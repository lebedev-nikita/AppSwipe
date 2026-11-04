import AppKit
import SwitchCore

/// Runs Switch Sessions: feeds touch frames to the recognizer, drives the Switcher panels, and
/// commits the Selection.
///
/// A session opens the App Switcher, and a swipe down shows the Window Switcher for an app under it.
/// The App Switcher appears the moment a session opens. To make that instant, it is laid out ahead of
/// time, whenever the app list changes.
@MainActor
final class SwitchController {
    private struct AppContents {
        let apps: [NSRunningApplication]
        let preparedAt: ContinuousClock.Instant
        /// Whether Finder was left out for having no windows.
        let hidesFinder: Bool
        /// The displays the apps were listed from.
        let displays: DisplayScope
    }

    private enum Targets {
        case apps([NSRunningApplication])
        case windows(NSRunningApplication, [WindowEntry])

        var count: Int {
            switch self {
            case .apps(let apps): apps.count
            case .windows(_, let windows): windows.count
            }
        }
    }

    /// One open Switcher and its Selection.
    private struct Level {
        let targets: Targets
        let panel: SwitcherPanel
        var selection: SwitchSession
        /// Items Live Switching may bring forward while passing over them; nil without Live Switching.
        var passable: Set<Int>?
        /// The Item Live Switching last brought forward.
        var inFront = 0
        /// The Selection moves by the travel past this.
        var origin = 0.0
    }

    private struct Session {
        /// The Switcher the swipe opened.
        var root: Level
        /// The windows of the app selected in the App Switcher, opened under it by a swipe down. While
        /// they show, they have the Selection.
        var windows: Level?
        /// The travel of the latest move.
        var travel = 0.0

        /// The Level with the Selection.
        var current: Level {
            get { windows ?? root }
            set { if windows != nil { windows = newValue } else { root = newValue } }
        }
    }

    /// Rebuild app contents older than this when fingers land, in case something changed unnoticed,
    /// such as an app's icon.
    private static let appContentsLifetime = Duration.seconds(60)

    private let inputTap: SessionInputTap
    private let trial: StepTrial
    private let preferences = Preferences.shared
    private let screenLock = ScreenLock()
    private let appPanel = SwitcherPanel()
    private let windowPanel = SwitcherPanel()
    private let cursor = CursorFreeze()
    private let appOrder = AppOrder()
    private let windowList = WindowList()
    private let previews = WindowPreviews()
    private var windowContentsCount = 0
    private var previewCapture: Task<Void, Never>?
    private let clock = ContinuousClock()
    private var recognizer = SwipeRecognizer()
    private var contents: AppContents?
    private var contentsCount = 0
    private var session: Session?
    /// The fingers whose landing froze the pointer, while no session has opened yet.
    private var armedFingers: Int?
    /// A swipe over the Step trial strip in Settings, which moves its dots instead of a Switcher.
    private var trialSession: SwitchSession?
    /// Dock badges by app bundle path, from the previous refresh, shown until fresh ones arrive.
    private var badges: [String: String] = [:]

    init(inputTap: SessionInputTap, trial: StepTrial) {
        self.inputTap = inputTap
        self.trial = trial
        inputTap.onEscape = { [weak self] in self?.cancel() }
        appOrder.onChange = { [weak self] in self?.appsChanged() }
    }

    /// Re-lays out the App Switcher on the next turn of the run loop, unless a session is showing.
    private func appsChanged() {
        contents = nil
        Task { [weak self] in
            guard let self, session == nil, contents == nil else { return }
            prepareApps()
            WindowList.warmUp(appOrder.apps().map(\.processIdentifier))
            capturePreviewsSoon()
        }
    }

    /// Captures the frontmost app's windows a moment after it activates, so its Window Previews are
    /// ready before the next swipe, and drops previews of windows that are gone.
    private func capturePreviewsSoon() {
        previewCapture?.cancel()
        previewCapture = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled, session == nil, let app = appOrder.frontmost else { return }
            let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            previews.forget(allBut: Set(all.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }))
            previews.refresh(windowList.windows(of: app), pid: app.processIdentifier) { _, _ in }
        }
    }

    /// Creates and lays out the panels once, so the first swipe doesn't pay for it.
    func warmUp() {
        prepareApps()
        if let front = appOrder.frontmost { prepareWindows(of: front) }
        WindowList.warmUp(appOrder.apps().map(\.processIdentifier))
    }

    func handle(_ frame: TouchFrame) {
        if let armedFingers, frame.fingersDown.count < armedFingers { disarm() }
        recognizer.settings.ignoresPalms = preferences.ignorePalms
        switch recognizer.handle(frame) {
        case .armed(let fingers):
            guard session == nil else { return }
            arm(fingers)
            guard fingers == preferences.fingers else { return }
            // Apps on the pointer's display depend on where the pointer and the windows are now.
            if let contents, clock.now - contents.preparedAt < Self.appContentsLifetime,
               contents.hidesFinder == shouldHideFinder(), contents.displays == .all,
               preferences.appDisplays == .all {
                refreshBadges(apps: contents.apps, contents: contentsCount)
            } else {
                prepareApps()
            }
        case .began(let fingers, let direction, let time):
            if trial.isUnderPointer {
                trialSession = SwitchSession(
                    itemCount: StepTrial.dots, direction: direction, began: time, settings: sessionSettings)
                trial.selection = trialSession?.selection
                return
            }
            guard sessionsAllowed, fingers == preferences.fingers else { return }
            begin(direction: direction, at: time)
        case .beganDown(let fingers, let time):
            guard !trial.isUnderPointer, sessionsAllowed, fingers == preferences.fingers else { return }
            begin(direction: nil, at: time)
            openWindowsOfSelection()
        case .moved(let travel):
            if var trialSession {
                if trialSession.move(travel: travel) { trial.selection = trialSession.selection }
                self.trialSession = trialSession
                return
            }
            guard var session else { return }
            session.travel = travel
            var level = session.current
            if level.selection.move(travel: travel - level.origin) {
                level.panel.select(level.selection.selection)
                bringForward(level.selection.selection, in: &level)
            }
            session.current = level
            self.session = session
        case .swiped(let direction):
            guard trialSession == nil else { return }
            switch direction {
            case .down: openWindowsOfSelection()
            case .up: closeWindowsOfSelection()
            }
        case .ended(let time):
            if trialSession != nil {
                trialSession = nil
                trial.selection = nil
                disarm()
                return
            }
            end(at: time)
        case nil:
            break
        }
    }

    /// Whether swipes may open a Switcher now.
    private var sessionsAllowed: Bool {
        !preferences.isPaused && !screenLock.isLocked && !preferences.isExcluded(appOrder.frontmost)
    }

    /// Freezes the pointer when fingers that can open a Switcher land, so the swipe never moves it.
    private func arm(_ fingers: Int) {
        guard trial.isUnderPointer || (sessionsAllowed && fingers == preferences.fingers) else {
            disarm()
            return
        }
        armedFingers = fingers
        cursor.freeze()
        inputTap.mode = .fingersDown
    }

    /// Lets the pointer move again after fingers lift without opening a session.
    private func disarm() {
        guard armedFingers != nil else { return }
        armedFingers = nil
        if session == nil {
            inputTap.mode = .off
            cursor.release()
        }
    }

    private var sessionSettings: SwitchSession.Settings {
        var settings = SwitchSession.Settings()
        settings.stepLength = preferences.stepLength
        return settings
    }

    /// Whether the App Switcher should leave out Finder now: it is set to, Finder has no windows,
    /// minimized or on any Space, and isn't the Active App.
    private func shouldHideFinder() -> Bool {
        guard preferences.hideFinderWithoutWindows,
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              appOrder.frontmost != finder
        else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return !windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == finder.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            return (bounds["Width"] ?? 0) > 50 && (bounds["Height"] ?? 0) > 50
        }
    }

    #if DEBUG
    /// Shows the Window Switcher alone for a few seconds without a gesture, for checking its look.
    func previewWindows(selection: Int, of bundleID: String?) {
        guard let app = bundleID.flatMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first })
            ?? appOrder.frontmost
        else { return }
        let count = prepareWindows(of: app).count
        // Give the previews a moment to arrive.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            windowPanel.select(min(selection, count - 1))
            windowPanel.show()
            logPanelFrame(windowPanel)
            try? await Task.sleep(for: .seconds(6))
            windowPanel.hide()
        }
    }

    /// Shows the App Switcher for a few seconds without a gesture, for checking its look.
    func previewApps(selection: Int) {
        begin(direction: .right, at: ProcessInfo.processInfo.systemUptime)
        inputTap.mode = .off
        guard let session else { return }
        session.root.panel.select(selection)
        logPanelFrame(session.root.panel)
        Task {
            try? await Task.sleep(for: .seconds(6))
            finish()
        }
    }

    /// Logs the panel's frame in the top-left-origin coordinates `screencapture -R` takes.
    private func logPanelFrame(_ panel: SwitcherPanel) {
        let screenHeight = NSScreen.screens[0].frame.height
        let frame = panel.frame
        DiagnosticLog.write(
            "preview: panel at \(Int(frame.minX)),\(Int(screenHeight - frame.maxY)),"
                + "\(Int(frame.width)),\(Int(frame.height))")
    }

    /// Shows the App Switcher, then the Window Switcher over three demo windows of this app, over a
    /// made-up wallpaper, on a fixed timeline that a script captures for the README.
    func readmeShots() {
        let backdrop = GlassTestBackdrop(size: NSSize(width: 1280, height: 560), wallpaper: true)
        Task {
            backdrop.show()
            DiagnosticLog.write("readme shots: start, rect \(backdrop.captureRect)")
            try? await Task.sleep(for: .seconds(0.8))
            prepareApps()
            appPanel.select(2)
            appPanel.show()
            try? await Task.sleep(for: .seconds(0.6))
            DiagnosticLog.write("readme shots: app switcher")
            try? await Task.sleep(for: .seconds(1))
            appPanel.hide()

            let screen = NSScreen.screens[0].frame
            let titles = ["Lagoon.heic", "Dunes.heic", "Aurora.heic"]
            let windows = titles.enumerated().map { index, title in
                let size = NSSize(width: 520, height: 340)
                let origin = NSPoint(
                    x: screen.midX - 560 + CGFloat(index) * 300, y: screen.midY - 200 + CGFloat(index % 2) * 90)
                let window = NSWindow(
                    contentRect: NSRect(origin: origin, size: size), styleMask: [.titled, .closable, .miniaturizable],
                    backing: .buffered, defer: false)
                window.title = title
                window.contentView = WallpaperView(seed: index + 1)
                window.level = .floating
                window.isReleasedWhenClosed = false
                window.orderFrontRegardless()
                return window
            }
            // Windows are listed front to back; the last one opened is in front.
            try? await Task.sleep(for: .seconds(0.8))
            prepareWindows(of: NSRunningApplication.current)
            try? await Task.sleep(for: .seconds(1.2))
            windowPanel.select(1)
            windowPanel.show()
            try? await Task.sleep(for: .seconds(0.6))
            DiagnosticLog.write("readme shots: window switcher")
            try? await Task.sleep(for: .seconds(1))
            windowPanel.hide()
            windows.forEach { $0.close() }
            backdrop.hide()
            DiagnosticLog.write("readme shots: done")
        }
    }

    /// Shows the App Switcher in the light and then the dark appearance over a flat backdrop the colour
    /// of a photo, on a fixed timeline that a script captures.
    func themeTest() {
        let white = UserDefaults.standard.bool(forKey: "ThemeTestWhite")
        let backdrop = GlassTestBackdrop(
            size: NSSize(width: 1100, height: 440),
            flat: white ? NSColor(white: 0.99, alpha: 1) : NSColor(red: 0.42, green: 0.29, blue: 0.2, alpha: 1))
        Task {
            backdrop.show()
            DiagnosticLog.write("theme test: start, rect \(backdrop.captureRect)")
            try? await Task.sleep(for: .seconds(0.8))
            // "6;6:_scrimState=1" tries variant 6 alone, then with the scrim state set.
            let configs = (UserDefaults.standard.string(forKey: "ThemeTestConfigs") ?? "\(GlassMaterial.variant)")
                .split(separator: ";").map(String.init)
            for (index, config) in configs.enumerated() {
                let parts = config.split(separator: ":")
                let variant = Int(parts[0]) ?? GlassMaterial.variant
                let values = parts.dropFirst().first.map { list in
                    Dictionary(uniqueKeysWithValues: list.split(separator: ",").compactMap { pair -> (String, Int)? in
                        let kv = pair.split(separator: "=")
                        return kv.count == 2 ? (String(kv[0]), Int(kv[1]) ?? 0) : nil
                    })
                } ?? [:]
                for name in [NSAppearance.Name.aqua, .darkAqua] {
                    appPanel.setAppearance(NSAppearance(named: name))
                    appPanel.setGlassVariant(variant, values: values)
                    prepareApps()
                    appPanel.select(2)
                    appPanel.show()
                    try? await Task.sleep(for: .seconds(0.35))
                    DiagnosticLog.write("theme test: showing \(index)-\(name.rawValue)")
                    try? await Task.sleep(for: .seconds(0.25))
                    appPanel.hide()
                    try? await Task.sleep(for: .seconds(0.1))
                }
            }
            appPanel.setGlassVariant(GlassMaterial.variant, values: ["_scrimState": 0, "_subduedState": 0, "_adaptiveAppearance": 2])
            appPanel.setAppearance(nil)
            backdrop.hide()
            DiagnosticLog.write("theme test: done")
        }
    }

    /// Shows the App Switcher over a test backdrop, then, with `native`, the native Cmd-Tab switcher,
    /// on a fixed timeline that a script captures.
    func glassTest(native: Bool) {
        let backdrop = GlassTestBackdrop(size: NSSize(width: 1100, height: 440))
        Task {
            backdrop.show()
            DiagnosticLog.write("glass test: start, rect \(backdrop.captureRect)")
            try? await Task.sleep(for: .seconds(1))
            prepareApps()
            appPanel.select(1)
            appPanel.show()
            try? await Task.sleep(for: .seconds(0.3))
            DiagnosticLog.write("glass test: showing ours")
            try? await Task.sleep(for: .seconds(1.2))
            appPanel.hide()
            if native {
                GlassTestBackdrop.openNativeSwitcher()
                try? await Task.sleep(for: .seconds(0.6))
                DiagnosticLog.write("glass test: showing native")
                try? await Task.sleep(for: .seconds(0.8))
                GlassTestBackdrop.closeNativeSwitcher()
            }
            try? await Task.sleep(for: .seconds(0.5))
            backdrop.hide()
            DiagnosticLog.write("glass test: done")
        }
    }
    #endif

    // MARK: - Preparing

    /// Lays out the App Switcher with the current apps, without showing it.
    @discardableResult
    private func prepareApps() -> AppContents {
        let started = clock.now
        let hidesFinder = shouldHideFinder()
        let displays = preferences.appDisplays
        var apps = appOrder.apps().filter { !(hidesFinder && $0.bundleIdentifier == "com.apple.finder") }
        if displays == .pointer { apps = Self.onPointerDisplay(apps) }
        let paths = apps.map { $0.bundleURL.map(DockBadges.path(of:)) }
        let listed = clock.now
        appPanel.prepare(
            zip(apps, paths).map { app, path in
                SwitcherPanel.Item(
                    image: app.icon ?? NSImage(), title: app.localizedName ?? "", badge: path.flatMap { badges[$0] })
            },
            selection: -1)
        #if DEBUG
        DiagnosticLog.write(
            "timing: app list \(Self.milliseconds(listed - started)) ms, "
                + "layout \(Self.milliseconds(clock.now - listed)) ms, \(apps.count) apps")
        #endif
        contentsCount += 1
        refreshBadges(apps: apps, contents: contentsCount)
        let contents = AppContents(apps: apps, preparedAt: clock.now, hidesFinder: hidesFinder, displays: displays)
        self.contents = contents
        return contents
    }

    /// The Active App, first in `apps`, and the apps with a window on the Current Space of the display
    /// with the pointer. A window belongs to the display that shows most of it.
    private static func onPointerDisplay(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        let display = Displays.withPointer.frame
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var shown: Set<pid_t> = []
        for window in windows where window[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 50, frame.height > 50,
                  Displays.frame(showingMostOf: frame) == display
            else { continue }
            shown.insert(pid)
        }
        return apps.enumerated().filter { $0.offset == 0 || shown.contains($0.element.processIdentifier) }.map(\.element)
    }

    /// Lays out the Window Switcher with `app`'s windows, without showing it, and returns them.
    @discardableResult
    private func prepareWindows(of app: NSRunningApplication) -> [WindowEntry] {
        let started = clock.now
        var windows = windowList.windows(of: app)
        if preferences.windowDisplays == .pointer {
            let display = Displays.withPointer.frame
            windows = windows.filter { Displays.frame(showingMostOf: $0.frame) == display }
        }
        let listed = clock.now
        let icon = app.icon ?? NSImage()
        let appName = app.localizedName ?? ""
        windowPanel.prepare(
            windows.map { window in
                SwitcherPanel.Item(
                    image: icon, title: windowTitle(window.title, appName: appName), isDimmed: window.isMinimized,
                    aspect: window.frame.width / max(window.frame.height, 1), preview: previews.cached(window))
            },
            selection: -1)
        windowContentsCount += 1
        let id = windowContentsCount
        previewCapture?.cancel()
        previews.refresh(windows, pid: app.processIdentifier) { [weak self] index, image in
            // Only while the panel still holds these windows.
            guard let self, windowContentsCount == id else { return }
            windowPanel.setPreview(image, at: index)
        }
        #if DEBUG
        DiagnosticLog.write(
            "timing: window list \(Self.milliseconds(listed - started)) ms, "
                + "layout \(Self.milliseconds(clock.now - listed)) ms, \(windows.count) windows of \(app.localizedName ?? "?")")
        #endif
        return windows
    }

    // MARK: - Session

    /// Opens the App Switcher. Without a `direction`, as for a swipe down, the Selection starts on the
    /// Current Item.
    private func begin(direction: Direction?, at time: Double) {
        let eventAge = ProcessInfo.processInfo.systemUptime - time
        let started = clock.now
        // The contents stay valid for the next session unless the app list changes.
        let targets = Targets.apps((contents ?? prepareApps()).apps)
        let panel = appPanel
        let selection = direction.map {
            SwitchSession(itemCount: targets.count, direction: $0, began: time, settings: sessionSettings)
        } ?? SwitchSession(onCurrentItemOf: targets.count, settings: sessionSettings)
        panel.select(selection.selection)
        panel.show()
        // Usually already frozen where the fingers landed.
        cursor.freeze()
        cursor.hide()
        inputTap.mode = .session
        armedFingers = nil
        var level = Level(targets: targets, panel: panel, selection: selection)
        if preferences.liveSwitching {
            level.passable = Self.passableItems(targets)
            appOrder.freeze()
            bringForward(selection.selection, in: &level)
        }
        session = Session(root: level)
        #if DEBUG
        DiagnosticLog.write(
            "timing: event age \(Self.milliseconds(eventAge)) ms, "
                + "showing the apps panel \(Self.milliseconds(clock.now - started)) ms")
        #endif
    }

    /// Hands the Selection from the App Switcher to the selected app's windows, shown under it.
    private func openWindowsOfSelection() {
        guard var session, session.windows == nil, case .apps(let apps) = session.root.targets,
              apps.indices.contains(session.root.selection.selection)
        else { return }
        let app = apps[session.root.selection.selection]
        let windows = prepareWindows(of: app)
        SwitcherPanel.stack(appPanel, over: windowPanel)
        windowPanel.select(0)
        windowPanel.show()
        var level = Level(
            targets: .windows(app, windows), panel: windowPanel,
            selection: SwitchSession(choosingAmong: windows.count, settings: sessionSettings), inFront: -1,
            origin: session.travel)
        if session.root.passable != nil {
            // Like the App Switcher, Live Switching leaves hidden apps hidden.
            level.passable = app.isHidden ? [] : Self.passableItems(level.targets)
            bringForward(0, in: &level)
        }
        session.windows = level
        self.session = session
        #if DEBUG
        DiagnosticLog.write("opened \(windows.count) windows of \(app.localizedName ?? "?") from the apps")
        #endif
    }

    /// Hands the Selection back to the App Switcher, where it was.
    private func closeWindowsOfSelection() {
        guard var session, let windows = session.windows else { return }
        windows.panel.hide()
        session.root.panel.center()
        // Travel among the windows doesn't move the app Selection.
        session.root.origin += session.travel - windows.origin
        session.windows = nil
        self.session = session
    }

    /// Live Switching: brings the selected Item forward, if it may be while passing over it.
    private func bringForward(_ item: Int, in level: inout Level) {
        guard let passable = level.passable, item != level.inFront, passable.contains(item) else { return }
        switch level.targets {
        case .apps(let apps):
            AppActivator.bringForward(apps[item])
        case .windows(let app, let windows):
            WindowActivator.raise(windows[item], of: app)
        }
        cursor.reassertHidden()
        level.inFront = item
    }

    /// Items Live Switching brings forward while passing over them. The Active App always comes back.
    /// Other apps are skipped when hidden, or when their windows are all minimized or on other Spaces,
    /// so the screen doesn't jump between Spaces; minimized windows stay minimized.
    private static func passableItems(_ targets: Targets) -> Set<Int> {
        switch targets {
        case .apps(let apps):
            let passable = passableApps(apps)
            return Set(apps.indices.filter {
                $0 == 0 || (passable.contains(apps[$0].processIdentifier) && !apps[$0].isHidden)
            })
        case .windows(_, let windows):
            return Set(windows.indices.filter { !windows[$0].isMinimized })
        }
    }

    /// Apps with a window on the Current Space, or with no windows at all.
    private static func passableApps(_ apps: [NSRunningApplication]) -> Set<pid_t> {
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var onScreen: Set<pid_t> = []
        var withWindows: Set<pid_t> = []
        for window in windows where window[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 50, (bounds["Height"] ?? 0) > 50
            else { continue }
            withWindows.insert(pid)
            if window[kCGWindowIsOnscreen as String] as? Bool == true { onScreen.insert(pid) }
        }
        return Set(apps.map(\.processIdentifier).filter { onScreen.contains($0) || !withWindows.contains($0) })
    }

    private func end(at time: Double) {
        guard let session = finish() else { return }
        if let level = session.windows, case .windows(let app, let windows) = level.targets {
            switch level.selection.outcome(endedAt: time) {
            case .activate(let item):
                if app.isHidden { app.unhide() }
                WindowActivator.focus(windows[item], of: app)
            case .cancel:
                // No windows to choose from: switch to the app as a Dock click does.
                AppActivator.activate(app)
            }
            if session.root.passable != nil { appOrder.unfreeze(final: app.processIdentifier) }
            return
        }
        guard case .apps(let apps) = session.root.targets else { return }
        switch session.root.selection.outcome(endedAt: time) {
        case .activate(let item):
            AppActivator.activate(apps[item])
            if session.root.passable != nil { appOrder.unfreeze(final: apps[item].processIdentifier) }
        case .cancel:
            restore(after: session)
        }
    }

    private func cancel() {
        guard let session = finish() else { return }
        restore(after: session)
    }

    /// After Live Switching is cancelled, brings back the Active App or its window.
    private func restore(after session: Session) {
        guard session.root.passable != nil, case .apps(let apps) = session.root.targets else { return }
        if let level = session.windows, case .windows(let app, let windows) = level.targets, app == apps.first {
            // Among the Active App's own windows, those passed over stay raised: Accessibility can only
            // raise a window to the top, so putting them back would flash them over the current one.
            if level.inFront > 0, let current = windows.first { WindowActivator.raise(current, of: app) }
        } else if session.root.inFront != 0 || session.windows != nil, let active = apps.first {
            AppActivator.bringForward(active)
        }
        appOrder.unfreeze(final: nil)
    }

    @discardableResult
    private func finish() -> Session? {
        guard let session else { return nil }
        self.session = nil
        session.root.panel.hide()
        if let windows = session.windows {
            windows.panel.hide()
            // The App Switcher is laid out ahead of the next session, which opens it centred.
            session.root.panel.center()
        }
        cursor.release()
        inputTap.mode = .off
        // The app list may have changed while the panel was showing.
        if contents == nil { appsChanged() }
        return session
    }

    // MARK: - Badges

    private func refreshBadges(apps: [NSRunningApplication], contents id: Int) {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }
        let pid = dock.processIdentifier
        let paths = apps.map { $0.bundleURL.map(DockBadges.path(of:)) }
        Task {
            let badges = await Task.detached { DockBadges.current(dockPID: pid) }.value
            self.badges = badges
            // Only while the panel still holds the apps these paths describe.
            guard id == contentsCount else { return }
            var byItem: [Int: String] = [:]
            for (index, path) in paths.enumerated() {
                if let path, let badge = badges[path] { byItem[index] = badge }
            }
            appPanel.setBadges(byItem)
        }
    }

    #if DEBUG
    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return milliseconds(Double(seconds) + Double(attoseconds) / 1e18)
    }

    private static func milliseconds(_ seconds: Double) -> String {
        (seconds * 1000).formatted(.number.precision(.fractionLength(1)))
    }
    #endif
}
