import CoreGraphics
import Darwin

/// Lets a background app hide the cursor.
///
/// The WindowServer ignores `CGDisplayHideCursor` from apps that aren't frontmost, and OpenSwipe never
/// is. The private connection property "SetsCursorInBackground" lifts that restriction. Private API, so
/// it lives here alone; see docs/adr/0003-touch-input-and-private-apis.md.
enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    /// Returns whether the property could be set. Fails, rather than crashing, if macOS drops the symbols.
    @discardableResult
    static func allowHiding() -> Bool {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let connectionSymbol = dlsym(handle, "_CGSDefaultConnection"),
              let setSymbol = dlsym(handle, "CGSSetConnectionProperty")
        else { return false }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let set = unsafeBitCast(setSymbol, to: SetConnectionProperty.self)
        return set(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }
}
