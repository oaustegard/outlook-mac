import SwiftUI

/// The default and minimum size of every app window: about 70% of a 13-inch M1 MacBook Air's
/// 1440 by 900 display, the smallest that the web apps are useful at.
enum WindowSize {
    static let width: CGFloat = 1008
    static let height: CGFloat = 630
}

@main
struct OutlookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(width: WindowSize.width, height: WindowSize.height)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands { AppCommands() }
    }
}
