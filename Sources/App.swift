import SwiftUI
import AppKit

/// App entry point: a menu-bar-only app with a MenuBarExtra menu and a Settings window.
@main
struct WindowEdgeStashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var manager = StashManager.shared

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra("WindowEdgeStash", systemImage: "sidebar.right") {
            MenuContent(manager: manager)
        }
        Settings {
            SettingsView(manager: manager)
        }
    }
}

/// Starts the stash service at launch and restores every stashed window before the app quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StashManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        StashManager.shared.unstashAll(animated: false)
    }
}

/// Opens the project's donation page.
enum Support {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
