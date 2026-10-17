import SwiftUI

@main
struct OutlookApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands { AppCommands() }
    }
}
