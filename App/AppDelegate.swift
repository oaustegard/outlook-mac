import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Cookies are read asynchronously, so quitting waits for the save before it replies.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await WebViewStore.shared.saveCookies()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
