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
    private let preferences = Preferences.shared
    private let settings = SettingsWindow()
    private let sessionInputTap = SessionInputTap()
    private lazy var switchController = SwitchController(inputTap: sessionInputTap, trial: settings.trial)
    private lazy var gestureTap = GestureEventTap { [weak self] frame in self?.handle(frame) }
    private var recorder: TouchRecorder?
    private let eventTypeProbe = EventTypeProbe()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        DiagnosticLog.write(
            "launched OpenSwipe \(version) on \(ProcessInfo.processInfo.operatingSystemVersionString); "
                + "accessibility \(Permissions.hasAccessibility), input monitoring \(Permissions.canListenToInput), "
                + "screen recording \(Permissions.hasScreenRecording)")
        setUpStatusItem()
        observePreferences()
        Permissions.requestAccessibility()
        switchController.warmUp()
        startInputTaps()
        watchPermissions()
        if preferences.isFirstLaunch { settings.show() }
        #if DEBUG
        let preview = UserDefaults.standard.integer(forKey: "PreviewSwitcher")
        if preview > 0 { switchController.preview(.apps, selection: preview) }
        let windowPreview = UserDefaults.standard.integer(forKey: "PreviewWindowSwitcher")
        if windowPreview > 0 {
            let app = UserDefaults.standard.string(forKey: "PreviewWindowsOf")
            switchController.preview(.windows, selection: windowPreview, of: app)
        }
        if UserDefaults.standard.bool(forKey: "CursorProbe") { probeCursorHiding() }
        if UserDefaults.standard.bool(forKey: "ThemeTest") { switchController.themeTest() }
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

    private func handle(_ frame: TouchFrame) {
        recorder?.record(frame)
        switchController.handle(frame)
    }

    /// Logs permission changes and reinstalls the tap when they happen, since a tap created
    /// before access was granted may never receive events.
    private func watchPermissions() {
        Task {
            var state = (Permissions.hasAccessibility, Permissions.canListenToInput)
            var screenRecording = Permissions.hasScreenRecording
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Permissions.hasScreenRecording != screenRecording {
                    screenRecording.toggle()
                    DiagnosticLog.write("permissions changed: screen recording \(screenRecording)")
                }
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

    /// Opening OpenSwipe again, as from Finder or Spotlight, shows Settings, the way back when the menu
    /// bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    /// Applies the settings that live here, now and whenever they change.
    private func observePreferences() {
        withObservationTracking {
            statusItem?.isVisible = preferences.showMenuBarIcon
            if preferences.recordTouches { startRecording() } else { recorder = nil }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePreferences() }
        }
    }

    private func startRecording() {
        guard recorder == nil else { return }
        recorder = TouchRecorder()
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
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        let pause = menu.addItem(
            withTitle: String(localized: "Pause OpenSwipe"), action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = preferences.isPaused ? .on : .off
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit OpenSwipe"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
    }

    @objc private func showSettings() {
        settings.show()
    }

    @objc private func togglePause() {
        preferences.isPaused.toggle()
    }
}
