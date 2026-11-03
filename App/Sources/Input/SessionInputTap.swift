import AppKit

/// An active event tap that runs only during a Switch Session. It swallows trackpad gestures,
/// scrolling and mouse movement so the app under the pointer doesn't react, and turns Esc into Cancel.
///
/// It stays disabled the rest of the time because an active tap in the HID stream delays the cursor.
@MainActor
final class SessionInputTap {
    var onEscape: () -> Void = {}

    private static let escape: Int64 = 53
    private static let types: [CGEventType] = [
        .keyDown, .keyUp, .scrollWheel, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue, let port else { return }
            CGEvent.tapEnable(tap: port, enable: isEnabled)
        }
    }

    /// Must run before `GestureEventTap.start()`: of two taps at the same spot, the one created last
    /// sees events first, and the gesture tap has to read touches before this one swallows them.
    func install() -> Bool {
        guard port == nil else { return true }
        let gesture = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
        let mask = Self.types.reduce(gesture) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
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
        CGEvent.tapEnable(tap: port, enable: isEnabled)
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
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

    private func shouldSwallow(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isEnabled, let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .keyDown, .keyUp:
            guard isEnabled, event.getIntegerValueField(.keyboardEventKeycode) == Self.escape else { return false }
            if type == .keyDown { onEscape() }
            return true
        default:
            return isEnabled
        }
    }
}
