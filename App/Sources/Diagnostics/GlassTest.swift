#if DEBUG
import AppKit

/// A high-contrast backdrop for comparing how much of the background shows through the Switcher's
/// glass and through the native Cmd-Tab switcher's.
@MainActor
final class GlassTestBackdrop {
    private let window: NSWindow

    init(size: NSSize) {
        let screen = NSScreen.screens[0].frame
        window = NSWindow(
            contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false)
        // Above normal windows, below both switchers.
        window.level = .floating
        window.ignoresMouseEvents = true
        window.contentView = PatternView()
    }

    /// The window's frame in the top-left-origin coordinates `screencapture -R` takes.
    var captureRect: String {
        let frame = window.frame
        let top = NSScreen.screens[0].frame.height - frame.maxY
        return "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))"
    }

    func show() { window.orderFrontRegardless() }
    func hide() { window.orderOut(nil) }

    /// Presses Cmd-Tab and keeps Cmd down, so the native switcher stays open.
    static func openNativeSwitcher() {
        post(55, down: true, flags: .maskCommand)
        post(48, down: true, flags: .maskCommand)
        post(48, down: false, flags: .maskCommand)
    }

    /// Esc while Cmd is down closes the native switcher without switching, then Cmd comes up.
    static func closeNativeSwitcher() {
        post(53, down: true, flags: .maskCommand)
        post(53, down: false, flags: .maskCommand)
        post(55, down: false, flags: [])
    }

    private static func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: key, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}

private final class PatternView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black,
        ]
        let line = String(repeating: "The quick brown fox jumps over the lazy dog 0123456789 ", count: 4)
        var y = bounds.maxY - 22
        while y > 0 {
            (line as NSString).draw(at: NSPoint(x: 6, y: y), withAttributes: attributes)
            y -= 22
        }
        for (index, color) in [NSColor.systemRed, .systemBlue, .systemGreen, .black].enumerated() {
            color.setFill()
            NSRect(x: 120 + CGFloat(index) * 240, y: 0, width: 36, height: bounds.height).fill()
        }
    }
}
#endif
