import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // No native window tabs: otherwise macOS shows an empty tab strip with "+" under the toolbar.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.windows.forEach { $0.tabbingMode = .disallowed }
        SecondaryWindows.restoreOpen()
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
