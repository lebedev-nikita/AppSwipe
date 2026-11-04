#if DEBUG
import AppKit

/// A high-contrast backdrop for comparing how much of the background shows through the Switcher's
/// glass and through the native Cmd-Tab switcher's.
@MainActor
final class GlassTestBackdrop {
    private let window: NSWindow

    /// With `flat`, a plain colour instead of the high-contrast pattern; with `wallpaper`, soft colour
    /// blobs like a desktop picture.
    init(size: NSSize, flat: NSColor? = nil, wallpaper: Bool = false) {
        let screen = NSScreen.screens[0].frame
        window = NSWindow(
            contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false)
        // Above normal windows, below both switchers.
        window.level = .floating
        window.ignoresMouseEvents = true
        if wallpaper {
            window.contentView = WallpaperView(seed: 0)
        } else if let flat {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = flat.cgColor
            window.contentView = view
        } else {
            window.contentView = PatternView()
        }
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
/// Soft overlapping colour blobs, for screenshots that shouldn't show anyone's desktop.
final class WallpaperView: NSView {
    private static let palettes: [[NSColor]] = [
        [.systemIndigo, .systemPurple, .systemOrange, .systemPink],
        [.systemTeal, .systemBlue, .systemMint, .systemIndigo],
        [.systemOrange, .systemYellow, .systemRed, .systemPink],
        [.systemGreen, .systemTeal, .systemYellow, .systemBlue],
    ]

    private let seed: Int

    init(seed: Int) {
        self.seed = seed
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let colors = Self.palettes[seed % Self.palettes.count]
        NSGradient(starting: colors[0].blended(withFraction: 0.5, of: .black)!, ending: colors[1])?
            .draw(in: bounds, angle: 35 + CGFloat(seed) * 40)
        let centers: [(CGFloat, CGFloat, CGFloat)] = [(0.2, 0.3, 0.55), (0.75, 0.7, 0.5), (0.55, 0.15, 0.4), (0.9, 0.2, 0.35)]
        for (index, (x, y, r)) in centers.enumerated() {
            let color = colors[(index + 2) % colors.count].withAlphaComponent(0.75)
            let radius = r * max(bounds.width, bounds.height)
            let center = NSPoint(x: bounds.width * x, y: bounds.height * y)
            NSGradient(starting: color, ending: color.withAlphaComponent(0))?
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
        }
    }
}
#endif
