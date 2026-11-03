import CoreGraphics

/// Keeps the cursor still from the moment the fingers land until they lift, and hidden while a
/// Switcher shows.
///
/// `SessionInputTap` swallows pointer movement meanwhile; this puts the cursor back where the fingers
/// landed in case it moved anyway, and handles hiding.
@MainActor
final class CursorFreeze {
    private var position: CGPoint?
    /// Calls to `CGDisplayHideCursor` not yet balanced by `CGDisplayShowCursor`.
    private var hides = 0
    private var allowedHiding = false
    private var reassertion: Task<Void, Never>?

    /// Remembers where the cursor is. Later calls keep the first position until `release`.
    func freeze() {
        guard position == nil else { return }
        position = CGEvent(source: nil)?.location
    }

    func hide() {
        guard position != nil, hides == 0 else { return }
        if !allowedHiding {
            allowedHiding = true
            if !BackgroundCursor.allowHiding() { DiagnosticLog.write("cannot allow hiding the cursor in background") }
        }
        hideOnce()
    }

    /// Hides the cursor again over the next moments. Another app becoming active, as during Live
    /// Switching, can bring the cursor back.
    func reassertHidden() {
        guard hides > 0 else { return }
        hideOnce()
        reassertion?.cancel()
        reassertion = Task { [weak self] in
            for delay in [20, 60, 150] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, !Task.isCancelled, hides > 0 else { return }
                hideOnce()
            }
        }
    }

    func release() {
        reassertion?.cancel()
        if let position, CGEvent(source: nil)?.location != position {
            CGWarpMouseCursorPosition(position)
            // Without this, the cursor ignores the mouse for a moment after a warp.
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        while hides > 0 {
            CGDisplayShowCursor(CGMainDisplayID())
            hides -= 1
        }
        position = nil
    }

    private func hideOnce() {
        CGDisplayHideCursor(CGMainDisplayID())
        hides += 1
    }
}
