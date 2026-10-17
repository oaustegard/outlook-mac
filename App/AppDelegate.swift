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
    }

    // Cookies are read asynchronously, so quitting waits for the save before it replies.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await WebViewStore.shared.saveCookies()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
