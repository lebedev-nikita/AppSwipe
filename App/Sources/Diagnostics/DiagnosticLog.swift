import Foundation

/// A plain-text log in ~/Library/Logs/AppSwipe, for diagnosing the app on a user's machine.
@MainActor
enum DiagnosticLog {
    static let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/AppSwipe", directoryHint: .isDirectory)

    private static let file = directory.appending(path: "appswipe.log")
    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    static func write(_ message: String) {
        let line = "\(Date.now.formatted(timestamp)) \(message)\n"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            print("AppSwipe: cannot write the diagnostic log: \(error)")
        }
    }
}
