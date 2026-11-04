import AppKit
import SwiftUI

/// The Settings window, created on first use.
///
/// While it is open AppSwipe is a regular app, with a Dock icon and a place in Command-Tab and the
/// App Switcher, so the window can't get lost behind other apps.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    let trial = StepTrial()
    private let conflicts = TrackpadConflicts()
    private var window: NSWindow?
    /// The app in front before Settings opened, which gets the focus back when Settings closes.
    private var previousApp: NSRunningApplication?

    private static let contentSize = NSSize(width: 560, height: 640)

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { previousApp = NSWorkspace.shared.frontmostApplication }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NSApp.isActive, let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(
            rootView: SettingsView(preferences: .shared, conflicts: conflicts, trial: trial))
        controller.sizingOptions = [.minSize, .maxSize]
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "AppSwipe Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        fit(window)
        return window
    }

    /// Sizes the window to fit the screen it opens on, which may be shorter than the usual height.
    private func fit(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? window.screen else { return }
        let available = window.contentRect(forFrameRect: screen.visibleFrame).height
        window.setContentSize(NSSize(width: Self.contentSize.width, height: min(Self.contentSize.height, available)))
        window.center()
    }
}
