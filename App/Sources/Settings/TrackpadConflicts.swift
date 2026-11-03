import Foundation
import Observation

/// System trackpad gestures that take the swipes a Switcher needs, and turning them off and back on.
///
/// macOS keeps each trackpad gesture in two domains, one per kind of trackpad, plus a per-host global
/// key; System Settings writes all three, so this does too. `activateSettings -u` makes the Dock pick up
/// the change without a logout (checked on macOS 27.0.1).
@MainActor
@Observable
final class TrackpadConflicts {
    enum Conflict: Hashable {
        /// Horizontal swipes with this many fingers switch between full-screen apps and Spaces.
        case spacesSwipe(fingers: Int)
        /// Three-finger horizontal swipes go back and forward in apps.
        case pageSwipe
        /// Three-finger drag, which only Accessibility settings can turn off.
        case threeFingerDrag
    }

    private static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    private static let savedKey = "SavedTrackpadGestures"
    private static let activateSettings = URL(
        fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")

    private(set) var conflicts: [Conflict] = []
    /// Whether "Restore" has original values to put back.
    private(set) var canRestore = UserDefaults.standard.dictionary(forKey: savedKey) != nil

    /// Re-reads the trackpad settings for Switchers using `fingers`.
    func refresh(fingers: Set<Int>) {
        var found: [Conflict] = []
        for count in fingers.sorted() where Self.value(Self.horizontalKey(count)) == 2 {
            found.append(.spacesSwipe(fingers: count))
        }
        if fingers.contains(3) {
            if Self.value(Self.horizontalKey(3)) == 1 { found.append(.pageSwipe) }
            if Self.value("TrackpadThreeFingerDrag") == 1 { found.append(.threeFingerDrag) }
        }
        conflicts = found
    }

    /// Turns off the horizontal swipes the Switchers need, remembering the old values. Returns false
    /// if macOS didn't take the change, in which case Trackpad settings should be opened instead.
    @discardableResult
    func turnOff(fingers: Set<Int>) -> Bool {
        var saved = UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: Int] ?? [:]
        for count in fingers {
            let key = Self.horizontalKey(count)
            if saved[key] == nil { saved[key] = Self.value(key) ?? 0 }
            Self.write(key, 0)
        }
        UserDefaults.standard.set(saved, forKey: Self.savedKey)
        canRestore = true
        let applied = Self.apply()
        refresh(fingers: fingers)
        return applied && !conflicts.contains { if case .threeFingerDrag = $0 { false } else { true } }
    }

    /// Puts back the values `turnOff` replaced.
    func restore(fingers: Set<Int>) {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: Int] else { return }
        for (key, value) in saved { Self.write(key, value) }
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        canRestore = false
        Self.apply()
        refresh(fingers: fingers)
    }

    private static func horizontalKey(_ fingers: Int) -> String {
        fingers == 3 ? "TrackpadThreeFingerHorizSwipeGesture" : "TrackpadFourFingerHorizSwipeGesture"
    }

    /// The per-host global key System Settings writes alongside each trackpad key.
    private static func globalKey(_ key: String) -> String? {
        switch key {
        case "TrackpadThreeFingerHorizSwipeGesture": "com.apple.trackpad.threeFingerHorizSwipeGesture"
        case "TrackpadFourFingerHorizSwipeGesture": "com.apple.trackpad.fourFingerHorizSwipeGesture"
        default: nil
        }
    }

    private static func value(_ key: String) -> Int? {
        CFPreferencesCopyAppValue(key as CFString, domains[0] as CFString) as? Int
    }

    private static func write(_ key: String, _ value: Int) {
        for domain in domains {
            CFPreferencesSetValue(key as CFString, value as CFNumber, domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        guard let global = globalKey(key) else { return }
        CFPreferencesSetValue(global as CFString, value as CFNumber, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    @discardableResult
    private static func apply() -> Bool {
        guard let process = try? Process.run(activateSettings, arguments: ["-u"]) else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
