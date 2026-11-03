# Own app instead of AltTab or SwipeSwitcher

AltTab already opens its switcher with a three- or four-finger swipe and moves the Selection as the fingers travel, but it has a single gesture slot, so an App Switcher on three fingers and a Window Switcher on four cannot coexist ([lwouis/alt-tab-macos#4556](https://github.com/lwouis/alt-tab-macos/issues/4556); the maintainer is reluctant to add more). We build our own MIT-licensed app instead of forking AltTab's large GPL-3.0 codebase.

## Considered Options

- **AltTab on four fingers plus SwipeSwitcher on three fingers.** Works without new code, but means two apps with different looks and behaviour, neither under our control.
- **Fork AltTab and add a second gesture slot.** Large codebase, GPL-3.0, and little chance of the change landing upstream.

## Consequences

Code may be borrowed only from permissively licensed projects such as [SwipeSwitcher](https://github.com/haonlabs/SwipeSwitcher) (MIT), with attribution. AltTab (GPL-3.0), cyclist and Touch-Tab (no license) are reading references only.
