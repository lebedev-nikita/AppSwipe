import AppKit

@main
@MainActor
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let recorder = TouchRecorder()
    private lazy var gestureTap = GestureEventTap { [recorder] frame in recorder.record(frame) }
    private let eventTypeProbe = EventTypeProbe()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        DiagnosticLog.write(
            "launched OpenSwipe \(version) on \(ProcessInfo.processInfo.operatingSystemVersionString); "
                + "accessibility \(Permissions.hasAccessibility), input monitoring \(Permissions.canListenToInput)")
        setUpStatusItem()
        Permissions.requestAccessibility()
        startGestureTap()
        watchPermissions()
    }

    /// Logs permission changes and reinstalls the tap when they happen, since a tap created
    /// before access was granted may never receive events.
    private func watchPermissions() {
        Task {
            var state = (Permissions.hasAccessibility, Permissions.canListenToInput)
            while true {
                try? await Task.sleep(for: .seconds(1))
                let current = (Permissions.hasAccessibility, Permissions.canListenToInput)
                guard current != state else { continue }
                state = current
                DiagnosticLog.write("permissions changed: accessibility \(current.0), input monitoring \(current.1)")
                gestureTap.stop()
                startGestureTap()
            }
        }
    }

    /// The tap can only be created once the user grants access, so keep trying until then.
    private func startGestureTap() {
        Task {
            var loggedWait = false
            while !gestureTap.start() {
                if !loggedWait {
                    DiagnosticLog.write("gesture tap unavailable, waiting for permission")
                    loggedWait = true
                }
                try? await Task.sleep(for: .seconds(1))
            }
            DiagnosticLog.write(
                "gesture tap installed; accessibility \(Permissions.hasAccessibility), "
                    + "input monitoring \(Permissions.canListenToInput)")
            _ = eventTypeProbe.start()
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "OpenSwipe")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "OpenSwipe (development build)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let accessibility = menu.addItem(
            withTitle: Permissions.hasAccessibility ? "Accessibility: Granted" : "Accessibility: Not Granted…",
            action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibility.target = self
        menu.addItem(
            withTitle: gestureTap.isRunning ? "Touch Input: Running" : "Touch Input: Waiting for Permission",
            action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Logs in Finder", action: #selector(showLogs), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit OpenSwipe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func showLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.directory])
    }
}
