import AppKit
import ScreenCaptureKit

/// Window Previews, captured with ScreenCaptureKit and kept, so a Switcher can show the last capture
/// at once while a fresh one is taken.
///
/// Minimized windows and windows on other Spaces can't be captured, so they keep the image from the
/// last time they were visible.
@MainActor
final class WindowPreviews {
    /// Captures at twice the preview height, for Retina displays.
    nonisolated private static let pixelHeight = 2 * 140.0
    /// At most this many captures run at once: more can leak WindowServer memory.
    private static let parallelCaptures = 2

    private var images: [CGWindowID: CGImage] = [:]
    private var capture: Task<Void, Never>?

    func cached(_ window: WindowEntry) -> CGImage? {
        window.id.flatMap { images[$0] }
    }

    /// Captures the visible ones of `windows`, which belong to the app with `pid`, and calls `update`
    /// with each window's index as its preview arrives. Supersedes a refresh still in progress.
    func refresh(_ windows: [WindowEntry], pid: pid_t, update: @escaping (Int, CGImage) -> Void) {
        guard CGPreflightScreenCaptureAccess(), windows.contains(where: { !$0.isMinimized }) else { return }
        capture?.cancel()
        capture = Task {
            let clock = ContinuousClock()
            let started = clock.now
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
                  !Task.isCancelled
            else { return }
            #if DEBUG
            DiagnosticLog.write("timing: shareable content \(clock.now - started)")
            #endif
            let candidates = content.windows.filter { $0.owningApplication?.processID == pid }
            var pending = windows.indices.compactMap { index -> (Int, CapturableWindow)? in
                guard !windows[index].isMinimized,
                      let window = Self.match(windows[index], in: candidates)
                else { return nil }
                return (index, CapturableWindow(window: window))
            }[...]
            await withTaskGroup(of: (Int, CGWindowID, CGImage?).self) { group in
                func startNext() {
                    guard let (index, window) = pending.popFirst() else { return }
                    group.addTask { (index, window.window.windowID, await Self.image(of: window)) }
                }
                for _ in 0..<Self.parallelCaptures { startNext() }
                for await (index, id, image) in group {
                    if let image, !Task.isCancelled {
                        images[id] = image
                        update(index, image)
                    }
                    #if DEBUG
                    DiagnosticLog.write("timing: preview \(index) \(image == nil ? "failed" : "captured") after \(clock.now - started)")
                    #endif
                    startNext()
                }
            }
        }
    }

    /// Drops images of windows that no longer exist.
    func forget(allBut windows: Set<CGWindowID>) {
        images = images.filter { windows.contains($0.key) }
    }

    private static func match(_ entry: WindowEntry, in windows: [SCWindow]) -> SCWindow? {
        if let id = entry.id { return windows.first { $0.windowID == id } }
        // Without the window number, fall back to the frame, then the title among windows sharing it.
        let sameFrame = windows.filter { abs($0.frame.minX - entry.frame.minX) < 2 && abs($0.frame.minY - entry.frame.minY) < 2
            && abs($0.frame.width - entry.frame.width) < 2 && abs($0.frame.height - entry.frame.height) < 2 }
        return sameFrame.count > 1 ? sameFrame.first { $0.title == entry.title } : sameFrame.first
    }

    nonisolated private static func image(of capturable: CapturableWindow) async -> CGImage? {
        let window = capturable.window
        let configuration = SCStreamConfiguration()
        let aspect = window.frame.width / max(window.frame.height, 1)
        configuration.height = Int(pixelHeight)
        configuration.width = Int((pixelHeight * aspect).rounded())
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

/// ScreenCaptureKit's window descriptions are immutable snapshots, safe to hand to a capture task.
private struct CapturableWindow: @unchecked Sendable {
    let window: SCWindow
}
