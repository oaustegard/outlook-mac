import SwiftUI

@main
struct OutlookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands { AppCommands() }
    }
}
