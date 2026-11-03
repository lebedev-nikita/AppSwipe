import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let conflicts: TrackpadConflicts
    let trial: StepTrial
    @State private var permissions = PermissionState()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                Toggle(isOn: $preferences.showMenuBarIcon) {
                    Text("Show icon in the menu bar")
                    Text("When hidden, open OpenSwipe again to see these settings.")
                }
            }

            Section("Switchers") {
                Toggle(isOn: $preferences.appSwitcherEnabled) {
                    Text("App Switcher")
                    Text(fingersDescription(preferences.fingers(for: .apps)))
                }
                Toggle(isOn: $preferences.windowSwitcherEnabled) {
                    Text("Window Switcher")
                    Text(fingersDescription(preferences.fingers(for: .windows)))
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

            Section {
                LabeledContent("Step length") {
                    HStack {
                        Slider(value: $preferences.stepLength, in: Preferences.stepLengths, step: 1)
                        Text(verbatim: "\(Int(preferences.stepLength)) mm")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                StepTrialStrip(trial: trial)
            } header: {
                Text("Step")
            } footer: {
                Text("How far the fingers travel to move the selection by one item.")
            }

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
                Button("Add App…", action: addExcludedApp)
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("Swipes do nothing while one of these apps is in front, for games and apps with their own gestures.")
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Accessibility", detail: "Required to read swipes and switch windows.",
                    isGranted: permissions.accessibility, open: Permissions.openAccessibilitySettings)
                PermissionRow(
                    title: "Screen Recording", detail: "Optional, for window previews. Takes effect after OpenSwipe restarts.",
                    isGranted: permissions.screenRecording,
                    open: {
                        // Adds OpenSwipe to the list in System Settings, where the user turns it on.
                        Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    })
                if !permissions.screenRecording {
                    Button("Restart OpenSwipe", action: Self.restart)
                }
            }

            Section {
                if conflicts.conflicts.isEmpty {
                    Label("No trackpad gestures conflict with OpenSwipe.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(conflicts.conflicts, id: \.self) { conflict in
                    Label(description(of: conflict), systemImage: "exclamationmark.triangle")
                }
                let canTurnOff = conflicts.conflicts.contains { $0 != .threeFingerDrag }
                let hasDrag = conflicts.conflicts.contains(.threeFingerDrag)
                if canTurnOff || hasDrag || conflicts.canRestore {
                    HStack {
                        if canTurnOff { Button("Turn Off Conflicting Gestures", action: turnOffConflicts) }
                        if hasDrag { Button("Open Accessibility Settings", action: Self.openPointerSettings) }
                        if conflicts.canRestore {
                            Button("Restore Original Gestures") { conflicts.restore(fingers: switcherFingers) }
                        }
                    }
                }
            } header: {
                Text("Trackpad Gestures")
            } footer: {
                Text("macOS gestures that use the same swipes take them before OpenSwipe can.")
            }

            Section("Diagnostics") {
                Toggle(isOn: $preferences.recordTouches) {
                    Text("Record touches")
                    Text("Writes every trackpad touch to a log, for bug reports.")
                }
                Button("Show Logs in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.directory])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onChange(of: switcherFingers) { conflicts.refresh(fingers: switcherFingers) }
    }

    /// Finger counts of the enabled Switchers.
    private var switcherFingers: Set<Int> {
        var fingers: Set<Int> = []
        if preferences.appSwitcherEnabled { fingers.insert(preferences.fingers(for: .apps)) }
        if preferences.windowSwitcherEnabled { fingers.insert(preferences.fingers(for: .windows)) }
        return fingers
    }

    private func refresh() {
        permissions = PermissionState()
        conflicts.refresh(fingers: switcherFingers)
    }

    private func fingersDescription(_ fingers: Int) -> LocalizedStringKey {
        fingers == 3 ? "Swipe sideways with three fingers." : "Swipe sideways with four fingers."
    }

    private func description(of conflict: TrackpadConflicts.Conflict) -> LocalizedStringKey {
        switch conflict {
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
        if !conflicts.turnOff(fingers: switcherFingers) {
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

    private static func restart() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

private struct PermissionState {
    var accessibility = Permissions.hasAccessibility
    var screenRecording = Permissions.hasScreenRecording
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
