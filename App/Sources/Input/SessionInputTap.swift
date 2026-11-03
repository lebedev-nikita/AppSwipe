import AppKit

/// An active event tap that keeps a swipe from reaching the app under the pointer.
///
/// It is off unless enough fingers for a Switcher are down, because an active tap in the HID stream
/// delays the cursor. With the fingers down, it stops the pointer from moving. During a Switch Session
/// it also swallows gestures, scrolling, clicks and pressure, and turns Esc into Cancel.
@MainActor
final class SessionInputTap {
    enum Mode {
        case off
        /// Fingers that may start a session are down: only pointer movement is swallowed.
        case fingersDown
        case session
    }

    var onEscape: () -> Void = {}

    private static let escape: Int64 = 53
    private static let movement: Set<CGEventType> = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private static let presses: Set<CGEventType> = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    private static let releases: Set<CGEventType> = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
    /// Trackpad gestures, and the pressure of a Force Click.
    private static let gestureTypes: [UInt32] = [UInt32(NSEvent.EventType.gesture.rawValue), 34]

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// A click that began during a session, whose release must be swallowed too, even once the
    /// session is over, so the app under the pointer never sees half a click.
    private var swallowingRelease = false

    var mode = Mode.off {
        didSet { updateEnabled() }
    }

    /// Must run before `GestureEventTap.start()`: of two taps at the same spot, the one created last
    /// sees events first, and the gesture tap has to read touches before this one swallows them.
    func install() -> Bool {
        guard port == nil else { return true }
        let types = [CGEventType.keyDown, .keyUp, .scrollWheel].map(\.rawValue)
            + Self.movement.map(\.rawValue) + Self.presses.map(\.rawValue) + Self.releases.map(\.rawValue)
            + Self.gestureTypes
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let swallow = MainActor.assumeIsolated {
                Unmanaged<SessionInputTap>.fromOpaque(userInfo!).takeUnretainedValue().shouldSwallow(type, event)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
        isTapEnabled = true
        updateEnabled()
        return true
    }

    func uninstall() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    private var isTapEnabled = false

    private var wantsEnabled: Bool { mode != .off || swallowingRelease }

    private func updateEnabled() {
        guard let port, isTapEnabled != wantsEnabled else { return }
        isTapEnabled = wantsEnabled
        CGEvent.tapEnable(tap: port, enable: isTapEnabled)
    }

    private func shouldSwallow(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if wantsEnabled, let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        if Self.releases.contains(type), swallowingRelease {
            swallowingRelease = false
            updateEnabled()
            return true
        }
        switch mode {
        case .off:
            return false
        case .fingersDown:
            return Self.movement.contains(type)
        case .session:
            if type == .keyDown || type == .keyUp {
                guard event.getIntegerValueField(.keyboardEventKeycode) == Self.escape else { return false }
                if type == .keyDown { onEscape() }
                return true
            }
            if Self.presses.contains(type) { swallowingRelease = true }
            return true
        }
    }
}
