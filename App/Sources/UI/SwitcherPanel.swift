import AppKit

/// The floating Switcher: a glass panel with one row of Items and the Selection's title below it.
///
/// Proportions follow the native Cmd-Tab switcher of macOS 27, measured from a screenshot.
@MainActor
final class SwitcherPanel {
    struct Item {
        let image: NSImage
        let title: String
        var badge: String?
    }

    private struct Metrics {
        static let maxIcon: CGFloat = 88
        static let minIcon: CGFloat = 40
        static let screenFraction: CGFloat = 0.85
        static let titleFontSize: CGFloat = 13
        /// From the bottom of the row to the title's baseline.
        static let titleBaseline: CGFloat = 17
        /// From the title's baseline to the bottom of the panel.
        static let bottomPadding: CGFloat = 6

        /// Size of an icon's visible artwork, without the transparent margins around it.
        let icon: CGFloat
        var cell: CGFloat { (icon * 1.3).rounded() }
        var horizontalPadding: CGFloat { (icon * 0.18).rounded() }
        var topPadding: CGFloat { (icon * 0.25).rounded() }
        var cornerRadius: CGFloat { (icon * 0.21).rounded() }

        /// The largest icon that fits `count` Items into `width`, within the size limits.
        init(fitting count: Int, into width: CGFloat) {
            let count = CGFloat(max(count, 1))
            let fitting = (width - 2 * 0.18 * Self.maxIcon) / count / 1.3
            icon = min(Self.maxIcon, max(Self.minIcon, fitting)).rounded(.down)
        }
    }

    private let panel: NSPanel
    private let glass = NSGlassEffectView()
    private let scrollView = NSScrollView()
    private let row = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private var items: [Item] = []
    private var itemViews: [ItemView] = []
    private var metrics = Metrics(fitting: 1, into: 1000)

    init() {
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass draws its own edge.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let content = NSView()
        glass.contentView = content
        panel.contentView = glass

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = row
        content.addSubview(scrollView)

        titleField.alignment = .center
        titleField.font = .systemFont(ofSize: Metrics.titleFontSize)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        content.addSubview(titleField)
    }

    /// Lays out `items` for the screen with the pointer, without showing the panel.
    func prepare(_ items: [Item], selection: Int) {
        self.items = items
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let maxWidth = screen.visibleFrame.width * Metrics.screenFraction
        metrics = Metrics(fitting: items.count, into: maxWidth)
        let cell = metrics.cell
        let rowWidth = CGFloat(items.count) * cell
        let visibleRowWidth = min(max(rowWidth, cell), maxWidth - 2 * metrics.horizontalPadding)

        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.enumerated().map { index, item in
            let view = ItemView(image: item.image, iconSize: metrics.icon)
            view.badge = item.badge
            view.frame = NSRect(x: CGFloat(index) * cell, y: 0, width: cell, height: cell)
            row.addSubview(view)
            return view
        }
        row.frame = NSRect(x: 0, y: 0, width: rowWidth, height: cell)

        let bottom = Metrics.bottomPadding + Metrics.titleBaseline
        let size = NSSize(
            width: visibleRowWidth + 2 * metrics.horizontalPadding,
            height: metrics.topPadding + cell + bottom)
        scrollView.frame = NSRect(x: metrics.horizontalPadding, y: bottom, width: visibleRowWidth, height: cell)
        glass.cornerRadius = metrics.cornerRadius
        let frame = screen.frame
        panel.setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                   width: size.width, height: size.height).integral,
            display: false)
        select(selection)
    }

    func setBadges(_ badges: [Int: String]) {
        for (index, view) in itemViews.enumerated() { view.badge = badges[index] }
    }

    func select(_ index: Int) {
        for (offset, view) in itemViews.enumerated() { view.isSelected = offset == index }
        let title: String
        var center = scrollView.frame.midX
        if itemViews.indices.contains(index) {
            let view = itemViews[index]
            view.scrollToVisible(view.bounds)
            title = items[index].title
            center = scrollView.frame.minX + view.frame.midX - scrollView.documentVisibleRect.minX
        } else {
            title = items.isEmpty ? String(localized: "No windows") : ""
        }
        titleField.stringValue = title
        // Center the title under the selected Item, keeping it inside the panel, with its baseline
        // at a fixed distance from the bottom edge.
        let size = titleField.intrinsicContentSize
        let width = min(size.width + 8, scrollView.frame.width)
        let x = min(max(center - width / 2, scrollView.frame.minX), scrollView.frame.maxX - width)
        let baseline = Metrics.bottomPadding
        let y = baseline - (size.height - titleField.firstBaselineOffsetFromTop)
        titleField.frame = NSRect(x: x, y: y, width: width, height: size.height).integral
    }

    func show() {
        panel.orderFrontRegardless()
    }

    var frame: NSRect { panel.frame }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class ItemView: NSView {
    private let imageView: NSImageView
    private let iconSize: CGFloat
    private let badgeView = BadgeView()

    var isSelected = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    var badge: String? {
        get { badgeView.text }
        set {
            badgeView.text = newValue
            needsLayout = true
        }
    }

    init(image: NSImage, iconSize: CGFloat) {
        imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        self.iconSize = iconSize
        super.init(frame: .zero)
        addSubview(imageView)
        addSubview(badgeView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Share of an app icon's canvas that its artwork covers: 824 of 1024 points on Apple's icon grid.
    private static let artworkFraction: CGFloat = 0.805

    override func layout() {
        super.layout()
        let canvas = (iconSize / Self.artworkFraction).rounded()
        imageView.frame = NSRect(
            x: (bounds.width - canvas) / 2, y: (bounds.height - canvas) / 2, width: canvas, height: canvas)
        let icon = NSRect(
            x: (bounds.width - iconSize) / 2, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        // Like the Dock, the badge sits over the icon's top-right corner.
        let height = (iconSize * 0.44).rounded()
        let width = max(height, badgeView.textWidth(forHeight: height) + height * 0.6)
        let center = NSPoint(x: icon.maxX - iconSize * 0.11, y: icon.maxY - iconSize * 0.09)
        badgeView.frame = NSRect(
            x: min(center.x - height / 2, bounds.maxX - width), y: center.y - height / 2,
            width: width, height: height)
        badgeView.isHidden = badgeView.text == nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark ? NSColor.white.withAlphaComponent(0.2) : NSColor.black.withAlphaComponent(0.24)).setFill()
        let radius = (iconSize * 0.07).rounded()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}

/// A Dock-style badge: white text on a red capsule.
private final class BadgeView: NSView {
    var text: String? {
        didSet { needsDisplay = true }
    }

    func textWidth(forHeight height: CGFloat) -> CGFloat {
        guard let text else { return 0 }
        return (text as NSString).size(withAttributes: attributes(forHeight: height)).width
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let text else { return }
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let attributes = attributes(forHeight: bounds.height)
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes)
    }

    private func attributes(forHeight height: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: height * 0.58, weight: .regular), .foregroundColor: NSColor.white]
    }
}
