import AppKit
import SwitchCore

/// Runs Switch Sessions: feeds touch frames to the recognizer, drives the Switcher panel, and
/// commits the Selection.
@MainActor
final class SwitchController {
    private struct Session {
        let apps: [NSRunningApplication]
        var selection: SwitchSession
        var reveal: Task<Void, Never>
    }

    private let inputTap: SessionInputTap
    private let panel = SwitcherPanel()
    private let cursor = CursorFreeze()
    private let appOrder = AppOrder()
    private let sessionSettings = SwitchSession.Settings()
    private var recognizer: SwipeRecognizer
    private var session: Session?
    private var sessionCount = 0
    /// Dock badges by app bundle path, from the previous session, shown until fresh ones arrive.
    private var badges: [String: String] = [:]

    init(inputTap: SessionInputTap) {
        self.inputTap = inputTap
        var settings = SwipeRecognizer.Settings()
        // The Window Switcher comes in a later milestone.
        settings.fingerCounts = [3]
        recognizer = SwipeRecognizer(settings: settings)
        inputTap.onEscape = { [weak self] in self?.cancel() }
    }

    func handle(_ frame: TouchFrame) {
        switch recognizer.handle(frame) {
        case .began(let fingers, let direction, let time):
            guard SwitcherKind(fingers: fingers) == .apps else { return }
            begin(direction: direction, at: time)
        case .moved(let travel):
            guard var session, session.selection.move(travel: travel) else { return }
            self.session = session
            panel.select(session.selection.selection)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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
        session?.reveal.cancel()
        panel.select(selection)
        panel.show()
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

    private func begin(direction: Direction, at time: Double) {
        let apps = appOrder.apps()
        let paths = apps.map { $0.bundleURL.map(DockBadges.path(of:)) }
        let selection = SwitchSession(itemCount: apps.count, direction: direction, began: time, settings: sessionSettings)
        panel.prepare(
            zip(apps, paths).map { app, path in
                SwitcherPanel.Item(
                    image: app.icon ?? NSImage(), title: app.localizedName ?? "", badge: path.flatMap { badges[$0] })
            },
            selection: selection.selection)
        sessionCount += 1
        refreshBadges(paths: paths, session: sessionCount)
        let delay = sessionSettings.revealDelay
        let reveal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.panel.show()
            self?.cursor.hide()
        }
        session = Session(apps: apps, selection: selection, reveal: reveal)
        cursor.freeze()
        inputTap.isEnabled = true
    }

    private func refreshBadges(paths: [String?], session id: Int) {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }
        let pid = dock.processIdentifier
        Task {
            let badges = await Task.detached { DockBadges.current(dockPID: pid) }.value
            self.badges = badges
            guard id == sessionCount, session != nil else { return }
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
        session.reveal.cancel()
        panel.hide()
        cursor.release()
        inputTap.isEnabled = false
        return session
    }
}
