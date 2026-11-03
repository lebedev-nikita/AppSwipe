import Foundation
import SwitchCore

/// Records touch frames for diagnosis and for replaying in SwitchCore tests.
///
/// Every frame goes to touches.jsonl as one JSON line. Each completed gesture also gets a one-line
/// summary in the diagnostic log.
@MainActor
final class TouchRecorder {
    private let handle: FileHandle?
    private let encoder = JSONEncoder()
    private var gesture: GestureSummary?
    private var previous: TouchFrame?

    init() {
        let file = DiagnosticLog.directory.appending(path: "touches.jsonl")
        try? FileManager.default.createDirectory(at: DiagnosticLog.directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: file)
        _ = try? handle?.seekToEnd()
        encoder.outputFormatting = .sortedKeys
    }

    func record(_ frame: TouchFrame) {
        if let line = try? encoder.encode(frame) {
            try? handle?.write(contentsOf: line + Data("\n".utf8))
        }
        summarize(frame)
    }

    private func summarize(_ frame: TouchFrame) {
        let down = frame.fingersDown
        if gesture == nil, !down.isEmpty {
            gesture = GestureSummary(start: frame.time, surface: frame.surface)
        }
        guard var summary = gesture else { return }
        summary.frames += 1
        summary.maxFingers = max(summary.maxFingers, down.count)
        // Only movement between frames with the same fingers down counts as travel, so a finger
        // landing or lifting doesn't shift the centroid.
        if let previous, Set(previous.fingersDown.map(\.id)) == Set(down.map(\.id)), !down.isEmpty {
            let (x0, y0) = centroid(previous.fingersDown)
            let (x1, y1) = centroid(down)
            summary.dx += (x1 - x0) * frame.surface.width
            summary.dy += (y1 - y0) * frame.surface.height
        }
        previous = frame
        gesture = summary
        if down.isEmpty {
            DiagnosticLog.write(summary.line(end: frame.time))
            gesture = nil
            previous = nil
        }
    }

    private func centroid(_ touches: [Touch]) -> (Double, Double) {
        let count = Double(touches.count)
        return (touches.map(\.x).reduce(0, +) / count, touches.map(\.y).reduce(0, +) / count)
    }
}

private struct GestureSummary {
    let start: Double
    let surface: Size
    var frames = 0
    var maxFingers = 0
    var dx = 0.0
    var dy = 0.0

    func line(end: Double) -> String {
        let duration = Int(((end - start) * 1000).rounded())
        return "gesture: \(maxFingers) fingers, travel x \(mm(dx)) y \(mm(dy)) mm, \(duration) ms, "
            + "\(frames) frames, surface \(mm(surface.width))×\(mm(surface.height)) mm"
    }

    private func mm(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
