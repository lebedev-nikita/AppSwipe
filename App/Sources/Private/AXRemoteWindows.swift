import ApplicationServices
import Darwin

/// Whether an app has a window on any Space, read through Accessibility.
///
/// Public Accessibility lists only windows on the Spaces shown right now, and the window server also
/// lists windows an app closed but keeps hidden, so neither tells a window on another Space from a
/// closed one. The private `_AXUIElementCreateWithRemoteToken` makes an app's accessibility elements by
/// number, which reaches windows on every Space and only real ones, as AltTab does; see
/// docs/adr/0003-touch-input-and-private-apis.md. Trying the numbers takes up to about 50 ms per app.
enum AXRemoteWindows {
    private typealias CreateWithToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let createWithToken: CreateWithToken? = {
        guard let services = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(services, "_AXUIElementCreateWithRemoteToken")
        else { return nil }
        return unsafeBitCast(symbol, to: CreateWithToken.self)
    }()

    private static let ordinary: Set<String> = [kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole]

    /// Whether the app has an ordinary window or dialog; nil if that can't be told.
    static func hasWindow(pid: pid_t) -> Bool? {
        guard let createWithToken else { return nil }
        for id in UInt64(0)..<1000 {
            var token = Data(count: 20)
            token.withUnsafeMutableBytes { bytes in
                bytes.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
                bytes.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
                // "coco", marking a Cocoa element.
                bytes.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
                bytes.storeBytes(of: id, toByteOffset: 12, as: UInt64.self)
            }
            guard let element = createWithToken(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, 0.1)
            var subrole: AnyObject?
            switch AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) {
            case .success:
                if let subrole = subrole as? String, ordinary.contains(subrole) { return true }
            case .cannotComplete:
                // The app doesn't answer.
                return nil
            default:
                break
            }
        }
        return false
    }
}
