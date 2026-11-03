# OpenSwipe v1 specification

OpenSwipe switches apps and windows with horizontal trackpad swipes. Terms in **bold** are defined in [GLOSSARY.md](../GLOSSARY.md); the reasons behind the larger decisions are in [docs/adr](adr/).

## Switchers

### App Switcher (three fingers)

- Items: every running app with a Dock icon, including hidden apps, apps whose windows are all minimized, and apps without windows. Menu-bar-only agents are excluded.
- Order: most recently used first, so the Active App is the Current Item.
- Look: one row of app icons, with the selected app's name below. Icons carry the same badges as in the Dock, such as unread counts.
- Commit activates the app, brings all its windows forward, and unhides it if hidden. If the app has no visible window, Commit behaves like a click on its Dock icon: it restores the most recent minimized window, or lets the app open a new one.

### Window Switcher (four fingers)

- Items: the Active App's windows on the **Current Space**. That means ordinary windows, dialogs, and panels such as tool palettes.
- Excluded:
  - transient popups, such as menus, popovers, tooltips and autocomplete lists, because they close as soon as focus moves;
  - invisible and zero-size windows;
  - sheets, which belong to their parent window.
- Order: ordinary windows and dialogs come first, most recently used first. Panels come next, then minimized windows, which are marked as minimized.
- Look: one row of **Window Previews** of equal height, with the selected window's title below. An untitled window shows the app's name.
- Commit focuses the window, un-minimizing it first if needed.

### Shared behaviour

- The Selection is a thin shadow that outlines the selected icon or preview.
- If the list has a single Item, the Switcher still opens, so the user sees that the gesture registered. With no windows at all, the Window Switcher shows a "No windows" placeholder.
- Window Previews come from ScreenCaptureKit and may be slightly stale. A preview is captured when the Switcher opens, or the last time the window was visible, and is cached.
- Without Screen Recording permission, each preview is replaced by the app icon and the window title.
- The row of Items:
  - stays a single row;
  - shrinks the Items down to a minimum size as the list grows;
  - then scrolls to follow the Selection.
- The Switcher is our own floating panel, not the system switcher, styled after the native Cmd-Tab switcher with Liquid Glass. It appears on the display that has the mouse pointer.

## Switch Session

1. A session starts when exactly three or four fingers travel horizontally past a small opening threshold. The finger count at that moment fixes which Switcher opens; fingers added later are ignored.
2. If the fingers start moving right, the Selection lands on the second Item. If they start moving left, it lands on the last Item, like Cmd-Shift-Tab.
3. Each **Step** moves the Selection one Item in the direction of finger travel. Moving back moves the Selection back.
   - A Step is a fixed physical distance, about 1 cm by default and adjustable in Settings, with no acceleration.
   - The Selection stops at either end of the list instead of wrapping around.
   - Direction ignores the natural-scrolling setting.
4. On a Force Touch trackpad, each Step plays a short haptic tick. This is on by default and can be turned off.
5. **Commit** happens as soon as the finger count drops below the count the session started with. The Selection is frozen at that moment.
6. **Cancel** means committing while the Current Item is selected, or pressing Esc.
7. The cursor stays still for the whole session and is hidden while the Switcher shows, so it never wanders over other apps. It reappears where it was.
8. The Switcher appears about 200 ms after the session starts, like the native switcher on a held Cmd-Tab. Lifting the fingers before then is a **Quick Switch**: it Commits to the second Item, whatever the direction and travel. In the spike, quick flicks took 100–170 ms and covered 21–41 mm, while deliberate swipes took 540–750 ms.

Constraints:

- v1 has no other actions during a session: no quit, hide, or close, and no opening an app's windows from the App Switcher. Vertical finger movement is reserved for such actions later.
- A session does not start while Mission Control or App Exposé is open, while the screen is locked, or while OpenSwipe is paused.
- Keyboard Cmd-Tab and Cmd-` are left to the system. OpenSwipe only listens to Esc, and only during a session.

## App shell

### Menu bar

OpenSwipe is a menu bar agent with no Dock icon. Its menu bar icon offers Settings…, Pause, and Quit. The icon can be hidden, after which launching the app again opens Settings.

### Settings

- Launch at login.
- Step length.
- Enable or disable each Switcher.
- Haptic feedback.
- Permission status, with buttons that open the matching pane of System Settings. Accessibility is required. Screen Recording is optional and only needed for Window Previews.
- Gesture conflicts, described below.

The first launch opens Settings.

### Gesture conflicts

OpenSwipe detects these conflicting system settings:

- three- or four-finger swipes between full-screen apps and Spaces;
- three-finger swipe between pages;
- three-finger drag.

A "Turn off" button rewrites the trackpad preferences and applies them without a logout. If applying fails, the button opens Trackpad settings with instructions instead. The original values are remembered, and a "Restore" button puts them back. Three-finger drag lives in Accessibility settings, so OpenSwipe only warns about it.

### Language

The interface is in English, with a Russian localization.

## Platform and project

- macOS 26 or later.
- Swift 6 and AppKit, with SwiftUI for Settings.
- Touch input and the policy on private APIs: [ADR 0003](adr/0003-touch-input-and-private-apis.md).
- The Switch Session logic is a pure module with no macOS dependencies. It takes touch frames as input and is unit-tested with synthetic and recorded frames. The adapters to the OS stay thin and are tested by hand:
  - touch input;
  - app and window lists;
  - activation;
  - preview capture;
  - the UI.
- The Xcode project is generated by XcodeGen from `project.yml`. Tools are pinned with mise, and commands run through Just.
- Development builds are signed with a local self-signed "OpenSwipe Development" certificate, so Accessibility grants survive rebuilds.
- App name: OpenSwipe. Bundle ID: `io.github.lebedev-nikita.OpenSwipe`. License: MIT.

## Out of scope for v1

- Windows on other Spaces.
- Actions inside a session.
- Keyboard switching.
- Remapping finger counts.
- The App Store.
- Signed and notarized releases, which come later through GitHub Releases with a Developer ID.
- Suppressing system gestures by swallowing Dock events.

## Milestones

1. Spike:
   - read touches through an event tap on macOS 27;
   - check that rewriting trackpad preferences takes effect without a logout.
2. Pure Switch Session module with tests.
3. App Switcher end to end.
4. Window Switcher with app icon and title in place of previews.
5. Window Previews.
6. Settings, gesture conflicts, permission status, launch at login, haptics.

## Spike findings

Measured on macOS 27.0.1 with a 16-inch MacBook Pro on 2026-11-03:

- A listen-only gesture tap is created without any permission, but receives nothing until Accessibility is granted. Input Monitoring is not needed. A tap created before the grant stays silent, so the app re-creates it when permissions change.
- Gesture events deliver three- and four-finger touches at about 126 Hz. `NSTouch.deviceSize` reports the surface as 157×97 mm.
- Fingers lift one by one, 7–30 ms apart.
- Rewriting the trackpad preferences and running `activateSettings -u` turns off the system's horizontal swipes without a logout.
- Accessibility grants survive rebuilds signed with the self-signed certificate.

## Open questions

- Do gesture taps keep working after sleep?
- Can an agent app reliably activate another app with public APIs on macOS 14 and later?
- Can Mission Control be detected without private APIs?
- Do three- and four-finger movements leak scroll events to the app under the pointer?
- Does the Screen Recording re-approval prompt still appear on macOS 26 and 27?
