import SwiftUI

@main
struct OutlookApp: App {
    var body: some Scene {
        WindowGroup {
            OutlookWebView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands { AppCommands() }
    }
}
