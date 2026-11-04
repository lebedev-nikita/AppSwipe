import AppKit

/// Running apps with a Dock icon, most recently used first, like the Cmd-Tab order.
///
/// macOS has no public API for the Cmd-Tab order, so the order before AppSwipe launched is a guess
/// from the on-screen window stacking order; activations after that are tracked exactly. The list is
/// kept current from workspace notifications, so reading it at the start of a swipe costs nothing.
///
/// AppSwipe itself is listed only while Settings is open and it is a regular app.
@MainActor
final class AppOrder {
    /// Called after the list or its order changes.
    var onChange: () -> Void = {}

    private var running: [pid_t: NSRunningApplication] = [:]
    private var order: [pid_t] = []
    private var observers: [NSObjectProtocol] = []
    /// During Live Switching, activations don't reorder the list, and for a moment after it neither do
    /// the late notifications of apps that were only passed over.
    private var frozen = false
    private var ignoreActivationsUntil = Date.distantPast
    private var allowedActivation: pid_t?
    private var policyObservation: NSKeyValueObservation?

    init() {
        for app in NSWorkspace.shared.runningApplications {
            running[app.processIdentifier] = app
        }
        running[Self.me.processIdentifier] = Self.me
        order = Self.initialOrder()
        observe(NSWorkspace.didLaunchApplicationNotification) { order, app in
            order.running[app.processIdentifier] = app
        }
        observe(NSWorkspace.didActivateApplicationNotification) { order, app in
            order.running[app.processIdentifier] = app
            guard !order.isIgnoringActivation(of: app.processIdentifier) else { return }
            order.moveToFront(app.processIdentifier)
        }
        observe(NSWorkspace.didTerminateApplicationNotification) { order, app in
            order.running[app.processIdentifier] = nil
            order.order.removeAll { $0 == app.processIdentifier }
        }
        // Settings opening or closing adds AppSwipe to the list or takes it out.
        policyObservation = Self.me.observe(\.activationPolicy) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                if Self.me.activationPolicy != .regular { self.order.removeAll { $0 == Self.me.processIdentifier } }
                self.onChange()
            }
        }
    }

    private static let me = NSRunningApplication.current

    /// The most recently activated app, which is the frontmost one outside Live Switching.
    var frontmost: NSRunningApplication? {
        order.lazy.compactMap { self.running[$0] }.first { !$0.isTerminated }
    }

    /// The apps to show in the App Switcher. The frontmost app comes first.
    func apps() -> [NSRunningApplication] {
        // Apps that launched without ever activating go last.
        let known = Set(order)
        order += running.keys.filter { !known.contains($0) }.sorted()
        order.removeAll { running[$0] == nil }
        return order.compactMap { running[$0] }.filter { $0.activationPolicy == .regular && !$0.isTerminated }
    }

    /// Keeps the order as it is while Live Switching activates apps the Selection passes over.
    func freeze() {
        frozen = true
    }

    /// Ends a freeze. Only `final`, the app switched to, if any, counts as used.
    func unfreeze(final: pid_t?) {
        frozen = false
        if let final { moveToFront(final) }
        allowedActivation = final
        ignoreActivationsUntil = Date.now.addingTimeInterval(1)
    }

    private func isIgnoringActivation(of pid: pid_t) -> Bool {
        frozen || (Date.now < ignoreActivationsUntil && pid != allowedActivation)
    }

    private func moveToFront(_ pid: pid_t) {
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
    }

    private func observe(
        _ name: Notification.Name, _ update: @escaping @MainActor (AppOrder, NSRunningApplication) -> Void
    ) {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated {
                // AppSwipe activates for its own panels too; only Settings, which makes it regular, counts.
                guard let self, app.processIdentifier != Self.me.processIdentifier || Self.me.activationPolicy == .regular
                else { return }
                update(self, Self.me.processIdentifier == app.processIdentifier ? Self.me : app)
                self.onChange()
            }
        })
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
