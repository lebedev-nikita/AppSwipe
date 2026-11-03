import Foundation

/// Whether the screen is locked, from the notifications macOS posts on locking and unlocking.
@MainActor
final class ScreenLock {
    private(set) var isLocked = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLocked = locked }
            })
        }
    }
}
