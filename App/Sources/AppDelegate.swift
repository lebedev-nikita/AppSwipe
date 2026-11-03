import AppKit
import SwitchCore

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
    private static let recordTouchesKey = "RecordTouches"

    private let sessionInputTap = SessionInputTap()
    private lazy var switchController = SwitchController(inputTap: sessionInputTap)
    private lazy var gestureTap = GestureEventTap { [weak self] frame in self?.handle(frame) }
    private var recorder: TouchRecorder?
    private let eventTypeProbe = EventTypeProbe()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        DiagnosticLog.write(
            "launched OpenSwipe \(version) on \(ProcessInfo.processInfo.operatingSystemVersionString); "
                + "accessibility \(Permissions.hasAccessibility), input monitoring \(Permissions.canListenToInput)")
        setUpStatusItem()
        if UserDefaults.standard.bool(forKey: Self.recordTouchesKey) { startRecording() }
        Permissions.requestAccessibility()
        switchController.warmUp()
        startInputTaps()
        watchPermissions()
        #if DEBUG
        let preview = UserDefaults.standard.integer(forKey: "PreviewSwitcher")
        if preview > 0 { switchController.preview(selection: preview) }
        if UserDefaults.standard.bool(forKey: "CursorProbe") { probeCursorHiding() }
        if UserDefaults.standard.bool(forKey: "GlassTest") {
            switchController.glassTest(native: UserDefaults.standard.bool(forKey: "GlassTestNative"))
        }
        #endif
    }

    #if DEBUG
    /// Hides the cursor the public way, then with `BackgroundCursor`, three seconds each.
    private func probeCursorHiding() {
        Task {
            let location = NSEvent.mouseLocation
            DiagnosticLog.write("cursor probe: pointer at \(location.x), \(location.y); public hide")
            CGDisplayHideCursor(CGMainDisplayID())
            try? await Task.sleep(for: .seconds(3))
            CGDisplayShowCursor(CGMainDisplayID())
            try? await Task.sleep(for: .seconds(1))
            DiagnosticLog.write("cursor probe: private property set \(BackgroundCursor.allowHiding()); hide")
            CGDisplayHideCursor(CGMainDisplayID())
            try? await Task.sleep(for: .seconds(3))
            CGDisplayShowCursor(CGMainDisplayID())
            DiagnosticLog.write("cursor probe: done")
        }
    }
    #endif

    #if DEBUG
    #endif

    private func handle(_ frame: TouchFrame) {
        recorder?.record(frame)
        switchController.handle(frame)
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
                sessionInputTap.uninstall()
                startInputTaps()
            }
        }
    }

    /// The taps can only be created once the user grants access, so keep trying until then.
    private func startInputTaps() {
        Task {
            var loggedWait = false
            // The session tap goes first; see `SessionInputTap.install()`.
            while !(sessionInputTap.install() && gestureTap.start()) {
                if !loggedWait {
                    DiagnosticLog.write("gesture tap unavailable, waiting for permission")
                    loggedWait = true
                }
                try? await Task.sleep(for: .seconds(1))
            }
            DiagnosticLog.write(
                "input taps installed; accessibility \(Permissions.hasAccessibility), "
                    + "input monitoring \(Permissions.canListenToInput)")
        }
    }

    private func startRecording() {
        recorder = recorder ?? TouchRecorder()
        if !eventTypeProbe.start() { DiagnosticLog.write("event type probe unavailable") }
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
        let live = menu.addItem(withTitle: "Live Switching", action: #selector(toggleLiveSwitching), keyEquivalent: "")
        live.target = self
        live.state = UserDefaults.standard.bool(forKey: SwitchController.liveSwitchingKey) ? .on : .off
        let record = menu.addItem(withTitle: "Record Touches", action: #selector(toggleRecording), keyEquivalent: "")
        record.target = self
        record.state = recorder == nil ? .off : .on
        menu.addItem(withTitle: "Show Logs in Finder", action: #selector(showLogs), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit OpenSwipe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func toggleLiveSwitching() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: SwitchController.liveSwitchingKey), forKey: SwitchController.liveSwitchingKey)
    }

    @objc private func toggleRecording() {
        let isOn = recorder == nil
        UserDefaults.standard.set(isOn, forKey: Self.recordTouchesKey)
        if isOn { startRecording() } else { recorder = nil }
    }

    @objc private func showLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.directory])
    }
}
