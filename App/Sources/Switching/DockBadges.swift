import AppKit
import ApplicationServices

/// The badges macOS shows on Dock icons, such as unread counts, read through the Dock's
/// accessibility interface.
enum DockBadges {
    /// Badge text by app bundle path. Blocks on the Dock, so call it off the main thread.
    nonisolated static func current(dockPID: pid_t) -> [String: String] {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, 0.25)
        var badges: [String: String] = [:]
        for list in children(of: dock) where string(list, kAXRoleAttribute) == kAXListRole {
            for item in children(of: list) {
                guard let label = string(item, "AXStatusLabel"), !label.isEmpty,
                      let url = value(item, kAXURLAttribute) as? URL
                else { continue }
                badges[path(of: url)] = label
            }
        }
        return badges
    }

    nonisolated static func path(of url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private nonisolated static func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private nonisolated static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
