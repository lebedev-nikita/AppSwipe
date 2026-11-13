import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let conflicts: TrackpadConflicts
    let trial: StepTrial
    /// Sections needing action go first, the rest where they usually are. Decided when the window opens,
    /// so granting a permission or turning off a gesture doesn't move a section away under the pointer.
    let attention: Attention
    @State private var permissions = PermissionState()
    @State private var runningApps = RunningApp.all()

    var body: some View {
        // What is changed most comes first, then how swipes are read, then what rarely needs a look.
        // What AppSwipe still needs jumps ahead, so the first launch shows it without scrolling.
        Form {
            if attention.permissions { permissionsSection }
            if attention.trackpad { trackpadSection }
            generalSection
            appSwitcherSection
            windowSwitcherSection
            switchingSection
            if !attention.trackpad { trackpadSection }
            excludedAppsSection
            if !attention.permissions { permissionsSection }
            diagnosticsSection
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 320, maxHeight: .infinity)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            runningApps = RunningApp.all()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            runningApps = RunningApp.all()
        }
        // Access granted in System Settings shows up here without switching back to this window.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let current = PermissionState()
                if current != permissions { permissions = current }
            }
        }
        .onChange(of: preferences.fingers) { conflicts.refresh(fingers: preferences.fingers) }
    }

    private var permissionsSection: some View {
        Section("Permissions") {
            PermissionRow(
                title: "Accessibility",
                detail: permissions.accessibility
                    ? "Required to read swipes and switch windows."
                    : "Required to read swipes and switch windows. If AppSwipe is already on in the list, remove it with the − button and add it again.",
                isGranted: permissions.accessibility, open: Permissions.openAccessibilitySettings)
            PermissionRow(
                title: "Screen Recording",
                detail: "Optional, for window previews. Takes effect after AppSwipe restarts: quit it with ⌘Q and open it again.",
                isGranted: permissions.screenRecording,
                open: {
                    // Adds AppSwipe to the list in System Settings, where the user turns it on.
                    Permissions.requestScreenRecording()
                    Permissions.openScreenRecordingSettings()
                })
        }
    }

    /// What the swipes do, the macOS gestures that take them, and how the swipes are read.
    @ViewBuilder private var trackpadSection: some View {
        let fingers = preferences.fingers
        Section {
            GestureRow(
                symbol: "arrow.left.and.right",
                title: fingers == 3 ? "Swipe sideways with three fingers" : "Swipe sideways with four fingers",
                detail: "Steps through apps, most recently used first. A quick flick switches to the previous app.")
            GestureRow(
                symbol: "arrow.down",
                title: fingers == 3 ? "Swipe down with three fingers" : "Swipe down with four fingers",
                detail: "Steps through the windows of the app in front. While switching apps, shows the selected app’s windows; swipe up to go back.")
            if conflicts.conflicts.isEmpty {
                Label("No trackpad gestures conflict with AppSwipe.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(conflicts.conflicts, id: \.self) { conflict in
                Label(description(of: conflict), systemImage: "exclamationmark.triangle")
            }
            if canTurnOffConflicts || hasThreeFingerDrag || conflicts.canRestore {
                // The buttons go under each other when they don't fit side by side, as in Russian.
                ViewThatFits(in: .horizontal) {
                    HStack { gestureButtons }
                    VStack(alignment: .leading) { gestureButtons }
                }
            }
            Toggle("Swipe with four fingers", isOn: $preferences.fourFingers)
            Toggle("Ignore a palm on the trackpad", isOn: $preferences.ignorePalms)
            LabeledContent {
                HStack {
                    Slider(value: $preferences.stepLength, in: Preferences.stepLengths, step: 1)
                    Text("\(Int(preferences.stepLength)) mm")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } label: {
                Text("Step length")
                Text("How far the fingers travel to move the selection by one item.")
            }
            StepTrialStrip(trial: trial)
        } header: {
            Text("Trackpad")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("macOS gestures that use the same swipes take them before AppSwipe can.")
                if conflicts.canRestore {
                    Text("Turning them off changes them for the whole Mac. Restore them here before removing AppSwipe.")
                }
            }
        }
    }

    @ViewBuilder private var gestureButtons: some View {
        if canTurnOffConflicts { Button("Turn Off Conflicting Gestures", action: turnOffConflicts) }
        if hasThreeFingerDrag { Button("Open Accessibility Settings", action: Self.openPointerSettings) }
        if conflicts.canRestore {
            Button("Restore Original Gestures") { conflicts.restore(fingers: preferences.fingers) }
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle(isOn: $preferences.launchAtLogin) {
                Text("Launch at login")
                if preferences.launchAtLoginNeedsApproval {
                    Text("Allow AppSwipe under Login Items in System Settings.")
                } else if let error = preferences.launchAtLoginError {
                    Text("Couldn't change this: \(error)")
                }
            }
            if preferences.launchAtLoginNeedsApproval {
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            Toggle("Pause AppSwipe", isOn: $preferences.isPaused)
            Toggle(isOn: $preferences.showMenuBarIcon) {
                Text("Show icon in the menu bar")
                Text("When hidden, open AppSwipe again to see these settings.")
            }
        }
    }

    private var appSwitcherSection: some View {
        Section("App Switcher") {
            Picker(selection: $preferences.appDisplays) { displayOptions } label: {
                Text("Show apps from")
                Text("From one display, the App Switcher lists the app in front and the apps with a window there.")
            }
            Toggle(isOn: $preferences.hideAppsWithoutWindows) {
                Text("Hide apps without windows")
                Text("Minimized windows and windows on other Spaces count.")
            }
            Toggle(isOn: Binding(
                get: { preferences.hideAppsWithoutWindows || preferences.hideFinderWithoutWindows },
                set: { preferences.hideFinderWithoutWindows = $0 }
            )) {
                Text("Hide Finder when it has no windows")
                if preferences.hideAppsWithoutWindows {
                    Text("Already hidden along with other apps without windows.")
                }
            }
            .disabled(preferences.hideAppsWithoutWindows)
        }
    }

    private var windowSwitcherSection: some View {
        Section("Window Switcher") {
            Picker("Show windows from", selection: $preferences.windowDisplays) { displayOptions }
        }
    }

    private var switchingSection: some View {
        Section("Switching") {
            Toggle(isOn: $preferences.liveSwitching) {
                Text("Live Switching")
                Text("Switch the moment the selection moves, without waiting for the fingers to lift.")
            }
            Toggle(isOn: $preferences.enlargeSelection) {
                Text("Enlarge the selection")
                Text("Instead of a highlight around it.")
            }
        }
    }

    @ViewBuilder private var displayOptions: some View {
        Text("All displays").tag(DisplayScope.all)
        Text("Display with the pointer").tag(DisplayScope.pointer)
    }

    private var excludedAppsSection: some View {
        Section {
            ForEach(preferences.excludedApps, id: \.self) { id in
                HStack {
                    AppLabel(bundleID: id)
                    Spacer()
                    Button("Remove", role: .destructive) { preferences.excludedApps.removeAll { $0 == id } }
                        .buttonStyle(.borderless)
                }
            }
            LabeledContent {
                addAppMenu
            } label: {
                if preferences.excludedApps.isEmpty {
                    Text("No excluded apps").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Excluded Apps")
        } footer: {
            Text("Swipes do nothing while one of these apps is in front, for games and apps with their own gestures.")
        }
    }

    private var addAppMenu: some View {
        Menu("Add App") {
            let candidates = runningApps.filter { !preferences.excludedApps.contains($0.bundleID) }
            ForEach(candidates) { app in
                Button { preferences.excludedApps.append(app.bundleID) } label: {
                    Label {
                        Text(verbatim: app.name)
                    } icon: {
                        Image(nsImage: app.icon)
                    }
                }
            }
            if !candidates.isEmpty { Divider() }
            Button("Other App…", action: addExcludedApp)
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Toggle(isOn: $preferences.recordTouches) {
                Text("Record touches")
                Text("Writes every trackpad touch to a log, for bug reports. The log keeps the last 10 MB.")
            }
            LabeledContent("Logs") {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.directory])
                }
            }
        }
    }

    private var canTurnOffConflicts: Bool { conflicts.conflicts.contains { $0 != .threeFingerDrag } }
    private var hasThreeFingerDrag: Bool { conflicts.conflicts.contains(.threeFingerDrag) }

    private func refresh() {
        permissions = PermissionState()
        runningApps = RunningApp.all()
        conflicts.refresh(fingers: preferences.fingers)
    }

    private func description(of conflict: TrackpadConflicts.Conflict) -> LocalizedStringKey {
        switch conflict {
        case .appExpose(let fingers):
            fingers == 3
                ? "Swiping down with three fingers shows App Exposé."
                : "Swiping down with four fingers shows App Exposé."
        case .spacesSwipe(let fingers):
            fingers == 3
                ? "Swiping with three fingers switches between full-screen apps."
                : "Swiping with four fingers switches between full-screen apps."
        case .pageSwipe:
            "Swiping with three fingers goes back and forward between pages."
        case .threeFingerDrag:
            "Three-finger drag is on. Turn it off in Accessibility settings, or swipe with four fingers."
        }
    }

    private func turnOffConflicts() {
        if !conflicts.turnOff(fingers: preferences.fingers) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
        }
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !preferences.excludedApps.contains(id) else { continue }
            preferences.excludedApps.append(id)
        }
    }

    private static func openPointerSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Pointer")!)
    }
}

/// Which sections need action and go first.
struct Attention {
    /// Accessibility is missing.
    var permissions: Bool
    /// The first launch, which shows what the swipes do, or a macOS gesture takes the swipes.
    var trackpad: Bool
}

private struct PermissionState: Equatable {
    var accessibility = Permissions.hasAccessibility
    var screenRecording = Permissions.hasScreenRecording
}

/// A running app with a Dock icon, offered for the excluded apps.
private struct RunningApp: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage

    var id: String { bundleID }

    static func all() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .compactMap { app -> RunningApp? in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier
                else { return nil }
                // A copy at menu size, since menus draw images at their own size.
                let icon = (app.icon?.copy() as? NSImage) ?? NSImage()
                icon.size = NSSize(width: 16, height: 16)
                return RunningApp(bundleID: id, name: app.localizedName ?? id, icon: icon)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// One swipe and what it does.
private struct GestureRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let isGranted: Bool
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if isGranted {
                Label {
                    Text("Granted").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Button("Open System Settings", action: open)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        Label {
            Text(verbatim: url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        } icon: {
            if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18) }
        }
    }
}
