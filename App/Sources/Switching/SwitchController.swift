import AppKit
import SwitchCore

/// Runs Switch Sessions: feeds touch frames to the recognizer, drives the Switcher panels, and
/// commits the Selection.
///
/// A Switcher appears the moment a session opens. To make that instant, the App Switcher is laid out
/// ahead of time, whenever the app list changes, and the Window Switcher when four fingers land, while
/// they travel the few millimetres that open the session.
@MainActor
final class SwitchController {
    private struct AppContents {
        let apps: [NSRunningApplication]
        let preparedAt: ContinuousClock.Instant
    }

    private struct WindowContents {
        let app: NSRunningApplication
        let windows: [WindowEntry]
        let preparedAt: ContinuousClock.Instant
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

    private struct Session {
        let targets: Targets
        let panel: SwitcherPanel
        var selection: SwitchSession
        /// Items Live Switching may bring forward while passing over them; nil without Live Switching.
        var passable: Set<Int>?
        /// The Item Live Switching last brought forward.
        var inFront = 0
        /// Windows Live Switching raised, so their stacking order can be put back.
        var raised: Set<Int> = []
    }

    static let liveSwitchingKey = "LiveSwitching"

    /// Rebuild app contents older than this when fingers land, in case something changed unnoticed,
    /// such as an app's icon.
    private static let appContentsLifetime = Duration.seconds(60)
    /// Window contents prepared when the fingers landed are used if the session opens within this time.
    private static let windowContentsLifetime = Duration.seconds(1)

    private let inputTap: SessionInputTap
    private let appPanel = SwitcherPanel()
    private let windowPanel = SwitcherPanel()
    private let cursor = CursorFreeze()
    private let appOrder = AppOrder()
    private let windowList = WindowList()
    private let sessionSettings = SwitchSession.Settings()
    private let clock = ContinuousClock()
    private var recognizer = SwipeRecognizer()
    private var contents: AppContents?
    private var contentsCount = 0
    private var windowContents: WindowContents?
    private var session: Session?
    /// Dock badges by app bundle path, from the previous refresh, shown until fresh ones arrive.
    private var badges: [String: String] = [:]

    init(inputTap: SessionInputTap) {
        self.inputTap = inputTap
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
        }
    }

    /// Creates and lays out the panels once, so the first swipe doesn't pay for it.
    func warmUp() {
        prepareApps()
        prepareWindows()
        WindowList.warmUp(appOrder.apps().map(\.processIdentifier))
    }

    func handle(_ frame: TouchFrame) {
        switch recognizer.handle(frame) {
        case .armed(let fingers):
            guard session == nil else { return }
            switch SwitcherKind(fingers: fingers) {
            case .apps:
                if let contents, clock.now - contents.preparedAt < Self.appContentsLifetime {
                    refreshBadges(apps: contents.apps, contents: contentsCount)
                } else {
                    prepareApps()
                }
            case .windows:
                prepareWindows()
            case nil:
                break
            }
        case .began(let fingers, let direction, let time):
            guard let kind = SwitcherKind(fingers: fingers) else { return }
            begin(kind, direction: direction, at: time)
        case .moved(let travel):
            guard var session, session.selection.move(travel: travel) else { return }
            session.panel.select(session.selection.selection)
            bringForward(session.selection.selection, in: &session)
            self.session = session
        case .ended(let time):
            end(at: time)
        case nil:
            break
        }
    }

    #if DEBUG
    /// Shows a Switcher for a few seconds without a gesture, for checking its look.
    func preview(_ kind: SwitcherKind, selection: Int) {
        begin(kind, direction: .right, at: ProcessInfo.processInfo.systemUptime)
        inputTap.isEnabled = false
        guard let session else { return }
        session.panel.select(selection)
        let screenHeight = NSScreen.screens[0].frame.height
        let frame = session.panel.frame
        // In the top-left-origin coordinates `screencapture -R` takes.
        DiagnosticLog.write(
            "preview: panel at \(Int(frame.minX)),\(Int(screenHeight - frame.maxY)),"
                + "\(Int(frame.width)),\(Int(frame.height))")
        Task {
            try? await Task.sleep(for: .seconds(6))
            finish()
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
        let apps = appOrder.apps()
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
        let contents = AppContents(apps: apps, preparedAt: clock.now)
        self.contents = contents
        return contents
    }

    /// Lays out the Window Switcher with the Active App's windows, without showing it.
    @discardableResult
    private func prepareWindows() -> WindowContents? {
        guard let app = appOrder.frontmost ?? NSWorkspace.shared.frontmostApplication else { return nil }
        let started = clock.now
        let windows = windowList.windows(of: app)
        let listed = clock.now
        let icon = app.icon ?? NSImage()
        windowPanel.prepare(
            windows.map { SwitcherPanel.Item(image: icon, title: $0.title, isDimmed: $0.isMinimized) },
            selection: -1)
        #if DEBUG
        DiagnosticLog.write(
            "timing: window list \(Self.milliseconds(listed - started)) ms, "
                + "layout \(Self.milliseconds(clock.now - listed)) ms, \(windows.count) windows of \(app.localizedName ?? "?")")
        #endif
        let contents = WindowContents(app: app, windows: windows, preparedAt: clock.now)
        windowContents = contents
        return contents
    }

    // MARK: - Session

    private func begin(_ kind: SwitcherKind, direction: Direction, at time: Double) {
        let eventAge = ProcessInfo.processInfo.systemUptime - time
        let started = clock.now
        let targets: Targets
        let panel: SwitcherPanel
        switch kind {
        case .apps:
            // The contents stay valid for the next session unless the app list changes.
            targets = .apps((contents ?? prepareApps()).apps)
            panel = appPanel
        case .windows:
            let front = appOrder.frontmost
            let fresh = windowContents.flatMap {
                clock.now - $0.preparedAt < Self.windowContentsLifetime && $0.app == front ? $0 : nil
            }
            guard let contents = fresh ?? prepareWindows() else { return }
            targets = .windows(contents.app, contents.windows)
            panel = windowPanel
        }
        let selection = SwitchSession(
            itemCount: targets.count, direction: direction, began: time, settings: sessionSettings)
        panel.select(selection.selection)
        panel.show()
        cursor.freeze()
        cursor.hide()
        inputTap.isEnabled = true
        var session = Session(targets: targets, panel: panel, selection: selection)
        if UserDefaults.standard.bool(forKey: Self.liveSwitchingKey) {
            session.passable = Self.passableItems(targets)
            if case .apps = targets { appOrder.freeze() }
            bringForward(selection.selection, in: &session)
        }
        self.session = session
        #if DEBUG
        DiagnosticLog.write(
            "timing: event age \(Self.milliseconds(eventAge)) ms, "
                + "showing the \(kind) panel \(Self.milliseconds(clock.now - started)) ms")
        #endif
    }

    /// Live Switching: brings the selected Item forward, if it may be while passing over it.
    private func bringForward(_ item: Int, in session: inout Session) {
        guard let passable = session.passable, item != session.inFront, passable.contains(item) else { return }
        switch session.targets {
        case .apps(let apps):
            AppActivator.bringForward(apps[item])
        case .windows(let app, let windows):
            WindowActivator.raise(windows[item], of: app)
            session.raised.insert(item)
        }
        session.inFront = item
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
        switch session.selection.outcome(endedAt: time) {
        case .activate(let item):
            switch session.targets {
            case .apps(let apps):
                AppActivator.activate(apps[item])
                if session.passable != nil { appOrder.unfreeze(final: apps[item].processIdentifier) }
            case .windows(let app, let windows):
                restoreStacking(after: session, except: item)
                WindowActivator.focus(windows[item], of: app)
            }
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
        guard session.passable != nil else { return }
        switch session.targets {
        case .apps(let apps):
            if session.inFront != 0, let active = apps.first { AppActivator.bringForward(active) }
            appOrder.unfreeze(final: nil)
        case .windows:
            restoreStacking(after: session, except: nil)
        }
    }

    /// Puts the windows Live Switching raised, and the Current Item, back in their original stacking
    /// order, so only the window switched to counts as used.
    private func restoreStacking(after session: Session, except final: Int?) {
        guard case .windows(let app, let windows) = session.targets, !session.raised.isEmpty else { return }
        let restacked = session.raised.union([0]).subtracting(final.map { [$0] } ?? [])
        for item in restacked.sorted(by: >) where !windows[item].isMinimized {
            WindowActivator.raise(windows[item], of: app)
        }
    }

    @discardableResult
    private func finish() -> Session? {
        guard let session else { return nil }
        self.session = nil
        session.panel.hide()
        cursor.release()
        inputTap.isEnabled = false
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
