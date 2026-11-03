import AppKit
import SwiftUI

/// The Settings window, created on first use.
@MainActor
final class SettingsWindow {
    let trial = StepTrial()
    private let conflicts = TrackpadConflicts()
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(
            rootView: SettingsView(preferences: .shared, conflicts: conflicts, trial: trial))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "OpenSwipe Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
