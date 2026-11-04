import AppKit
import SwitchCore

/// Turns trackpad gesture events into touch frames, through a listen-only event tap.
///
/// See docs/adr/0003-touch-input-and-private-apis.md for why touches come from an event tap.
@MainActor
final class GestureEventTap {
    private let onFrame: (TouchFrame) -> Void
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var touchIDs = TouchIDs()
    private var loggedFirstEvent = false

    init(onFrame: @escaping (TouchFrame) -> Void) {
        self.onFrame = onFrame
    }

    var isRunning: Bool { port != nil }

    /// Installs the tap on the main run loop. Fails while the app lacks permission to tap input.
    func start() -> Bool {
        guard port == nil else { return true }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            MainActor.assumeIsolated {
                let tap = Unmanaged<GestureEventTap>.fromOpaque(userInfo!).takeUnretainedValue()
                tap.handle(type, event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
        loggedFirstEvent = false
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DiagnosticLog.write("gesture tap disabled (type \(type.rawValue)), re-enabling")
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }
        guard type.rawValue == NSEvent.EventType.gesture.rawValue else { return }
        let nsEvent = NSEvent(cgEvent: event)
        // Direct touches come from touch screens and the Touch Bar, not from trackpads.
        let touches: Set<NSTouch> = nsEvent?.allTouches().filter { $0.type == .indirect } ?? []
        if !loggedFirstEvent {
            loggedFirstEvent = true
            DiagnosticLog.write(
                "first gesture event: converted \(nsEvent != nil), "
                    + "\(nsEvent?.allTouches().count ?? 0) touches, \(touches.count) indirect")
        }
        guard let nsEvent else { return }
        // macOS sends empty gesture events between real ones.
        guard let first = touches.first else { return }
        // TODO: `normalizedPosition` raises an Objective-C exception for touches forwarded by
        // Universal Control, which Swift cannot catch.
        let frame = TouchFrame(
            time: nsEvent.timestamp,
            surface: Size(width: millimetres(first.deviceSize.width), height: millimetres(first.deviceSize.height)),
            touches: touches.map { touch in
                Touch(
                    id: touchIDs.id(for: touch),
                    x: touch.normalizedPosition.x,
                    y: touch.normalizedPosition.y,
                    phase: Touch.Phase(touch.phase),
                    isResting: touch.isResting)
            }
            .sorted { $0.id < $1.id })
        touchIDs.forgetLifted(touches)
        onFrame(frame)
    }

    /// `NSTouch.deviceSize` is in points, 1/72 of an inch.
    private func millimetres(_ points: CGFloat) -> Double {
        points * 25.4 / 72
    }
}

/// Hands out small integers for `NSTouch.identity`, which is an opaque object.
private struct TouchIDs {
    private var ids: [NSObject: Int] = [:]
    private var next = 1

    mutating func id(for touch: NSTouch) -> Int {
        let key = touch.identity as! NSObject
        if let id = ids[key] { return id }
        defer { next += 1 }
        ids[key] = next
        return next
    }

    mutating func forgetLifted(_ touches: Set<NSTouch>) {
        for touch in touches where touch.phase == .ended || touch.phase == .cancelled {
            ids[touch.identity as! NSObject] = nil
        }
        if ids.isEmpty { next = 1 }
    }
}

private extension Touch.Phase {
    init(_ phase: NSTouch.Phase) {
        self = switch phase {
        case .began: .began
        case .moved: .moved
        case .stationary: .stationary
        case .ended: .ended
        default: .cancelled
        }
    }
}
