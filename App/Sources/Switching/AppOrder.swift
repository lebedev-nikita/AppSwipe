import AppKit

/// Running apps with a Dock icon, most recently used first, like the Cmd-Tab order.
///
/// macOS has no public API for the Cmd-Tab order, so the order before OpenSwipe launched is a guess
/// from the on-screen window stacking order; activations after that are tracked exactly.
@MainActor
final class AppOrder {
    private var order: [pid_t] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        order = Self.initialOrder()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.moveToFront(pid) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.order.removeAll { $0 == pid } }
        })
    }

    /// The apps to show in the App Switcher. The frontmost app comes first.
    func apps() -> [NSRunningApplication] {
        if let front = NSWorkspace.shared.frontmostApplication { moveToFront(front.processIdentifier) }
        let running = Self.switchableApps()
        let byPID = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(order)
        // Apps that launched without ever activating go last.
        order += running.map(\.processIdentifier).filter { !known.contains($0) }
        order.removeAll { byPID[$0] == nil }
        return order.compactMap { byPID[$0] }
    }

    private func moveToFront(_ pid: pid_t) {
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
    }

    private static func switchableApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != me
        }
    }

    /// The frontmost app, then apps in the stacking order of their on-screen windows.
    private static func initialOrder() -> [pid_t] {
        var order: [pid_t] = []
        if let front = NSWorkspace.shared.frontmostApplication { order.append(front.processIdentifier) }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for window in windows where window[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, !order.contains(pid) else { continue }
            order.append(pid)
        }
        return order
    }
}
