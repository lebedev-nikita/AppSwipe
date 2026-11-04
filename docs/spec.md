# AppSwipe v1 specification

AppSwipe switches apps and windows with horizontal trackpad swipes. Terms in **bold** are defined in [GLOSSARY.md](../GLOSSARY.md); the reasons behind the larger decisions are in [docs/adr](adr/).

## Switchers

### App Switcher (three fingers by default)

- Items: every running app with a Dock icon, including hidden apps, apps whose windows are all minimized, and apps without windows. Menu-bar-only agents are excluded. A setting, on by default, leaves out Finder while it has no windows; minimized windows and windows on other Spaces count, the desktop doesn't, and Finder stays when it is the Active App.
- Displays: apps from all displays by default. A setting limits the list to the display with the pointer: the Active App, then the apps with a window on the Current Space of that display, which leaves out hidden apps and apps without visible windows. A window belongs to the display that shows most of it.
- Order: most recently used first, so the Active App is the Current Item.
- Look: one row of app icons, with the selected app's name below. Icons carry the same badges as in the Dock, such as unread counts.
- Commit activates the app, brings all its windows forward, and unhides it if hidden. If the app has no visible window, Commit behaves like a click on its Dock icon: it restores the most recent minimized window, or lets the app open a new one.

### Window Switcher (four fingers by default)

- Items: the Active App's windows on the **Current Space**. That means ordinary windows, dialogs, and panels such as tool palettes.
- Displays: windows on all displays by default. A setting limits the list to the windows on the display with the pointer, minimized ones included by where they were before minimizing.
- Excluded:
  - transient popups, such as menus, popovers, tooltips and autocomplete lists, because they close as soon as focus moves;
  - invisible and zero-size windows;
  - sheets, which belong to their parent window.
- Order: ordinary windows and dialogs come first, most recently used first. Panels come next, then minimized windows, which are marked as minimized.
- Look: one row of **Window Previews** of equal height, with the selected window's title below. An untitled window shows the app's name.
- Commit focuses the window, un-minimizing it first if needed.

### Shared behaviour

- The Selection is a rounded highlight behind the selected icon or preview, as in the native switcher.
- Like the native switcher, the glass is lighter than what is behind it in the light theme and darker in the dark theme, and the highlight and title follow the theme.
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
   - A Step is a fixed physical distance, 8 mm by default and adjustable in Settings, with no acceleration.
   - The Selection stops at either end of the list instead of wrapping around.
   - Direction ignores the natural-scrolling setting.
4. **Commit** happens as soon as the finger count drops below the count the session started with. The Selection is frozen at that moment.
5. **Cancel** means committing while the Current Item is selected, or pressing Esc.
6. The cursor stays still from the moment the fingers land, and is hidden while the Switcher shows, so it never wanders over other apps. It reappears where it was. Clicks and Force Clicks during a session don't reach the app under the cursor.
7. The Switcher appears the moment the session opens. Lifting the fingers within about 200 ms of that is a **Quick Switch**: it Commits to the second Item, whatever the direction and travel. In the spike, quick flicks took 62–133 ms from opening to lift, while deliberate swipes took 480–660 ms.

### Windows of the selected app

In the App Switcher, moving the fingers down without lifting them opens the Window Switcher for the selected app, under the App Switcher, which stays open. The Selection moves to the app's windows, starting on the first of them, and sideways travel steps through them. Moving the fingers up hides them and gives the Selection back to the App Switcher, on the same app.

- A stroke counts once the fingers travel 6 mm up or down and at least twice as far as sideways, counting from when they last moved sideways. Drift while stepping through Items doesn't add up to a stroke.
- The windows are those the Window Switcher would list for that app, from the same displays.
- Commit focuses the selected window and activates its app, unhiding it if hidden. With no windows, Commit switches to the app as the App Switcher does.
- Every window Commits, the first one too, and there is no Quick Switch. To Cancel, move up and lift on the Current Item, or press Esc.
- With Live Switching, the first window comes forward as the windows open, and then each window the Selection lands on. A hidden app stays hidden until Commit.
- A setting, off by default, opens this straight away, in place of App Exposé: swiping down with the App Switcher's fingers opens the App Switcher on the Active App with its windows below. Moving up gives the Selection to the Active App, where lifting Cancels.

### Live Switching

With **Live Switching** on, there is no waiting for the fingers to lift: the selected Item is activated the moment the Selection lands on it, starting with the second Item when the session opens. It works the same in both Switchers.

- While the Selection passes over Items, activation is plain:
  - an app without windows becomes active without opening one;
  - a hidden app is not activated, and neither is an app whose windows are all minimized or on other Spaces, so the screen doesn't jump between Spaces;
  - a window is raised, and a minimized window stays minimized.
- On Commit, the selected Item gets the full treatment: an app opens like a Dock click and unhides; a window un-minimizes.
- Quick Switch still applies.
- Cancel, by lifting on the Current Item or pressing Esc, activates the Active App again.
- In the App Switcher, only the final app counts as used: it moves to the front of the order, the Active App becomes second, and the apps passed over keep their places. The native Cmd-Tab order may still record them.
- In the Window Switcher, windows passed over stay raised. Accessibility can only raise a window to the top, so putting them back would flash them over the window switched to.

Constraints:

- v1 has no other actions during a session: no quit, hide, or close. Vertical finger movement only opens and hides the selected app's windows.
- A session does not start while Mission Control or App Exposé is open, while the screen is locked, while AppSwipe is paused, or while an excluded app is frontmost.
- Keyboard Cmd-Tab and Cmd-` are left to the system. AppSwipe only listens to Esc, and only during a session.

## App shell

### Menu bar

AppSwipe is a menu bar agent with no Dock icon. Its menu bar icon offers Settings…, Pause, and Quit. The icon can be hidden, after which launching the app again opens Settings.

While Settings is open, AppSwipe is a regular app with a Dock icon, a menu bar and a place in Command-Tab and the App Switcher, so the window can't get lost behind other apps. ⌘W closes the window and ⌘Q quits. Closing the window makes AppSwipe an agent again and returns the focus to the app that was in front.

### Settings

Settings stay few on purpose. The opening travel, the Quick Switch window and the panel's look come from measurements and the native switcher, and a control for them could only make things worse.

- Launch at login. If macOS refuses or waits for approval under Login Items, Settings says so.
- Pause, the same as in the menu, so AppSwipe can be resumed while the menu bar icon is hidden.
- Show the menu bar icon.
- Enable or disable each Switcher.
- For each Switcher, list Items from all displays or only from the display with the pointer. All displays by default.
- Swap finger counts: four fingers for the App Switcher, three for the Window Switcher.
- Swipe down for the Active App's windows, in place of App Exposé. Off by default.
- Step length, with a strip to try it on: swiping across it shows how many Steps the travel makes.
- Excluded apps, added from the running apps or with an open panel. While one of them is frontmost, swipes do nothing, for games and apps with their own three- and four-finger gestures.
- Hide Finder from the App Switcher while it has no windows. On by default.
- Live Switching, described below. Off by default.
- Permission status, with buttons that open the matching pane of System Settings. Accessibility is required. Screen Recording is optional and only needed for Window Previews; it takes effect after AppSwipe is quit and opened again. The status updates while Settings is open.
- Gesture conflicts, described below.
- Diagnostics: recording touches, and showing the logs, for bug reports. The touch log keeps the last 10 MB, in two files.

Options for the Window Switcher, such as hiding minimized windows, wait until it exists. There is no haptic feedback, no acceleration and no keyboard shortcut to configure.

Permissions and gesture conflicts come first, so the first launch shows what AppSwipe still needs without scrolling. The window fits short screens and can be made taller.

The first launch opens Settings.

### Gesture conflicts

AppSwipe detects these conflicting system settings:

- three- or four-finger swipes between full-screen apps and Spaces;
- three-finger swipe between pages;
- App Exposé on the swipe down, while the swipe down opens the Active App's windows;
- three-finger drag.

A "Turn off" button rewrites the trackpad preferences and applies them without a logout. For App Exposé it turns off only App Exposé, which keeps Mission Control on the swipe up. If applying fails, the button opens Trackpad settings with instructions instead. The original values are remembered, and a "Restore" button puts them back. Removing AppSwipe does not restore them, so Settings asks to restore them first. Three-finger drag lives in Accessibility settings, so AppSwipe only warns about it. It conflicts with whichever Switcher uses three fingers; users who keep it can swap the finger counts and turn the three-finger Switcher off.

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
- Development builds and releases are signed with the same self-signed "AppSwipe Development" certificate, so Accessibility and Screen Recording grants survive rebuilds and updates.
- Releases are universal app zips on GitHub Releases, installed with the `app-swipe` cask from `lebedev-nikita/homebrew-tap`.
- App name: AppSwipe. Bundle ID: `io.github.lebedev-nikita.AppSwipe`. License: MIT.

## Out of scope for v1

- Windows on other Spaces.
- Actions inside a session.
- Keyboard switching.
- Gestures other than three- and four-finger horizontal swipes.
- The App Store.
- Notarized releases, which need a Developer ID.
- Suppressing system gestures by swallowing Dock events.

## Milestones

1. Spike:
   - read touches through an event tap on macOS 27;
   - check that rewriting trackpad preferences takes effect without a logout.
2. Pure Switch Session module with tests.
3. App Switcher end to end.
4. Window Switcher with app icon and title in place of previews.
5. Window Previews.
6. Settings, gesture conflicts, permission status, launch at login.
7. Live Switching.

## Spike findings

Measured on macOS 27.0.1 with a 16-inch MacBook Pro on 2026-11-03:

- A listen-only gesture tap is created without any permission, but receives nothing until Accessibility is granted. Input Monitoring is not needed. A tap created before the grant stays silent, so the app re-creates it when permissions change.
- Gesture events deliver three- and four-finger touches at about 126 Hz. `NSTouch.deviceSize` reports the surface as 157×97 mm.
- Fingers lift one by one, 7–30 ms apart.
- Rewriting the trackpad preferences and running `activateSettings -u` turns off the system's horizontal swipes without a logout.
- Accessibility grants survive rebuilds signed with the self-signed certificate.
- The agent app can bring another app forward with `NSRunningApplication.activate(options:)`, in about 20 ms, even long after launch. Setting `AXFrontmost` through Accessibility is accepted but ignored.

## Open questions

- Do gesture taps keep working after sleep?
- Can Mission Control be detected without private APIs? Until then, a session can start while it is open.
- Do three- and four-finger movements leak scroll events to the app under the pointer?
- Does the Screen Recording re-approval prompt still appear on macOS 26 and 27?
