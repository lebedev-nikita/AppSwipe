import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let conflicts: TrackpadConflicts
    let trial: StepTrial
    @State private var permissions = PermissionState()
    @State private var runningApps = RunningApp.all()

    var body: some View {
        // What AppSwipe needs to work comes first, so the first launch shows it without scrolling.
        Form {
            permissionsSection
            gesturesSection
            generalSection
            switchersSection
            stepSection
            excludedAppsSection
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
        .onChange(of: swipes) { conflicts.refresh(swipes) }
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

    private var gesturesSection: some View {
        Section {
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
        } header: {
            Text("Trackpad Gestures")
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
            Button("Restore Original Gestures") { conflicts.restore(swipes) }
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
            Toggle(isOn: $preferences.isPaused) {
                Text("Pause AppSwipe")
                Text("Swipes do nothing until AppSwipe is resumed.")
            }
            Toggle(isOn: $preferences.showMenuBarIcon) {
                Text("Show icon in the menu bar")
                Text("When hidden, open AppSwipe again to see these settings, and press ⌘Q here to quit it.")
            }
        }
    }

    private var switchersSection: some View {
        Section("Switchers") {
            Toggle(isOn: $preferences.appSwitcherEnabled) {
                Text("App Switcher")
                Text(fingersDescription(preferences.fingers(for: .apps)))
            }
            Picker(selection: $preferences.appDisplays) { displayOptions } label: {
                Text("Show apps from")
                Text("From one display, the App Switcher lists the app in front and the apps with a window there.")
            }
            .disabled(!preferences.appSwitcherEnabled)
            Toggle(isOn: $preferences.swipeDownForWindows) {
                Text("Swipe down for windows")
                Text(swipeDownDescription(preferences.fingers(for: .apps)))
            }
            .disabled(!preferences.appSwitcherEnabled)
            Toggle(isOn: $preferences.windowSwitcherEnabled) {
                Text("Window Switcher")
                Text(fingersDescription(preferences.fingers(for: .windows)))
            }
            Picker("Show windows from", selection: $preferences.windowDisplays) { displayOptions }
                .disabled(!preferences.windowSwitcherEnabled)
            if !preferences.appSwitcherEnabled && !preferences.windowSwitcherEnabled {
                Label("Both Switchers are off, so swipes do nothing.", systemImage: "exclamationmark.triangle")
            }
            Toggle(isOn: $preferences.swapFingerCounts) {
                Text("Swap finger counts")
                Text("Four fingers for apps, three for windows.")
            }
            Toggle(isOn: $preferences.liveSwitching) {
                Text("Live Switching")
                Text("Switch the moment the selection moves, without waiting for the fingers to lift.")
            }
            Toggle("Hide Finder when it has no windows", isOn: $preferences.hideFinderWithoutWindows)
        }
    }

    @ViewBuilder private var displayOptions: some View {
        Text("All displays").tag(DisplayScope.all)
        Text("Display with the pointer").tag(DisplayScope.pointer)
    }

    private var stepSection: some View {
        Section {
            LabeledContent("Step length") {
                HStack {
                    Slider(value: $preferences.stepLength, in: Preferences.stepLengths, step: 1)
                    Text("\(Int(preferences.stepLength)) mm")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            if !conflicts.conflicts.isEmpty {
                Label(
                    "Turn off the conflicting trackpad gestures above first, or macOS takes the swipe.",
                    systemImage: "exclamationmark.triangle")
            }
            StepTrialStrip(trial: trial)
        } header: {
            Text("Step")
        } footer: {
            Text("How far the fingers travel to move the selection by one item.")
        }
    }

    private var excludedAppsSection: some View {
        Section {
            if preferences.excludedApps.isEmpty {
                Text("No excluded apps").foregroundStyle(.secondary)
            }
            ForEach(preferences.excludedApps, id: \.self) { id in
                HStack {
                    AppLabel(bundleID: id)
                    Spacer()
                    Button("Remove", role: .destructive) { preferences.excludedApps.removeAll { $0 == id } }
                        .buttonStyle(.borderless)
                }
            }
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
            .fixedSize()
        } header: {
            Text("Excluded Apps")
        } footer: {
            Text("Swipes do nothing while one of these apps is in front, for games and apps with their own gestures.")
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Toggle(isOn: $preferences.recordTouches) {
                Text("Record touches")
                Text("Writes every trackpad touch to a log, for bug reports. The log keeps the last 10 MB.")
            }
            Button("Show Logs in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.directory])
            }
        }
    }

    /// The swipes of the enabled Switchers.
    private var swipes: TrackpadConflicts.Swipes {
        var swipes = TrackpadConflicts.Swipes()
        if preferences.appSwitcherEnabled {
            swipes.sideways.insert(preferences.fingers(for: .apps))
            if preferences.swipeDownForWindows { swipes.down = preferences.fingers(for: .apps) }
        }
        if preferences.windowSwitcherEnabled { swipes.sideways.insert(preferences.fingers(for: .windows)) }
        return swipes
    }

    private var canTurnOffConflicts: Bool { conflicts.conflicts.contains { $0 != .threeFingerDrag } }
    private var hasThreeFingerDrag: Bool { conflicts.conflicts.contains(.threeFingerDrag) }

    private func refresh() {
        permissions = PermissionState()
        runningApps = RunningApp.all()
        conflicts.refresh(swipes)
    }

    private func fingersDescription(_ fingers: Int) -> LocalizedStringKey {
        fingers == 3 ? "Swipe sideways with three fingers." : "Swipe sideways with four fingers."
    }

    private func swipeDownDescription(_ fingers: Int) -> LocalizedStringKey {
        fingers == 3
            ? "Swiping down with three fingers shows the windows of the app in front, instead of App Exposé."
            : "Swiping down with four fingers shows the windows of the app in front, instead of App Exposé."
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
            "Three-finger drag is on. Turn it off in Accessibility settings, or swap finger counts and turn off the three-finger Switcher."
        }
    }

    private func turnOffConflicts() {
        if !conflicts.turnOff(swipes) {
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

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let isGranted: Bool
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
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
