import AppIntents
import Foundation

// Every intent reads through OWAService, so each one needs the page signed in. A signed-out
// session throws "Outlook is signed out". Read-only intents do not open Outlook; the ones that
// show something do.

struct ComposeMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Compose Message"
    static let description = IntentDescription("Opens a new message in Outlook with the fields filled in. It is never sent.")
    static let openAppWhenRun = true

    @Parameter(title: "To", description: "Recipient addresses, separated by commas.")
    var to: String

    @Parameter(title: "Cc", description: "Copy recipients, separated by commas.")
    var cc: String?

    @Parameter(title: "Subject", default: "")
    var subject: String

    @Parameter(title: "Body", default: "", inputOptions: String.IntentInputOptions(multiline: true))
    var body: String

    func perform() async throws -> some IntentResult {
        try await OWAService.compose(to: to, cc: cc, subject: subject, body: body)
        return .result()
    }
}

struct SearchMailIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Mail"
    static let description = IntentDescription("Brings Outlook forward and searches for the query.")
    static let openAppWhenRun = true

    @Parameter(title: "Query")
    var query: String

    func perform() async throws -> some IntentResult {
        try await OWAService.search(query)
        return .result()
    }
}

struct GetUnreadCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Unread Count"
    static let description = IntentDescription("Returns the number of unread messages in a folder.")

    @Parameter(title: "Folder", description: "A folder name, or Inbox.", default: "Inbox")
    var folder: String

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: try await OWAService.unreadCount(folder: folder))
    }
}

struct GetRecentMessagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Recent Messages"
    static let description = IntentDescription("Returns the newest messages in a folder from the latest 200, metadata only.")

    @Parameter(title: "Folder", default: "Inbox")
    var folder: String

    @Parameter(title: "Unread Only", default: true)
    var unreadOnly: Bool

    @Parameter(title: "Limit", default: 10, inclusiveRange: (1, 100))
    var limit: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[MessageEntity]> {
        let records = try await OWAService.recentMessages(folder: folder, unreadOnly: unreadOnly, limit: limit)
        return .result(value: records.map(MessageEntity.init))
    }
}

struct GetNextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Next Meeting"
    static let description = IntentDescription("Returns the next meeting that starts within the given hours.")

    @Parameter(title: "Within Hours", default: 24, inclusiveRange: (1, 168))
    var withinHours: Int

    func perform() async throws -> some IntentResult & ReturnsValue<MeetingEntity> {
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(withinHours) * 3600)
        let meetings = try await OWAService.meetings(from: now, to: end, limit: 50)
        guard let next = meetings.first(where: { $0.start >= now }) else {
            throw OWAError.noMeeting(withinHours)
        }
        return .result(value: MeetingEntity(next))
    }
}

struct GetTodaysMeetingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Today's Meetings"
    static let description = IntentDescription("Returns the meetings from midnight to midnight today.")

    func perform() async throws -> some IntentResult & ReturnsValue<[MeetingEntity]> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let meetings = try await OWAService.meetings(from: start, to: end, limit: 100)
        return .result(value: meetings.map(MeetingEntity.init))
    }
}

struct OpenViewIntent: AppIntent {
    static let title: LocalizedStringResource = "Open View"
    static let description = IntentDescription("Opens Mail, Calendar or People, or a folder in Mail.")
    static let openAppWhenRun = true

    @Parameter(title: "View", default: .mail)
    var view: OutlookView

    @Parameter(title: "Folder", description: "Used only when the view is Folder.")
    var folder: String?

    func perform() async throws -> some IntentResult {
        try await OWAService.openView(view, folder: folder)
        return .result()
    }
}

struct OpenMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Message"
    static let description = IntentDescription("Opens a message in Outlook.")
    static let openAppWhenRun = true

    @Parameter(title: "Message")
    var message: MessageEntity

    func perform() async throws -> some IntentResult {
        try await OWAService.openMessage(id: message.id)
        return .result()
    }
}

struct FindMessagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Messages"
    static let description = IntentDescription("Finds messages among the newest 200 in the folder, by sender, subject, date, read state or attachments.")

    @Parameter(title: "Query", description: "Text to find in the sender name, sender email or subject.")
    var query: String?

    @Parameter(title: "From Contains")
    var from: String?

    @Parameter(title: "Subject Contains")
    var subject: String?

    @Parameter(title: "Folder", description: "A folder name, or All Mail.", default: "All Mail")
    var folder: String

    @Parameter(title: "Received After")
    var receivedAfter: Date?

    @Parameter(title: "Received Before")
    var receivedBefore: Date?

    @Parameter(title: "Unread Only", default: false)
    var unreadOnly: Bool

    @Parameter(title: "Has Attachments", default: false)
    var hasAttachments: Bool

    @Parameter(title: "Limit", default: 25, inclusiveRange: (1, 100))
    var limit: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[MessageEntity]> {
        let filter = MessageFilter(
            text: query,
            from: from,
            subject: subject,
            folder: folder,
            after: receivedAfter,
            before: receivedBefore,
            unreadOnly: unreadOnly,
            hasAttachments: hasAttachments,
            limit: limit
        )
        return .result(value: try await OWAService.findMessages(filter).map(MessageEntity.init))
    }
}

struct OutlookShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ComposeMessageIntent(),
            phrases: ["Compose a message in \(.applicationName)", "New \(.applicationName) message"],
            shortTitle: "Compose Message",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SearchMailIntent(),
            phrases: ["Search mail in \(.applicationName)"],
            shortTitle: "Search Mail",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: GetUnreadCountIntent(),
            phrases: ["Unread count in \(.applicationName)", "How many unread in \(.applicationName)"],
            shortTitle: "Unread Count",
            systemImageName: "envelope.badge"
        )
        AppShortcut(
            intent: GetRecentMessagesIntent(),
            phrases: ["Recent messages in \(.applicationName)"],
            shortTitle: "Recent Messages",
            systemImageName: "tray"
        )
        AppShortcut(
            intent: GetNextMeetingIntent(),
            phrases: ["Next meeting in \(.applicationName)"],
            shortTitle: "Next Meeting",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: GetTodaysMeetingsIntent(),
            phrases: ["Today's meetings in \(.applicationName)"],
            shortTitle: "Today's Meetings",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: OpenViewIntent(),
            phrases: ["Open \(.applicationName) view"],
            shortTitle: "Open View",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: FindMessagesIntent(),
            phrases: ["Find messages in \(.applicationName)"],
            shortTitle: "Find Messages",
            systemImageName: "magnifyingglass.circle"
        )
    }
}
