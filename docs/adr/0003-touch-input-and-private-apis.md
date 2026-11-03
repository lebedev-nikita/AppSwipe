# Touch input via gesture event taps; private APIs only behind wrappers

Touches come from `CGEventTap` on gesture events, converted to `NSTouch`, as AltTab does. One mechanism both reads touches and, during a Switch Session, swallows them so the focused app doesn't react. It needs Accessibility, which the app requires anyway. A listen-only tap runs all the time; the active, swallowing tap runs only during a Switch Session, because an always-on active HID tap adds cursor lag ([lwouis/alt-tab-macos#5911](https://github.com/lwouis/alt-tab-macos/issues/5911)). The private MultitouchSupport.framework is the fallback if taps prove unreliable: it reads raw frames without a permission but cannot swallow anything.

More generally, public APIs come first. A private API is allowed only after a prototype shows the public one isn't enough, and each private API lives behind one thin wrapper, so a macOS update breaks a single place.

## Consequences

Neither mechanism can stop macOS from acting on a swipe. The user must turn off conflicting system gestures (horizontal swipes between full-screen apps and Spaces, three-finger swipe between pages, three-finger drag). The app detects them and offers to turn them off.
