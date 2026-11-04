import AppKit

/// The floating Switcher: a glass panel with one row of Items and the Selection's title below it.
///
/// Proportions follow the native Cmd-Tab switcher of macOS 27, measured from a screenshot.
@MainActor
final class SwitcherPanel {
    struct Item {
        /// An app icon; for a window, shown until its preview arrives.
        let image: NSImage
        let title: String
        var badge: String?
        /// Drawn faded, as for a minimized window.
        var isDimmed = false
        /// Width over height of a window's preview; nil for an app icon.
        var aspect: CGFloat?
        var preview: CGImage?
    }

    /// Measured from the native switcher on macOS 27, in multiples of the icon artwork's size.
    struct Metrics {
        /// The artwork of a 128 pt icon, the native switcher's largest size.
        static let maxSize: CGFloat = 103
        static let minSize: CGFloat = 40
        static let screenFraction: CGFloat = 0.85
        static let titleFontSize: CGFloat = 13
        /// From the bottom of the highlights to the title's baseline.
        static let titleBaseline: CGFloat = 17
        /// From the title's baseline to the bottom of the panel.
        static let bottomPadding: CGFloat = 10
        /// Between a Switcher and the one shown under it.
        static let stackGap: CGFloat = 12

        private static let insetRatio: CGFloat = 0.074
        private static let gapRatio: CGFloat = 0.142
        private static let paddingRatio: CGFloat = 0.272
        /// Very narrow or wide windows get a preview of this shape, cropped to fit.
        private static let aspects: ClosedRange<CGFloat> = 0.6...2.0

        /// Height of every Item's content: an icon's visible artwork, without the transparent margins
        /// around it, or a window's preview.
        let size: CGFloat
        /// Margin between an Item's content and the edge of its highlight.
        var inset: CGFloat { (size * Self.insetRatio).rounded() }
        /// Space between neighbouring highlights.
        var gap: CGFloat { (size * Self.gapRatio).rounded() }
        var highlightHeight: CGFloat { size + 2 * inset }
        /// From the panel's edge to the nearest highlight.
        var padding: CGFloat { (size * Self.paddingRatio).rounded() }
        var iconCornerRadius: CGFloat { size * 0.225 }
        var previewCornerRadius: CGFloat { size * 0.07 }
        /// Corners are concentric: a highlight wraps its icon or preview, and the panel wraps the
        /// highlight. Window previews have squarer corners than icons, so their panel does too.
        func panelCornerRadius(windows: Bool) -> CGFloat {
            (windows ? previewCornerRadius : iconCornerRadius) + inset + padding
        }

        /// The panel widens until titles get as much room as the widest possible window preview; longer
        /// ones are cut short.
        var minTitleWidth: CGFloat { contentWidth(aspect: Self.aspects.upperBound) }

        func contentWidth(aspect: CGFloat?) -> CGFloat {
            guard let aspect else { return size }
            return (size * min(max(aspect, Self.aspects.lowerBound), Self.aspects.upperBound)).rounded()
        }

        /// An Item's highlight plus the gap to its neighbour.
        func itemWidth(aspect: CGFloat?) -> CGFloat {
            contentWidth(aspect: aspect) + 2 * inset + gap
        }

        /// The largest size that fits Items of these shapes into `width`, within the size limits.
        init(fitting aspects: [CGFloat?], into width: CGFloat) {
            let widths = aspects.map { aspect in
                aspect.map { min(max($0, Self.aspects.lowerBound), Self.aspects.upperBound) } ?? 1
            }
            let perItem = widths.reduce(0) { $0 + $1 + 2 * Self.insetRatio + Self.gapRatio }
            let total = max(perItem, 1 + 2 * Self.insetRatio + Self.gapRatio) - Self.gapRatio + 2 * Self.paddingRatio
            size = min(Self.maxSize, max(Self.minSize, width / total)).rounded(.down)
        }
    }

    /// White over the glass, per theme, measured against the native switcher's brightness.
    private static let veilLight: CGFloat = 0.30
    private static let veilDark: CGFloat = 0.12

    private let panel: NSPanel
    private let glass = NSGlassEffectView()
    private let content = NSView()
    /// Sets the glass's brightness per theme; see `applyTheme`.
    private let veil = NSView()
    private let scrollView = NSScrollView()
    private let row = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private var items: [Item] = []
    private var itemViews: [ItemView] = []
    private var metrics = Metrics(fitting: [nil], into: 1000)

    init() {
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass draws its own edge.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // Appear and disappear at once, without the default fade.
        panel.animationBehavior = .none

        GlassMaterial.useSwitcherMaterial(for: glass)
        glass.contentView = content
        panel.contentView = glass

        veil.wantsLayer = true
        veil.layer?.cornerCurve = .continuous
        veil.autoresizingMask = [.width, .height]
        content.addSubview(veil)

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
        let screen = Displays.withPointer
        let maxWidth = screen.visibleFrame.width * Metrics.screenFraction
        metrics = Metrics(fitting: items.map(\.aspect), into: maxWidth)
        let height = metrics.highlightHeight
        // Each Item's view holds its highlight in the middle, with half the gap on either side.
        let edge = metrics.padding - metrics.gap / 2

        itemViews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 0
        itemViews = items.map { item in
            let view = ItemView(image: item.image, aspect: item.aspect, metrics: metrics)
            view.badge = item.badge
            view.isDimmed = item.isDimmed
            view.preview = item.preview
            let width = metrics.itemWidth(aspect: item.aspect)
            view.frame = NSRect(x: x, y: 0, width: width, height: height)
            x += width
            row.addSubview(view)
            return view
        }
        let rowWidth = max(x, metrics.itemWidth(aspect: nil))
        let visibleRowWidth = min(rowWidth, maxWidth - 2 * edge)
        row.frame = NSRect(x: 0, y: 0, width: rowWidth, height: height)

        let bottom = Metrics.bottomPadding + Metrics.titleBaseline
        // Titles stay within the rounded edges. The panel widens for the longest one, up to the minimum
        // room, so its width doesn't change as the Selection moves.
        let longestTitle = items.map { titleWidth(of: $0.title) }.max() ?? 0
        let titleRoom = min(longestTitle, metrics.minTitleWidth) + 2 * (metrics.padding + metrics.inset)
        let width = min(max(visibleRowWidth + 2 * edge, titleRoom), maxWidth)
        let size = NSSize(width: width, height: metrics.padding + height + bottom)
        scrollView.frame = NSRect(
            x: ((width - visibleRowWidth) / 2).rounded(), y: bottom, width: visibleRowWidth, height: height)
        // Only the Window Switcher can be empty, when it shows "No windows".
        let cornerRadius = metrics.panelCornerRadius(windows: items.isEmpty || items.contains { $0.aspect != nil })
        glass.cornerRadius = cornerRadius
        veil.layer?.cornerRadius = cornerRadius
        let frame = screen.frame
        panel.setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                   width: size.width, height: size.height).integral,
            display: false)
        veil.frame = content.bounds
        applyTheme()
        select(selection)
    }

    /// The glass material darkens what is behind it in the light appearance and brightens it in the dark
    /// one, the opposite of the native switcher. So the glass always renders in the light appearance,
    /// a veil sets its brightness per theme, and the Items and title follow the system's theme.
    private func applyTheme() {
        let theme = panel.effectiveAppearance
        let isDark = theme.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        glass.appearance = NSAppearance(named: .aqua)
        content.appearance = theme
        veil.layer?.backgroundColor = NSColor.white.withAlphaComponent(isDark ? Self.veilDark : Self.veilLight).cgColor
    }

    func setPreview(_ preview: CGImage, at index: Int) {
        guard itemViews.indices.contains(index) else { return }
        itemViews[index].preview = preview
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
        // Center the title under the selected Item, with its baseline at a fixed distance from the
        // bottom edge. Like the native switcher, a title wider than the end Item shifts inwards, to stay
        // within the outer edges of the end Items' content, and one wider than that is cut short.
        let size = titleField.intrinsicContentSize
        let bounds = content.bounds.insetBy(dx: metrics.padding + metrics.inset, dy: 0)
        let width = min(titleWidth(of: title), bounds.width)
        let x = width < bounds.width
            ? min(max(center - width / 2, bounds.minX), bounds.maxX - width)
            : bounds.midX - width / 2
        let baseline = Metrics.bottomPadding
        let y = baseline - (size.height - titleField.firstBaselineOffsetFromTop)
        titleField.frame = NSRect(x: x, y: y, width: width, height: size.height).integral
    }

    /// The width the title field takes for `title`, with a little room on either side.
    private func titleWidth(of title: String) -> CGFloat {
        titleField.stringValue = title
        return titleField.intrinsicContentSize.width + 8
    }

    /// Centres `top` and `bottom` together on the display with the pointer, `bottom` under `top`.
    static func stack(_ top: SwitcherPanel, over bottom: SwitcherPanel) {
        let screen = Displays.withPointer
        let height = top.frame.height + Metrics.stackGap + bottom.frame.height
        let maxY = min(screen.frame.midY + height / 2, screen.visibleFrame.maxY)
        top.moveVertically(to: maxY - top.frame.height)
        bottom.moveVertically(to: max(maxY - height, screen.visibleFrame.minY))
    }

    /// Centres the panel on the display with the pointer again, as `prepare` places it.
    func center() {
        moveVertically(to: Displays.withPointer.frame.midY - panel.frame.height / 2)
    }

    private func moveVertically(to y: CGFloat) {
        var frame = panel.frame
        frame.origin.y = y
        panel.setFrame(frame.integral, display: false)
    }

    func show() {
        applyTheme()
        panel.orderFrontRegardless()
    }

    var frame: NSRect { panel.frame }

    #if DEBUG
    /// Overrides the system appearance, for comparing themes.
    func setAppearance(_ appearance: NSAppearance?) {
        panel.appearance = appearance
    }

    func setGlassVariant(_ variant: Int, values: [String: Int] = [:]) {
        glass.setValue(variant, forKey: "_variant")
        for (key, value) in values { glass.setValue(value, forKey: key) }
    }
    #endif

    func hide() {
        panel.orderOut(nil)
    }
}

private final class ItemView: NSView {
    /// Share of an app icon's canvas that its artwork covers: 824 of 1024 points on Apple's icon grid.
    private static let artworkFraction: CGFloat = 0.805
    /// A window's app icon, shown until its preview arrives, relative to the preview's height.
    private static let placeholderFraction: CGFloat = 0.6

    private let icon: NSImage
    private let aspect: CGFloat?
    private let imageView: NSImageView
    private let highlightView = NSView()
    private let badgeView = BadgeView()
    private let metrics: SwitcherPanel.Metrics

    var isSelected = false {
        didSet { if isSelected != oldValue { updateSelection() } }
    }

    var isDimmed = false {
        didSet { imageView.alphaValue = isDimmed ? 0.45 : 1 }
    }

    var badge: String? {
        get { badgeView.text }
        set {
            badgeView.text = newValue
            needsLayout = true
        }
    }

    var preview: CGImage? {
        didSet {
            imageView.image = preview.map { NSImage(cgImage: $0, size: .zero) } ?? icon
            needsLayout = true
        }
    }

    init(image: NSImage, aspect: CGFloat?, metrics: SwitcherPanel.Metrics) {
        icon = image
        self.aspect = aspect
        imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        self.metrics = metrics
        super.init(frame: .zero)
        highlightView.wantsLayer = true
        highlightView.layer?.cornerCurve = .continuous
        let contentRadius = aspect == nil ? metrics.iconCornerRadius : metrics.previewCornerRadius
        highlightView.layer?.cornerRadius = contentRadius + metrics.inset
        highlightView.isHidden = true
        addSubview(highlightView)
        addSubview(imageView)
        addSubview(badgeView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let size = metrics.size
        let width = metrics.contentWidth(aspect: aspect)
        let content = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - size) / 2, width: width, height: size)
        highlightView.frame = content.insetBy(dx: -metrics.inset, dy: -metrics.inset)
        if aspect != nil {
            let side = preview == nil ? (size * Self.placeholderFraction).rounded() : 0
            imageView.frame = preview == nil
                ? NSRect(x: content.midX - side / 2, y: content.midY - side / 2, width: side, height: side)
                : content
            badgeView.isHidden = true
            return
        }
        let canvas = (size / Self.artworkFraction).rounded()
        imageView.frame = NSRect(x: content.midX - canvas / 2, y: content.midY - canvas / 2, width: canvas, height: canvas)
        // Like the Dock, the badge sits over the icon's top-right corner.
        let badgeHeight = (size * 0.44).rounded()
        let badgeWidth = max(badgeHeight, badgeView.textWidth(forHeight: badgeHeight) + badgeHeight * 0.6)
        let center = NSPoint(x: content.maxX - size * 0.11, y: content.maxY - size * 0.09)
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
