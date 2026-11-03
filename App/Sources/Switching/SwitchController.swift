import AppKit
import SwitchCore

/// Runs Switch Sessions: feeds touch frames to the recognizer, drives the Switcher panel, and
/// commits the Selection.
///
/// The Switcher appears the moment a session opens. To make that instant, the panel is laid out ahead
/// of time, whenever the app list changes, so neither landing fingers nor an opening session wait for it.
@MainActor
final class SwitchController {
    private struct Contents {
        let apps: [NSRunningApplication]
        let preparedAt: ContinuousClock.Instant
    }

    private struct Session {
        let apps: [NSRunningApplication]
        var selection: SwitchSession
    }

    /// Rebuild contents older than this when fingers land, in case something changed unnoticed, such
    /// as an app's icon.
    private static let contentsLifetime = Duration.seconds(60)

    private let inputTap: SessionInputTap
    private let panel = SwitcherPanel()
    private let cursor = CursorFreeze()
    private let appOrder = AppOrder()
    private let sessionSettings = SwitchSession.Settings()
    private let clock = ContinuousClock()
    private var recognizer: SwipeRecognizer
    private var contents: Contents?
    private var contentsCount = 0
    private var session: Session?
    /// Dock badges by app bundle path, from the previous refresh, shown until fresh ones arrive.
    private var badges: [String: String] = [:]

    init(inputTap: SessionInputTap) {
        self.inputTap = inputTap
        var settings = SwipeRecognizer.Settings()
        // The Window Switcher comes in a later milestone.
        settings.fingerCounts = [3]
        recognizer = SwipeRecognizer(settings: settings)
        inputTap.onEscape = { [weak self] in self?.cancel() }
        appOrder.onChange = { [weak self] in self?.appsChanged() }
    }

    /// Re-lays out the panel on the next turn of the run loop, unless a session is showing it.
    private func appsChanged() {
        contents = nil
        Task { [weak self] in
            guard let self, session == nil, contents == nil else { return }
            prepare()
        }
    }

    /// Creates and lays out the panel once, so the first swipe doesn't pay for it.
    func warmUp() {
        prepare()
    }

    func handle(_ frame: TouchFrame) {
        switch recognizer.handle(frame) {
        case .armed(let fingers):
            guard session == nil, SwitcherKind(fingers: fingers) == .apps else { return }
            if let contents, clock.now - contents.preparedAt < Self.contentsLifetime {
                refreshBadges(apps: contents.apps, contents: contentsCount)
            } else {
                prepare()
            }
        case .began(let fingers, let direction, let time):
            guard SwitcherKind(fingers: fingers) == .apps else { return }
            begin(direction: direction, at: time)
        case .moved(let travel):
            guard var session, session.selection.move(travel: travel) else { return }
            self.session = session
            panel.select(session.selection.selection)
        case .ended(let time):
            end(at: time)
        case nil:
            break
        }
    }

    #if DEBUG
    /// Shows the App Switcher for a few seconds without a gesture, for checking its look.
    func preview(selection: Int) {
        begin(direction: .right, at: ProcessInfo.processInfo.systemUptime)
        inputTap.isEnabled = false
        panel.select(selection)
        let screenHeight = NSScreen.screens[0].frame.height
        let frame = panel.frame
        // In the top-left-origin coordinates `screencapture -R` takes.
        DiagnosticLog.write(
            "preview: panel at \(Int(frame.minX)),\(Int(screenHeight - frame.maxY)),"
                + "\(Int(frame.width)),\(Int(frame.height))")
        Task {
            try? await Task.sleep(for: .seconds(6))
            finish()
        }
    }
    #endif

    #if DEBUG
    /// Shows the Switcher over a test backdrop, then, with `native`, the native Cmd-Tab switcher, on a
    /// fixed timeline that a script captures.
    func glassTest(native: Bool) {
        let backdrop = GlassTestBackdrop(size: NSSize(width: 1100, height: 440))
        Task {
            backdrop.show()
            DiagnosticLog.write("glass test: start, rect \(backdrop.captureRect)")
            try? await Task.sleep(for: .seconds(1))
            prepare()
            panel.select(1)
            panel.show()
            try? await Task.sleep(for: .seconds(0.3))
            DiagnosticLog.write("glass test: showing ours")
            try? await Task.sleep(for: .seconds(1.2))
            panel.hide()
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

    /// Lays out the panel with the current apps, without showing it.
    @discardableResult
    private func prepare() -> Contents {
        let started = clock.now
        let apps = appOrder.apps()
        let paths = apps.map { $0.bundleURL.map(DockBadges.path(of:)) }
        let listed = clock.now
        panel.prepare(
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
        let contents = Contents(apps: apps, preparedAt: clock.now)
        self.contents = contents
        return contents
    }

    private func begin(direction: Direction, at time: Double) {
        let eventAge = ProcessInfo.processInfo.systemUptime - time
        let started = clock.now
        // The contents stay valid for the next session unless the app list changes.
        let contents = self.contents ?? prepare()
        let selection = SwitchSession(
            itemCount: contents.apps.count, direction: direction, began: time, settings: sessionSettings)
        panel.select(selection.selection)
        panel.show()
        cursor.freeze()
        cursor.hide()
        inputTap.isEnabled = true
        session = Session(apps: contents.apps, selection: selection)
        #if DEBUG
        DiagnosticLog.write(
            "timing: event age \(Self.milliseconds(eventAge)) ms, "
                + "showing the panel \(Self.milliseconds(clock.now - started)) ms")
        #endif
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
            panel.setBadges(byItem)
        }
    }

    private func end(at time: Double) {
        guard let session = finish() else { return }
        switch session.selection.outcome(endedAt: time) {
        case .activate(let item):
            AppActivator.activate(session.apps[item])
        case .cancel:
            break
        }
    }

    private func cancel() {
        finish()
    }

    @discardableResult
    private func finish() -> Session? {
        guard let session else { return nil }
        self.session = nil
        panel.hide()
        cursor.release()
        inputTap.isEnabled = false
        // The app list may have changed while the panel was showing.
        if contents == nil { appsChanged() }
        return session
    }
}
