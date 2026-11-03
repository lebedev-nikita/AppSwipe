import ApplicationServices
import Darwin

/// The window number behind an accessibility window, which ScreenCaptureKit needs to capture it.
///
/// Public API can only match the two by frame and title, which is ambiguous for windows of one app
/// stacked at the same place, such as two maximized browser windows. The private
/// `_AXUIElementGetWindow` answers directly; see docs/adr/0003-touch-input-and-private-apis.md.
enum AXWindowID {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindow: GetWindow? = {
        guard let services = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(services, "_AXUIElementGetWindow")
        else { return nil }
        return unsafeBitCast(symbol, to: GetWindow.self)
    }()

    static var isAvailable: Bool { getWindow != nil }

    static func of(_ window: AXUIElement) -> CGWindowID? {
        var id = CGWindowID(0)
        guard let getWindow, getWindow(window, &id) == .success, id != 0 else { return nil }
        return id
    }
}
