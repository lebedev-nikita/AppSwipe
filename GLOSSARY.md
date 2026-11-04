# AppSwipe

A macOS app that switches between apps and windows with horizontal trackpad swipes, showing a switcher overlay that follows the fingers until they lift.

## Switchers

**Switcher**:
An overlay listing Items that stays open for the length of a Switch Session. Either the App Switcher or the Window Switcher.
_Avoid_: Menu, popup, HUD

**App Switcher**:
The Switcher opened by a three-finger horizontal swipe, or four-finger if the finger counts are swapped. It lists running apps as icons in most-recently-used order, the counterpart of Cmd-Tab.
_Avoid_: Cmd-Tab menu, app menu

**Window Switcher**:
The Switcher opened by a four-finger horizontal swipe, or three-finger if the finger counts are swapped. It lists only the Active App's windows on the Current Space, as Window Previews, the counterpart of Cmd-` with a visible list.
_Avoid_: Window menu, Cmd-` menu, Exposé

**Item**:
One entry in a Switcher: an app in the App Switcher, a window in the Window Switcher.
_Avoid_: Entry, tile, cell

**Current Item**:
The first Item in a Switcher: the Active App, or the Active App's most recently used window.
_Avoid_: Origin, home

**Window Preview**:
A thumbnail image of a window, shown as its Item in the Window Switcher.
_Avoid_: Thumbnail, snapshot

**Active App**:
The frontmost app at the moment a Switch Session starts.
_Avoid_: Current app, focused app

**Current Space**:
The Spaces shown right now, one per display. A full-screen window is on the Current Space only while its own Space is shown.
_Avoid_: Active Space, current desktop

## Switch Session

**Switch Session**:
The span from a Switcher opening to its Commit or Cancel, lasting while the fingers stay on the trackpad.
_Avoid_: Gesture session, swipe session

**Selection**:
The highlighted Item in an open Switcher.
_Avoid_: Focus, cursor, highlight

**Step**:
The horizontal finger travel that moves the Selection by one Item.
_Avoid_: Tick, notch

**Commit**:
Ending a Switch Session by lifting the fingers, which activates the Selection.
_Avoid_: Confirm, release, accept

**Cancel**:
Ending a Switch Session without switching: lifting the fingers with the Current Item selected, or pressing Esc.
_Avoid_: Abort, dismiss

**Live Switching**:
A mode in which the selected Item is activated the moment the Selection lands on it, before Commit.
_Avoid_: Instant switching, preview mode

**Quick Switch**:
A Switch Session whose fingers lift within about 200 ms of its start. It always Commits to the second Item, the counterpart of a quick Cmd-Tab tap.
_Avoid_: Flick, quick tap
