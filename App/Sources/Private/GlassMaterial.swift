import AppKit

/// Gives the Switcher the glass material of the native Cmd-Tab switcher.
///
/// The public styles look milky in a window of a background app: through `.regular` or `.clear`,
/// 11% of the backdrop's contrast shows, against 24% through the native switcher. The private
/// variant 6 lets 20% through with a similar frosted blur. Measured on macOS 27.0.1 over a test
/// backdrop; see docs/adr/0003-touch-input-and-private-apis.md for the private API policy.
enum GlassMaterial {
    static let variant = 6
    private static let setter = NSSelectorFromString("set_variant:")

    /// Applies the material after `style` is set, since setting the style resets it. Leaves the public
    /// style in place if macOS drops the private property.
    static func useSwitcherMaterial(for glass: NSGlassEffectView) {
        guard glass.responds(to: setter) else { return }
        glass.setValue(variant, forKey: "_variant")
    }
}
