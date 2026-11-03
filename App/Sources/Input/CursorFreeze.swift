import CoreGraphics

/// Keeps the cursor still for a whole Switch Session, and hidden while the Switcher shows.
///
/// `SessionInputTap` swallows mouse movement during the session; this puts the cursor back in case
/// it moved anyway, and handles hiding.
@MainActor
final class CursorFreeze {
    private var position: CGPoint?
    private var isHidden = false
    private var allowedHiding = false

    func freeze() {
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
