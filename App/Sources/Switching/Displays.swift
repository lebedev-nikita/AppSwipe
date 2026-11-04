import AppKit

/// The displays a Switcher lists Items from.
enum DisplayScope: String, CaseIterable {
    /// Every display.
    case all = "All"
    /// Only the display with the pointer, where the Switcher appears.
    case pointer = "Pointer"
}

@MainActor
enum Displays {
    /// The display with the pointer, where the Switchers appear.
    static var withPointer: NSScreen {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The frame of the display that shows most of `rect`, or nil if no display shows any of it. `rect`
    /// is in screen coordinates with the origin at the top left of the main display, as Accessibility and
    /// the window list give them; the result is in AppKit coordinates, like `NSScreen.frame`.
    static func frame(showingMostOf rect: CGRect) -> CGRect? {
        guard let main = NSScreen.screens.first else { return nil }
        let flipped = CGRect(x: rect.minX, y: main.frame.height - rect.maxY, width: rect.width, height: rect.height)
        let areas = NSScreen.screens.map { screen in
            let overlap = screen.frame.intersection(flipped)
            return (frame: screen.frame, area: overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        guard let best = areas.max(by: { $0.area < $1.area }), best.area > 0 else { return nil }
        return best.frame
    }
}
