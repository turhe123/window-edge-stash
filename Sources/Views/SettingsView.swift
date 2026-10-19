import SwiftUI
import ServiceManagement

/// Settings window: hotkeys, strip/timing preferences, launch at login, permission status and support link.
struct SettingsView: View {
    @ObservedObject var manager: StashManager
    @AppStorage(Prefs.stripWidth) private var stripWidth = 6.0
    @AppStorage(Prefs.revealDelay) private var revealDelay = 150.0
    @AppStorage(Prefs.animationDuration) private var animationDuration = 200.0
    @AppStorage(Prefs.hideOnFocusLoss) private var hideOnFocusLoss = true
    @AppStorage(Prefs.stashKeyCode) private var stashKeyCode = 1
    @AppStorage(Prefs.stashModifiers) private var stashModifiers = Prefs.defaultModifiers
    @AppStorage(Prefs.stashLabel) private var stashLabel = "⌃⌥S"
    @AppStorage(Prefs.unstashKeyCode) private var unstashKeyCode = 32
    @AppStorage(Prefs.unstashModifiers) private var unstashModifiers = Prefs.defaultModifiers
    @AppStorage(Prefs.unstashLabel) private var unstashLabel = "⌃⌥U"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Hotkeys") {
                HotKeyRecorder(title: "Stash focused window", keyCode: $stashKeyCode,
                               modifiers: $stashModifiers, label: $stashLabel)
                HotKeyRecorder(title: "Unstash window", keyCode: $unstashKeyCode,
                               modifiers: $unstashModifiers, label: $unstashLabel)
            }
            Section("Behavior") {
                LabeledContent("Strip width: \(Int(stripWidth)) pt") {
                    Slider(value: $stripWidth, in: 2...20, step: 1)
                }
                LabeledContent("Reveal delay: \(Int(revealDelay)) ms") {
                    Slider(value: $revealDelay, in: 0...1000, step: 25)
                }
                LabeledContent("Animation: \(Int(animationDuration)) ms") {
                    Slider(value: $animationDuration, in: 0...600, step: 25)
                }
                Toggle("Hide revealed window when focus moves elsewhere", isOn: $hideOnFocusLoss)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Accessibility") {
                    if manager.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { manager.requestAccess() }
                    }
                }
                if !manager.isTrusted {
                    Text("Enable WindowEdgeStash in System Settings › Privacy & Security › Accessibility so it can move windows.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Text("WindowEdgeStash is free and open source.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Support / Donate ❤️") { Support.openDonation() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { manager.refreshTrust() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// A button that records a new global shortcut (requires ⌘, ⌃ or ⌥; Esc cancels) and re-registers hotkeys.
struct HotKeyRecorder: View {
    let title: String
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var label: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            Button(recording ? "Press shortcut…" : label) { recording ? stop() : start() }
                .frame(minWidth: 110)
        }
    }

    private func start() {
        HotKeyCenter.shared.unregisterAll()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            let mods = HotKeyCenter.carbonModifiers(event.modifierFlags)
            let required = HotKeyCenter.carbonModifiers([.command, .control, .option])
            guard mods & required != 0 else { NSSound.beep(); return nil }
            keyCode = Int(event.keyCode)
            modifiers = mods
            label = HotKeyCenter.label(for: event)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        StashManager.shared.registerHotKeys()
    }
}
