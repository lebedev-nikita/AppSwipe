import AppKit

/// Switches to an app the way a click on its Dock icon does: the app comes forward with its windows,
/// unhides, and restores or opens a window if none is visible.
@MainActor
enum AppActivator {
    /// Brings the app forward without anything a Dock click adds: no window opens or un-minimizes.
    /// For apps the Selection passes over during Live Switching.
    static func bringForward(_ app: NSRunningApplication) {
        guard !isSelf(app) else {
            activateSelf(restoringMinimized: false)
            return
        }
        bringForward(app, options: .activateAllWindows)
    }

    /// Activates the app on behalf of the app in front. A plain `activate` is ignored while Settings
    /// make AppSwipe a regular app, but activating from the frontmost app works either way (checked on
    /// macOS 27.0.1).
    static func bringForward(_ app: NSRunningApplication, options: NSApplication.ActivationOptions) {
        if let front = NSWorkspace.shared.frontmostApplication, front != app {
            app.activate(from: front, options: options)
        } else {
            app.activate(options: options)
        }
    }

    static func activate(_ app: NSRunningApplication) {
        guard !isSelf(app) else {
            activateSelf(restoringMinimized: true)
            return
        }
        guard let url = app.bundleURL else {
            bringForward(app, options: [])
            return
        }
        // Opening a running app activates it and sends it the same reopen event as a Dock click.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        let name = app.localizedName ?? url.lastPathComponent
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in DiagnosticLog.write("cannot activate \(name): \(error.localizedDescription)") }
        }
    }

    /// AppSwipe itself, listed while Settings is open.
    static func isSelf(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == NSRunningApplication.current.processIdentifier
    }

    /// Activating itself the way it activates other apps is cooperative, and the app in front never
    /// yields, so AppSwipe forces it, as Settings does when it opens.
    static func activateSelf(restoringMinimized: Bool) {
        // Switchers are borderless panels, which can't become main.
        let windows = NSApp.windows.filter(\.canBecomeMain)
        if restoringMinimized, !windows.contains(where: \.isVisible) {
            windows.first(where: \.isMiniaturized)?.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        for window in windows.reversed() where window.isVisible { window.orderFront(nil) }
        windows.first(where: \.isVisible)?.makeKey()
    }
}
