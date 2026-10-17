import SwiftUI

@main
struct OutlookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands { AppCommands() }

        Settings {
            AutomationsSettingsView()
        }
    }
}
