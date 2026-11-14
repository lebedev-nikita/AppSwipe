import AppKit

/// Which windows an app has, on any Space.
enum AppWindows: Sendable {
    case none
    /// Only minimized windows.
    case minimized
    /// At least one window that isn't minimized.
    case unminimized
}

/// Which apps have windows, minimized or on any Space, for leaving out apps without them or with all
/// of them minimized.
///
/// The window server lists windows on every Space, but also windows an app closed and keeps hidden,
/// and to it both look alike: not on screen, just like minimized windows. Accessibility tells them
/// apart only on the Spaces shown right now, and lists minimized windows from every Space. So an app
/// whose off-screen windows aren't all known to Accessibility is checked on every Space in the
/// background, which is slow, and the answer is kept until its window list changes or it gets old.
/// Until the first answer, such an app counts as having a window that isn't minimized.
@MainActor
final class WindowPresence {
    /// Called when a background check changes which windows an app has.
    var onChange: () -> Void = {}

    private struct Answer {
        /// The off-screen windows the check saw.
        let offScreen: Set<CGWindowID>
        let windows: AppWindows
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

    /// The apps among `apps` to leave out: those `withoutWindows` picks that have no windows, and, when
    /// `minimized` is set, those whose windows are all minimized.
    func appsToHide(
        among apps: [NSRunningApplication], withoutWindows: (NSRunningApplication) -> Bool, minimized: Bool
    ) -> Set<pid_t> {
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
            let hidesWithoutWindows = withoutWindows(app)
            guard hidesWithoutWindows || minimized else { return false }
            let pid = app.processIdentifier
            guard !onScreen.contains(pid) else { return false }
            guard let candidates = offScreen[pid] else { return hidesWithoutWindows }
            // Minimized windows, and windows of hidden apps on the Spaces shown.
            let known = windowList.windows(of: app)
            guard known.allSatisfy(\.isMinimized) else { return false }
            if known.isEmpty {
                // Minimized windows would be known, so the app has none.
                guard hidesWithoutWindows else { return false }
            } else {
                guard minimized else { return false }
                if candidates.isSubset(of: known.compactMap(\.id)) { return true }
            }
            switch self.windows(pid: pid, offScreen: candidates) {
            case .none: return hidesWithoutWindows
            case .minimized: return minimized
            case .unminimized: return false
            }
        }.map(\.processIdentifier))
    }

    private func windows(pid: pid_t, offScreen: Set<CGWindowID>) -> AppWindows {
        let answer = answers[pid].flatMap { $0.offScreen == offScreen ? $0 : nil }
        if answer.map({ clock.now - $0.checkedAt >= Self.answerLifetime }) ?? true {
            check(pid: pid, offScreen: offScreen)
        }
        return answer?.windows ?? .unminimized
    }

    private func check(pid: pid_t, offScreen: Set<CGWindowID>) {
        guard checking.insert(pid).inserted else { return }
        Task { [weak self] in
            let windows = await Task.detached(priority: .utility) {
                AXRemoteWindows.windows(pid: pid) ?? .unminimized
            }.value
            guard let self else { return }
            checking.remove(pid)
            let shown = answers[pid].flatMap { $0.offScreen == offScreen ? $0.windows : nil } ?? .unminimized
            answers[pid] = Answer(offScreen: offScreen, windows: windows, checkedAt: clock.now)
            if windows != shown { onChange() }
        }
    }
}
