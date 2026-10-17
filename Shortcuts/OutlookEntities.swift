import AppIntents
import Foundation

/// A message as Shortcuts sees it: metadata only. Opening it in Outlook goes through the item id.
struct MessageEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Message")
    static let defaultQuery = MessageQuery()

    let id: String

    @Property(title: "Sender Name")
    var senderName: String

    @Property(title: "Sender Email")
    var senderEmail: String

    @Property(title: "Subject")
    var subject: String

    @Property(title: "Received")
    var received: Date?

    @Property(title: "Is Important")
    var isImportant: Bool

    @Property(title: "Has Attachments")
    var hasAttachments: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(subject)", subtitle: "\(senderName)")
    }

    init(_ record: MessageRecord) {
        id = record.id
        senderName = record.senderName
        senderEmail = record.senderEmail
        subject = record.subject
        received = record.received
        isImportant = record.isImportant
        hasAttachments = record.hasAttachments
    }
}

struct MessageQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MessageEntity] {
        try await OWAService.messages(ids: identifiers).map(MessageEntity.init)
    }

    /// Find Messages with the typed text, so Shortcuts' own search finds the same mail as the action.
    func entities(matching string: String) async throws -> [MessageEntity] {
        var filter = MessageFilter()
        filter.text = string
        filter.limit = 25
        return try await OWAService.findMessages(filter).map(MessageEntity.init)
    }

    func suggestedEntities() async throws -> [MessageEntity] {
        try await OWAService.recentMessages(folder: "Inbox", unreadOnly: false, limit: 10).map(MessageEntity.init)
    }
}

/// A calendar item as Shortcuts sees it: metadata only.
struct MeetingEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meeting")
    static let defaultQuery = MeetingQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Start")
    var start: Date

    @Property(title: "End")
    var end: Date

    @Property(title: "Location")
    var location: String

    @Property(title: "Organizer")
    var organizer: String

    @Property(title: "Online Join URL")
    var joinURL: String?

    @Property(title: "Is Organizer")
    var isOrganizer: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(start.formatted(date: .abbreviated, time: .shortened))")
    }

    init(_ record: MeetingRecord) {
        id = record.id
        title = record.title
        start = record.start
        end = record.end
        location = record.location
        organizer = record.organizer
        joinURL = record.joinURL
        isOrganizer = record.isOrganizer
    }
}

struct MeetingQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MeetingEntity] {
        try await OWAService.meetings(ids: identifiers).map(MeetingEntity.init)
    }

    func suggestedEntities() async throws -> [MeetingEntity] {
        let now = Date()
        return try await OWAService.meetings(from: now, to: now.addingTimeInterval(24 * 3600), limit: 10)
            .map(MeetingEntity.init)
    }
}

/// The Outlook areas Open View can show.
enum OutlookView: String, AppEnum {
    case mail
    case calendar
    case people
    case folder

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Outlook View")

    static let caseDisplayRepresentations: [OutlookView: DisplayRepresentation] = [
        .mail: "Mail",
        .calendar: "Calendar",
        .people: "People",
        .folder: "Folder",
    ]
}
