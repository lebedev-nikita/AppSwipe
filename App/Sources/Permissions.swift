import AppKit
import ApplicationServices

enum Permissions {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Whether macOS lets the app observe input events (Input Monitoring).
    static var canListenToInput: Bool { CGPreflightListenEventAccess() }

    /// Shows the system Accessibility prompt if access is missing. Returns whether access is granted.
    @discardableResult
    static func requestAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Needed only for Window Previews. A grant takes effect after the app relaunches.
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system Screen Recording prompt if access is missing.
    static func requestScreenRecording() {
        if !hasScreenRecording { CGRequestScreenCaptureAccess() }
    }

    @MainActor
    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
