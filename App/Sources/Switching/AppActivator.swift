import AppKit

/// Switches to an app the way a click on its Dock icon does: the app comes forward with its windows,
/// unhides, and restores or opens a window if none is visible.
@MainActor
enum AppActivator {
    /// Brings the app forward without anything a Dock click adds: no window opens or un-minimizes.
    /// For apps the Selection passes over during Live Switching.
    static func bringForward(_ app: NSRunningApplication) {
        app.activate(options: .activateAllWindows)
    }

    static func activate(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            app.activate()
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
}
