import Foundation
import OSLog

/// Watches Outlook for the four events Settings > Automations lists, and runs the chosen shortcut
/// when one happens. Polls once a minute while the app runs, through the same service calls the
/// intents use. Only metadata is read, and only event inputs are logged.
@MainActor
final class AutomationMonitor {
    static let shared = AutomationMonitor()

    private static let interval: TimeInterval = 60
    private static let settleTime: Duration = .seconds(30)
    private let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "automation")
    private var timer: Timer?
    private var unreadSettling: Task<Void, Never>?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    /// One pass over the events. Skipped until the page has loaded, so a launch is not read as signed out.
    func poll() async {
        guard let webView = WebViewStore.shared.dispatcher.webView, !webView.isLoading, let url = webView.url else {
            return
        }
        guard let server = ServerConfig.serverURL, OWAService.isSameOrigin(url, server) else {
            // Off the Exchange server, such as a Duo or ADFS sign-in page: the session has lapsed.
            reportSignedOut()
            return
        }

        let settings = AutomationStore.shared.settings
        do {
            try await checkUnread(settings.unreadChanged)
            if settings.newMail.enabled {
                try await checkNewMail(settings)
            } else {
                AutomationState.seenMessageIDs = nil
            }
            if settings.meeting.enabled {
                try await checkMeetings(settings)
            }
        } catch OWAError.signedOut {
            reportSignedOut()
        } catch {
            log.error("Poll failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Events

    /// Unread Count Changed. A change is read again 30 seconds later, and fires only if it still holds.
    private func checkUnread(_ rule: AutomationSettings.Event) async throws {
        let count = try await OWAService.unreadCount(folder: "Inbox")
        AutomationState.signedOutReported = false
        guard rule.enabled else {
            AutomationState.lastUnreadCount = nil
            return
        }
        guard let baseline = AutomationState.lastUnreadCount else {
            // First poll after enabling: the current count is the baseline, so nothing fires.
            AutomationState.lastUnreadCount = count
            return
        }
        guard count != baseline, unreadSettling == nil else { return }

        unreadSettling = Task { @MainActor [self] in
            defer { self.unreadSettling = nil }
            try? await Task.sleep(for: Self.settleTime)
            let previous = AutomationState.lastUnreadCount ?? baseline
            guard let settled = try? await OWAService.unreadCount(folder: "Inbox"), settled != previous else {
                return
            }
            AutomationState.lastUnreadCount = settled
            fire(AutomationStore.shared.settings.unreadChanged, "unreadChanged", input: [
                "old": previous,
                "new": settled,
            ])
        }
    }

    /// New Mail. The first poll after enabling only records the inbox, so existing mail never fires.
    private func checkNewMail(_ settings: AutomationSettings) async throws {
        let recent = try await OWAService.recentMessages(folder: "Inbox", unreadOnly: false, limit: 50)
        let ids = recent.map(\.id)
        guard let seen = AutomationState.seenMessageIDs else {
            AutomationState.seenMessageIDs = ids
            return
        }

        let known = Set(seen)
        let arrivals = recent.filter { !known.contains($0.id) }.reversed()

        // Keep older ids too, so a message that drops off the newest 50 is not counted again later.
        var merged = ids
        var mergedSet = Set(ids)
        for id in seen where mergedSet.insert(id).inserted {
            merged.append(id)
        }
        AutomationState.seenMessageIDs = Array(merged.prefix(500))

        for message in arrivals where matches(message, settings) {
            fire(settings.newMail, "newMail", input: [
                "sender": message.senderName,
                "senderEmail": message.senderEmail,
                "subject": message.subject,
                "received": message.received.map(ISO8601DateFormatter.withFraction.string(from:)) ?? "",
                "isImportant": message.isImportant,
                "id": message.id,
            ])
        }
    }

    private func matches(_ message: MessageRecord, _ settings: AutomationSettings) -> Bool {
        if settings.newMailImportantOnly && !message.isImportant { return false }
        let sender = settings.newMailFromContains.trimmingCharacters(in: .whitespaces)
        if !sender.isEmpty,
           !message.senderName.localizedCaseInsensitiveContains(sender),
           !message.senderEmail.localizedCaseInsensitiveContains(sender) {
            return false
        }
        let subject = settings.newMailSubjectContains.trimmingCharacters(in: .whitespaces)
        if !subject.isEmpty, !message.subject.localizedCaseInsensitiveContains(subject) {
            return false
        }
        return true
    }

    /// Meeting Starting Soon. Each meeting fires once, even across relaunches.
    private func checkMeetings(_ settings: AutomationSettings) async throws {
        let lead = TimeInterval(max(1, settings.meetingMinutesBefore) * 60)
        let now = Date()
        let meetings = try await OWAService.meetings(from: now, to: now.addingTimeInterval(lead + 60), limit: 20)

        var notified = AutomationState.notifiedMeetingIDs
        for meeting in meetings
        where meeting.start > now && meeting.start.timeIntervalSince(now) <= lead && !notified.contains(meeting.id) {
            notified.append(meeting.id)
            fire(settings.meeting, "meetingStarting", input: [
                "id": meeting.id,
                "title": meeting.title,
                "start": ISO8601DateFormatter.withFraction.string(from: meeting.start),
                "end": ISO8601DateFormatter.withFraction.string(from: meeting.end),
                "location": meeting.location,
                "organizer": meeting.organizer,
                "isOrganizer": meeting.isOrganizer,
                "joinURL": meeting.joinURL ?? "",
            ])
        }
        AutomationState.notifiedMeetingIDs = Array(notified.suffix(200))
    }

    /// Signed Out fires once per lapse. It re-arms when a poll finds the session signed in again.
    private func reportSignedOut() {
        guard !AutomationState.signedOutReported else { return }
        AutomationState.signedOutReported = true
        fire(AutomationStore.shared.settings.signedOut, "signedOut", input: [
            "reason": "Outlook needs to sign in again.",
        ])
    }

    private func fire(_ rule: AutomationSettings.Event, _ event: String, input: [String: Any]) {
        guard rule.enabled, !rule.shortcut.isEmpty else { return }
        log.info("Event fired: \(event, privacy: .public)")
        ShortcutRunner.run(rule.shortcut, input: input)
    }
}
