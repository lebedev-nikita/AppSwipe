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

    @MainActor
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
