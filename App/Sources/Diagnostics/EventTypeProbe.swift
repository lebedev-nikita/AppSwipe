import AppKit

/// Counts the non-touch events around trackpad gestures, such as scrolling, swipes and the Dock's own
/// gesture events, and logs one line per burst of them.
@MainActor
final class EventTypeProbe {
    /// rotate, beginGesture, endGesture, scrollWheel, 30 (magnify, or the Dock's gesture events at the
    /// CGEvent level), swipe, smartMagnify, pressure.
    private static let types: [UInt32] = [18, 19, 20, 22, 30, 31, 32, 34]

    private var port: CFMachPort?
    private var counts: [UInt32: Int] = [:]
    private var lastEvent = Date.distantPast

    func start() -> Bool {
        guard port == nil else { return true }
        let mask = Self.types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1)) }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            MainActor.assumeIsolated {
                Unmanaged<EventTypeProbe>.fromOpaque(userInfo!).takeUnretainedValue().count(type)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        self.port = port
        Task { await flushBursts() }
        return true
    }

    private func count(_ type: CGEventType) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }
        counts[type.rawValue, default: 0] += 1
        lastEvent = .now
    }

    private func flushBursts() async {
        while true {
            try? await Task.sleep(for: .milliseconds(250))
            guard !counts.isEmpty, Date.now.timeIntervalSince(lastEvent) > 0.4 else { continue }
            let summary = counts.sorted { $0.key < $1.key }.map { "\(Self.name($0.key)) \($0.value)" }
            DiagnosticLog.write("other events: " + summary.joined(separator: ", "))
            counts.removeAll()
        }
    }

    private static func name(_ type: UInt32) -> String {
        switch type {
        case 18: "rotate"
        case 19: "beginGesture"
        case 20: "endGesture"
        case 22: "scrollWheel"
        case 30: "magnify/dock"
        case 31: "swipe"
        case 32: "smartMagnify"
        case 34: "pressure"
        default: "type \(type)"
        }
    }
}
