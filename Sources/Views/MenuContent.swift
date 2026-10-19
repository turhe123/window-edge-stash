import SwiftUI

/// The MenuBarExtra menu: permission row, stashed window list with Unstash actions, and app commands.
struct MenuContent: View {
    @ObservedObject var manager: StashManager
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.stashLabel) private var stashLabel = "⌃⌥S"
    @AppStorage(Prefs.unstashLabel) private var unstashLabel = "⌃⌥U"

    var body: some View {
        if !manager.isTrusted {
            Button("⚠️ Grant Accessibility…") { manager.requestAccess() }
            Text("Required to move other apps' windows")
            Divider()
        }

        if manager.items.isEmpty {
            Text("No stashed windows")
            Text("Press \(stashLabel) to stash the focused window")
        } else {
            Section("Stashed Windows") {
                ForEach(manager.items) { item in
                    Menu("\(item.appName) — \(item.title)") {
                        Button("Unstash") { manager.unstash(item) }
                    }
                }
            }
            Button("Unstash All") { manager.unstashAll() }
            Text("\(unstashLabel) unstashes the focused or last window")
        }

        Divider()
        Button("Stash Focused Window") { manager.stashFocused() }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Support / Donate ❤️") { Support.openDonation() }
        Divider()
        Button("Quit WindowEdgeStash") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
