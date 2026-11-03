import CoreGraphics

/// Keeps the cursor still from the moment the fingers land until they lift, and hidden while a
/// Switcher shows.
///
/// `SessionInputTap` swallows pointer movement meanwhile; this puts the cursor back where the fingers
/// landed in case it moved anyway, and handles hiding.
@MainActor
final class CursorFreeze {
    private var position: CGPoint?
    private var isHidden = false
    private var allowedHiding = false

    /// Remembers where the cursor is. Later calls keep the first position until `release`.
    func freeze() {
        guard position == nil else { return }
        position = CGEvent(source: nil)?.location
    }

    func hide() {
        guard position != nil, !isHidden else { return }
        if !allowedHiding {
            allowedHiding = true
            if !BackgroundCursor.allowHiding() { DiagnosticLog.write("cannot allow hiding the cursor in background") }
        }
        CGDisplayHideCursor(CGMainDisplayID())
        isHidden = true
    }

    func release() {
        if let position, CGEvent(source: nil)?.location != position {
            CGWarpMouseCursorPosition(position)
            // Without this, the cursor ignores the mouse for a moment after a warp.
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        if isHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            isHidden = false
        }
        position = nil
    }
}
