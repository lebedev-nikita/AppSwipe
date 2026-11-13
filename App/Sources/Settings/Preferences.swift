import AppKit
import Observation
import ServiceManagement

/// The user's settings, kept in UserDefaults. Switch Sessions read them as they start.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let showMenuBarIcon = "ShowMenuBarIcon"
        static let appDisplays = "AppSwitcherDisplays"
        static let windowDisplays = "WindowSwitcherDisplays"
        static let fourFingers = "FourFingers"
        /// Four fingers for the App Switcher, from when the Window Switcher had its own swipe.
        static let swapFingerCounts = "SwapFingerCounts"
        static let stepLength = "StepLength"
        static let excludedApps = "ExcludedApps"
        static let hideAppsWithoutWindows = "HideAppsWithoutWindows"
        static let hideFinderWithoutWindows = "HideFinderWithoutWindows"
        static let liveSwitching = "LiveSwitching"
        static let enlargeSelection = "EnlargeSelection"
        static let ignorePalms = "IgnorePalms"
        static let isPaused = "Paused"
        static let recordTouches = "RecordTouches"
        static let hasLaunched = "HasLaunched"
    }

    static let stepLengths: ClosedRange<Double> = 5...20

    private let defaults = UserDefaults.standard

    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    /// The displays whose apps the App Switcher lists.
    var appDisplays: DisplayScope { didSet { defaults.set(appDisplays.rawValue, forKey: Key.appDisplays) } }
    /// The displays whose windows the Window Switcher lists.
    var windowDisplays: DisplayScope { didSet { defaults.set(windowDisplays.rawValue, forKey: Key.windowDisplays) } }
    /// Swipes take four fingers instead of three.
    var fourFingers: Bool { didSet { defaults.set(fourFingers, forKey: Key.fourFingers) } }
    /// Finger travel per Step, in millimetres.
    var stepLength: Double { didSet { defaults.set(stepLength, forKey: Key.stepLength) } }
    /// Bundle identifiers of apps during which swipes do nothing.
    var excludedApps: [String] { didSet { defaults.set(excludedApps, forKey: Key.excludedApps) } }
    /// The App Switcher leaves out apps without windows, other than the Active App.
    var hideAppsWithoutWindows: Bool {
        didSet { defaults.set(hideAppsWithoutWindows, forKey: Key.hideAppsWithoutWindows) }
    }
    /// The App Switcher leaves out Finder without windows, unless it is the Active App. Only matters
    /// while apps without windows are shown.
    var hideFinderWithoutWindows: Bool {
        didSet { defaults.set(hideFinderWithoutWindows, forKey: Key.hideFinderWithoutWindows) }
    }
    var liveSwitching: Bool { didSet { defaults.set(liveSwitching, forKey: Key.liveSwitching) } }
    /// Show the Selection by enlarging its Item instead of highlighting it.
    var enlargeSelection: Bool { didSet { defaults.set(enlargeSelection, forKey: Key.enlargeSelection) } }
    /// A palm on the trackpad doesn't count as a finger.
    var ignorePalms: Bool { didSet { defaults.set(ignorePalms, forKey: Key.ignorePalms) } }
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
            Key.stepLength: 8.0,
            Key.ignorePalms: true,
        ])
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        appDisplays = defaults.string(forKey: Key.appDisplays).flatMap(DisplayScope.init) ?? .all
        windowDisplays = defaults.string(forKey: Key.windowDisplays).flatMap(DisplayScope.init) ?? .all
        fourFingers = defaults.object(forKey: Key.fourFingers) as? Bool ?? defaults.bool(forKey: Key.swapFingerCounts)
        stepLength = defaults.double(forKey: Key.stepLength)
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? []
        // Before apps without windows could be hidden, Finder alone was, unless turned off. Turned off,
        // everything stays shown.
        hideAppsWithoutWindows = defaults.object(forKey: Key.hideAppsWithoutWindows) as? Bool
            ?? defaults.object(forKey: Key.hideFinderWithoutWindows) as? Bool ?? true
        hideFinderWithoutWindows = defaults.bool(forKey: Key.hideFinderWithoutWindows)
        liveSwitching = defaults.bool(forKey: Key.liveSwitching)
        enlargeSelection = defaults.bool(forKey: Key.enlargeSelection)
        ignorePalms = defaults.bool(forKey: Key.ignorePalms)
        isPaused = defaults.bool(forKey: Key.isPaused)
        recordTouches = defaults.bool(forKey: Key.recordTouches)
        isFirstLaunch = !defaults.bool(forKey: Key.hasLaunched)
        defaults.set(true, forKey: Key.hasLaunched)
    }

    /// Fingers that swipe sideways for the App Switcher and down for an app's windows.
    var fingers: Int { fourFingers ? 4 : 3 }

    func isExcluded(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return excludedApps.contains(id)
    }
}
