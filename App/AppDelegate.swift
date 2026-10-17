import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // No native window tabs: otherwise macOS shows an empty tab strip with "+" under the toolbar.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.windows.forEach { $0.tabbingMode = .disallowed }
        AutomationMonitor.shared.start()
        SecondaryWindows.restoreOpen()
    }

    // Clicking the Dock icon with every window closed brings the main window back. Returning true
    // would let SwiftUI open one more, so it is left to SwiftUI only when the store cannot.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }
        return !WebViewStore.shared.reopenMainWindowIfNeeded()
    }

    // Cookies are read asynchronously, so quitting waits for the save before it replies.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Set before AppKit closes the open windows, so closing them does not clear their saved state.
        SecondaryWindows.prepareToQuit()
        Task { @MainActor in
            await WebViewStore.shared.saveCookies()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
