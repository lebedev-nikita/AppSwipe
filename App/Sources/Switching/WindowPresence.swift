import AppKit

/// Which apps have windows, minimized or on any Space, for leaving out apps without them.
///
/// The window server lists windows on every Space, but also windows an app closed and keeps hidden,
/// and to it both look alike: not on screen. Accessibility tells them apart only on the Spaces shown
/// right now. So an app whose windows are all off screen and unknown to Accessibility is checked on
/// every Space in the background, which is slow, and the answer is kept until its window list changes
/// or it gets old. Until the first answer, such an app counts as having windows.
@MainActor
final class WindowPresence {
    /// Called when a background check changes whether an app has windows.
    var onChange: () -> Void = {}

    private struct Answer {
        /// The off-screen windows the check saw.
        let windows: Set<CGWindowID>
        let hasWindows: Bool
        let checkedAt: ContinuousClock.Instant
    }

    /// Check again in the background when an answer is older than this, in case a window on another
    /// Space was closed since.
    private static let answerLifetime = Duration.seconds(10)

    private let windowList: WindowList
    private let clock = ContinuousClock()
    private var answers: [pid_t: Answer] = [:]
    private var checking: Set<pid_t> = []

    init(windowList: WindowList) {
        self.windowList = windowList
    }

    /// The apps among `apps` without windows.
    func appsWithoutWindows(among apps: [NSRunningApplication]) -> Set<pid_t> {
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var onScreen: Set<pid_t> = []
        var offScreen: [pid_t: Set<CGWindowID>] = [:]
        for window in windows where window[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 50, (bounds["Height"] ?? 0) > 50
            else { continue }
            if window[kCGWindowIsOnscreen as String] as? Bool == true {
                onScreen.insert(pid)
            } else {
                offScreen[pid, default: []].insert(id)
            }
        }
        answers = answers.filter { offScreen[$0.key] != nil }
        return Set(apps.filter { app in
            let pid = app.processIdentifier
            guard !onScreen.contains(pid) else { return false }
            guard let candidates = offScreen[pid] else { return true }
            // Minimized windows, and windows of hidden apps on the Spaces shown.
            guard windowList.windows(of: app).isEmpty else { return false }
            return !hasWindows(pid: pid, offScreen: candidates)
        }.map(\.processIdentifier))
    }

    private func hasWindows(pid: pid_t, offScreen: Set<CGWindowID>) -> Bool {
        let answer = answers[pid].flatMap { $0.windows == offScreen ? $0 : nil }
        if answer.map({ clock.now - $0.checkedAt >= Self.answerLifetime }) ?? true {
            check(pid: pid, offScreen: offScreen)
        }
        return answer?.hasWindows ?? true
    }

    private func check(pid: pid_t, offScreen: Set<CGWindowID>) {
        guard checking.insert(pid).inserted else { return }
        Task { [weak self] in
            let hasWindows = await Task.detached(priority: .utility) {
                AXRemoteWindows.hasWindow(pid: pid) ?? true
            }.value
            guard let self else { return }
            checking.remove(pid)
            let shown = answers[pid].flatMap { $0.windows == offScreen ? $0.hasWindows : nil } ?? true
            answers[pid] = Answer(windows: offScreen, hasWindows: hasWindows, checkedAt: clock.now)
            if hasWindows != shown { onChange() }
        }
    }
}
