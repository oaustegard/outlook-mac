import AppKit
import OSLog
import UserNotifications

/// The Dock's unread badge and a banner for each new inbox message, both fed by AutomationMonitor's
/// poll and switched in Settings > Automations. A banner shows the sender and subject only.
@MainActor
final class MailAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MailAlerts()

    /// At most this many banners per poll, so a burst of mail does not fill the screen.
    private static let bannerLimit = 5
    private let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "alerts")

    // The newest inbox message the last poll saw. Mail already in the inbox at launch is never announced.
    private var hasBaseline = false
    private var newestSeenID: String?

    /// Takes banner clicks, and asks for permission. macOS asks once; later launches get the stored answer.
    func start() {
        UNUserNotificationCenter.current().delegate = self
        if MailAlertStore.shared.showsNotifications { requestAuthorization() }
    }

    func requestAuthorization() {
        // @Sendable, so the reply (which arrives off the main thread) is not treated as main-actor code.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { @Sendable [log] granted, error in
            if let error {
                log.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                log.notice("Notifications not allowed")
            }
        }
    }

    // MARK: Dock badge

    /// The inbox unread count on the Dock icon. None when it is zero, unknown, or switched off.
    func showUnread(_ count: Int?) {
        var label: String?
        if MailAlertStore.shared.showsDockBadge, let count, count > 0 { label = String(count) }
        NSApplication.shared.dockTile.badgeLabel = label
    }

    // MARK: Banners

    /// Posts a banner for each unread message above the one the last poll saw as newest, given the
    /// inbox newest first. The first poll after launch, or after banners are switched on, only records.
    func checkArrivals(_ recent: [MessageRecord]) {
        let previous = newestSeenID
        let isBaseline = !hasBaseline
        hasBaseline = true
        newestSeenID = recent.first?.id
        guard !isBaseline, recent.first?.id != previous else { return }

        let arrivals: ArraySlice<MessageRecord>
        if let previous {
            // The last newest message was deleted or moved, so which are new is unknown: start again from here.
            guard let index = recent.firstIndex(where: { $0.id == previous }) else { return }
            arrivals = recent[..<index]
        } else {
            arrivals = recent[...]
        }
        // Oldest first, so the newest banner ends up on top.
        for message in arrivals.filter({ !$0.isRead }).prefix(Self.bannerLimit).reversed() {
            post(message)
        }
    }

    func resetArrivals() {
        hasBaseline = false
        newestSeenID = nil
    }

    private func post(_ message: MessageRecord) {
        let content = UNMutableNotificationContent()
        content.title = message.senderName.isEmpty ? message.senderEmail : message.senderName
        content.body = message.subject.isEmpty ? "(No subject)" : message.subject
        content.sound = .default
        let request = UNNotificationRequest(identifier: message.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { @Sendable [log] error in
            if let error {
                log.error("Banner failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    // Shown while the app is in front too, as Mail does.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // Called off the main actor, so it hops there before touching windows.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { self.showMainWindow() }
    }

    /// Brings the app forward with the mail window, reopening it if it was closed.
    private func showMainWindow() {
        NSApplication.shared.activate()
        if let window = WebViewStore.shared.mailWebView?.window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            WebViewStore.shared.reopenMainWindowIfNeeded()
        }
    }
}
