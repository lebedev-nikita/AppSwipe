import AppKit
import ApplicationServices

/// One window in the Window Switcher.
struct WindowEntry: @unchecked Sendable {
    let element: AXUIElement
    /// The window number, for capturing a Window Preview; nil if macOS doesn't tell.
    let id: CGWindowID?
    /// In screen coordinates with the origin at the top left of the main display.
    let frame: CGRect
    /// The window's title, or the app's name for an untitled window.
    let title: String
    let isMinimized: Bool
    /// A floating panel, such as a tool palette, rather than an ordinary window or dialog.
    let isPanel: Bool
}

/// An app's windows on the Current Space, read through Accessibility.
///
/// Accessibility only lists windows on the Spaces shown right now, plus minimized ones, which is what
/// the Window Switcher shows. The first query to an app takes 15–60 ms to open the connection and later
/// ones well under a millisecond, so connections are opened ahead of time with `warmUp`.
@MainActor
final class WindowList {
    private static let ordinary: Set<String> = [kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole]
    private static let panels: Set<String> = [kAXFloatingWindowSubrole, kAXSystemFloatingWindowSubrole]
    private static let attributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute, kAXSizeAttribute,
        kAXPositionAttribute,
    ] as CFArray

    private var elements: [pid_t: AXUIElement] = [:]

    /// Ordinary windows and dialogs first, front to back; then panels; then minimized windows.
    func windows(of app: NSRunningApplication) -> [WindowEntry] {
        let element = self.element(for: app.processIdentifier)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return [] }
        let appName = app.localizedName ?? ""
        let entries = windows.compactMap { Self.entry(for: $0, appName: appName) }
        // A stable sort keeps the front-to-back order within each group.
        return entries.enumerated().sorted { lhs, rhs in
            let (left, right) = (Self.group(lhs.element), Self.group(rhs.element))
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Opens the accessibility connections to `pids` in the background.
    nonisolated static func warmUp(_ pids: [pid_t]) {
        Task.detached(priority: .utility) {
            for pid in pids {
                let element = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(element, 0.5)
                var value: AnyObject?
                _ = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
            }
        }
    }

    private func element(for pid: pid_t) -> AXUIElement {
        if let element = elements[pid] { return element }
        let element = AXUIElementCreateApplication(pid)
        // A hung app must not freeze the Switcher.
        AXUIElementSetMessagingTimeout(element, 0.1)
        elements[pid] = element
        return element
    }

    private static func group(_ entry: WindowEntry) -> Int {
        entry.isMinimized ? 2 : entry.isPanel ? 1 : 0
    }

    private static func entry(for window: AXUIElement, appName: String) -> WindowEntry? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(window, attributes, AXCopyMultipleAttributeOptions(), &values)
                == .success,
              let values = values as? [AnyObject], values.count == 6,
              values[0] as? String == kAXWindowRole
        else { return nil }
        let subrole = values[1] as? String ?? ""
        // Popups and other transient windows have other subroles.
        guard ordinary.contains(subrole) || panels.contains(subrole) else { return nil }
        var size = CGSize.zero
        var origin = CGPoint.zero
        if CFGetTypeID(values[4]) == AXValueGetTypeID() { AXValueGetValue(values[4] as! AXValue, .cgSize, &size) }
        if CFGetTypeID(values[5]) == AXValueGetTypeID() { AXValueGetValue(values[5] as! AXValue, .cgPoint, &origin) }
        guard size.width >= 20, size.height >= 20 else { return nil }
        let title = (values[2] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName
        return WindowEntry(
            element: window, id: AXWindowID.of(window), frame: CGRect(origin: origin, size: size), title: title,
            isMinimized: values[3] as? Bool ?? false, isPanel: panels.contains(subrole))
    }
}

/// Brings windows forward through Accessibility.
@MainActor
enum WindowActivator {
    /// Raises the window above the app's others and makes it the app's main window.
    static func raise(_ window: WindowEntry, of app: NSRunningApplication) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if !app.isActive { app.activate() }
    }

    /// Commit: un-minimizes the window if needed, then raises it.
    static func focus(_ window: WindowEntry, of app: NSRunningApplication) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        raise(window, of: app)
    }
}
