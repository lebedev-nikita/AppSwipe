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

    /// Measured from the native switcher on macOS 27, in multiples of the icon artwork's size.
    struct Metrics {
        /// The artwork of a 128 pt icon, the native switcher's largest size.
        static let maxIcon: CGFloat = 103
        static let minIcon: CGFloat = 40
        static let screenFraction: CGFloat = 0.85
        static let titleFontSize: CGFloat = 13
        /// From the bottom of the highlights to the title's baseline.
        static let titleBaseline: CGFloat = 17
        /// From the title's baseline to the bottom of the panel.
        static let bottomPadding: CGFloat = 10

        private static let pitchRatio: CGFloat = 1.29
        private static let insetRatio: CGFloat = 0.074
        private static let paddingRatio: CGFloat = 0.272

        /// Size of an icon's visible artwork, without the transparent margins around it.
        let icon: CGFloat
        /// Distance between the centres of neighbouring Items.
        var pitch: CGFloat { (icon * Self.pitchRatio).rounded() }
        /// Margin between an icon's artwork and the edge of its highlight.
        var inset: CGFloat { (icon * Self.insetRatio).rounded() }
        var highlight: CGFloat { icon + 2 * inset }
        /// From the panel's edge to the nearest highlight.
        var padding: CGFloat { (icon * Self.paddingRatio).rounded() }
        /// Corners are concentric: the highlight's wraps the icon's, the panel's wraps the highlight's.
        var highlightCornerRadius: CGFloat { icon * 0.225 + inset }
        var panelCornerRadius: CGFloat { highlightCornerRadius + padding }

        /// The largest icon that fits `count` Items into `width`, within the size limits.
        init(fitting count: Int, into width: CGFloat) {
            let count = CGFloat(max(count, 1))
            let width = width / (2 * Self.paddingRatio + (count - 1) * Self.pitchRatio + 1 + 2 * Self.insetRatio)
            icon = min(Self.maxIcon, max(Self.minIcon, width)).rounded(.down)
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

        // A light tint, to match the native switcher's slightly darker glass.
        glass.tintColor = NSColor(white: 0, alpha: 0.06)
        let content = NSView()
        glass.contentView = content
        panel.contentView = glass

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = row
        content.addSubview(scrollView)

        titleField.alignment = .center
        titleField.font = .systemFont(ofSize: Metrics.titleFontSize, weight: .bold)
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
        let pitch = metrics.pitch
        let highlight = metrics.highlight
        // Each Item spans one pitch; its highlight sits in the middle, leaving a gap to the next one.
        let sideGap = (pitch - highlight) / 2
        let edge = metrics.padding - sideGap
        let rowWidth = CGFloat(items.count) * pitch
        let visibleRowWidth = min(max(rowWidth, pitch), maxWidth - 2 * edge)

        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.enumerated().map { index, item in
            let view = ItemView(image: item.image, metrics: metrics)
            view.badge = item.badge
            view.frame = NSRect(x: CGFloat(index) * pitch, y: 0, width: pitch, height: highlight)
            row.addSubview(view)
            return view
        }
        row.frame = NSRect(x: 0, y: 0, width: rowWidth, height: highlight)

        let bottom = Metrics.bottomPadding + Metrics.titleBaseline
        let size = NSSize(width: visibleRowWidth + 2 * edge, height: metrics.padding + highlight + bottom)
        scrollView.frame = NSRect(x: edge, y: bottom, width: visibleRowWidth, height: highlight)
        glass.cornerRadius = metrics.panelCornerRadius
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
    /// Share of an app icon's canvas that its artwork covers: 824 of 1024 points on Apple's icon grid.
    private static let artworkFraction: CGFloat = 0.805

    private let imageView: NSImageView
    private let highlightView = NSView()
    private let badgeView = BadgeView()
    private let metrics: SwitcherPanel.Metrics

    var isSelected = false {
        didSet { if isSelected != oldValue { updateSelection() } }
    }

    var badge: String? {
        get { badgeView.text }
        set {
            badgeView.text = newValue
            needsLayout = true
        }
    }

    init(image: NSImage, metrics: SwitcherPanel.Metrics) {
        imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        self.metrics = metrics
        super.init(frame: .zero)
        highlightView.wantsLayer = true
        highlightView.layer?.cornerCurve = .continuous
        highlightView.layer?.cornerRadius = metrics.highlightCornerRadius
        highlightView.isHidden = true
        addSubview(highlightView)
        addSubview(imageView)
        addSubview(badgeView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let iconSize = metrics.icon
        let highlight = metrics.highlight
        highlightView.frame = NSRect(
            x: (bounds.width - highlight) / 2, y: (bounds.height - highlight) / 2, width: highlight, height: highlight)
        let canvas = (iconSize / Self.artworkFraction).rounded()
        imageView.frame = NSRect(
            x: (bounds.width - canvas) / 2, y: (bounds.height - canvas) / 2, width: canvas, height: canvas)
        let icon = NSRect(
            x: (bounds.width - iconSize) / 2, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        // Like the Dock, the badge sits over the icon's top-right corner.
        let badgeHeight = (iconSize * 0.44).rounded()
        let badgeWidth = max(badgeHeight, badgeView.textWidth(forHeight: badgeHeight) + badgeHeight * 0.6)
        let center = NSPoint(x: icon.maxX - iconSize * 0.11, y: icon.maxY - iconSize * 0.09)
        badgeView.frame = NSRect(
            x: min(center.x - badgeHeight / 2, bounds.maxX - badgeWidth), y: center.y - badgeHeight / 2,
            width: badgeWidth, height: badgeHeight)
        badgeView.isHidden = badgeView.text == nil
    }

    private func updateSelection() {
        highlightView.isHidden = !isSelected
        guard isSelected else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        highlightView.layer?.backgroundColor =
            (isDark ? NSColor.white.withAlphaComponent(0.2) : NSColor.black.withAlphaComponent(0.25)).cgColor
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
