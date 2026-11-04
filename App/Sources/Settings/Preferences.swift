import AppKit
import Observation
import ServiceManagement
import SwitchCore

/// The user's settings, kept in UserDefaults. Switch Sessions read them as they start.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let showMenuBarIcon = "ShowMenuBarIcon"
        static let appSwitcherEnabled = "AppSwitcherEnabled"
        static let windowSwitcherEnabled = "WindowSwitcherEnabled"
        static let appDisplays = "AppSwitcherDisplays"
        static let windowDisplays = "WindowSwitcherDisplays"
        static let swapFingerCounts = "SwapFingerCounts"
        static let swipeDownForWindows = "SwipeDownForWindows"
        static let stepLength = "StepLength"
        static let excludedApps = "ExcludedApps"
        static let hideFinderWithoutWindows = "HideFinderWithoutWindows"
        static let liveSwitching = "LiveSwitching"
        static let isPaused = "Paused"
        static let recordTouches = "RecordTouches"
        static let hasLaunched = "HasLaunched"
    }

    static let stepLengths: ClosedRange<Double> = 5...20

    private let defaults = UserDefaults.standard

    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    var appSwitcherEnabled: Bool { didSet { defaults.set(appSwitcherEnabled, forKey: Key.appSwitcherEnabled) } }
    var windowSwitcherEnabled: Bool { didSet { defaults.set(windowSwitcherEnabled, forKey: Key.windowSwitcherEnabled) } }
    /// The displays whose apps the App Switcher lists.
    var appDisplays: DisplayScope { didSet { defaults.set(appDisplays.rawValue, forKey: Key.appDisplays) } }
    /// The displays whose windows the Window Switcher lists.
    var windowDisplays: DisplayScope { didSet { defaults.set(windowDisplays.rawValue, forKey: Key.windowDisplays) } }
    /// Four fingers for the App Switcher and three for the Window Switcher.
    var swapFingerCounts: Bool { didSet { defaults.set(swapFingerCounts, forKey: Key.swapFingerCounts) } }
    /// A swipe down with the App Switcher's fingers opens it on the Active App's windows.
    var swipeDownForWindows: Bool {
        didSet { defaults.set(swipeDownForWindows, forKey: Key.swipeDownForWindows) }
    }
    /// Finger travel per Step, in millimetres.
    var stepLength: Double { didSet { defaults.set(stepLength, forKey: Key.stepLength) } }
    /// Bundle identifiers of apps during which swipes do nothing.
    var excludedApps: [String] { didSet { defaults.set(excludedApps, forKey: Key.excludedApps) } }
    var hideFinderWithoutWindows: Bool {
        didSet { defaults.set(hideFinderWithoutWindows, forKey: Key.hideFinderWithoutWindows) }
    }
    var liveSwitching: Bool { didSet { defaults.set(liveSwitching, forKey: Key.liveSwitching) } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Key.isPaused) } }
    var recordTouches: Bool { didSet { defaults.set(recordTouches, forKey: Key.recordTouches) } }

    /// Whether AppSwipe opens at login, as registered with the system.
    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    launchAtLoginError = nil
                } catch {
                    DiagnosticLog.write("cannot change launch at login: \(error.localizedDescription)")
                    launchAtLoginError = error.localizedDescription
                }
            }
        }
    }

    /// Whether launch at login waits for the user to allow it under Login Items in System Settings.
    var launchAtLoginNeedsApproval: Bool {
        access(keyPath: \.launchAtLogin)
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// Why the last change to launch at login failed.
    private(set) var launchAtLoginError: String?

    /// True only the first time AppSwipe launches.
    let isFirstLaunch: Bool

    private init() {
        defaults.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.appSwitcherEnabled: true,
            Key.windowSwitcherEnabled: true,
            Key.stepLength: 8.0,
            Key.hideFinderWithoutWindows: true,
        ])
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        appSwitcherEnabled = defaults.bool(forKey: Key.appSwitcherEnabled)
        windowSwitcherEnabled = defaults.bool(forKey: Key.windowSwitcherEnabled)
        appDisplays = defaults.string(forKey: Key.appDisplays).flatMap(DisplayScope.init) ?? .all
        windowDisplays = defaults.string(forKey: Key.windowDisplays).flatMap(DisplayScope.init) ?? .all
        swapFingerCounts = defaults.bool(forKey: Key.swapFingerCounts)
        swipeDownForWindows = defaults.bool(forKey: Key.swipeDownForWindows)
        stepLength = defaults.double(forKey: Key.stepLength)
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? []
        hideFinderWithoutWindows = defaults.bool(forKey: Key.hideFinderWithoutWindows)
        liveSwitching = defaults.bool(forKey: Key.liveSwitching)
        isPaused = defaults.bool(forKey: Key.isPaused)
        recordTouches = defaults.bool(forKey: Key.recordTouches)
        isFirstLaunch = !defaults.bool(forKey: Key.hasLaunched)
        defaults.set(true, forKey: Key.hasLaunched)
    }

    /// Fingers that open each Switcher, given the swap setting.
    func fingers(for kind: SwitcherKind) -> Int {
        switch kind {
        case .apps: swapFingerCounts ? 4 : 3
        case .windows: swapFingerCounts ? 3 : 4
        }
    }

    /// The Switcher a number of fingers opens, if it is enabled.
    func switcher(forFingers fingers: Int) -> SwitcherKind? {
        if fingers == self.fingers(for: .apps), appSwitcherEnabled { return .apps }
        if fingers == self.fingers(for: .windows), windowSwitcherEnabled { return .windows }
        return nil
    }

    func isExcluded(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return excludedApps.contains(id)
    }
}
