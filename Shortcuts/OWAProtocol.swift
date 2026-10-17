import Foundation

/// A mail or calendar folder: either a distinguished name such as "inbox", or a server id.
struct FolderRef: Sendable {
    let id: String
    let distinguished: Bool

    var json: [String: Any] {
        ["__type": distinguished ? "DistinguishedFolderId:#Exchange" : "FolderId:#Exchange", "Id": id]
    }
}

/// Which messages a search returns. Every field is optional; empty fields are left out.
struct MessageFilter: Sendable {
    var text: String?
    var from: String?
    var subject: String?
    var folder: String = "All Mail"
    var after: Date?
    var before: Date?
    var unreadOnly = false
    var hasAttachments = false
    var limit = 25

    /// Whether a message passes every condition. The server rejects restriction bodies and its AQS
    /// keywords match nothing, so filtering runs here on the metadata OWA returns: sender, subject,
    /// date, read state and attachments. Text search therefore covers sender and subject only.
    func matches(_ message: MessageRecord) -> Bool {
        if let text, !text.isEmpty,
           !message.subject.localizedCaseInsensitiveContains(text),
           !message.senderName.localizedCaseInsensitiveContains(text),
           !message.senderEmail.localizedCaseInsensitiveContains(text) {
            return false
        }
        if let from, !from.isEmpty,
           !message.senderName.localizedCaseInsensitiveContains(from),
           !message.senderEmail.localizedCaseInsensitiveContains(from) {
            return false
        }
        if let subject, !subject.isEmpty, !message.subject.localizedCaseInsensitiveContains(subject) {
            return false
        }
        if let after, !(message.received.map { $0 >= after } ?? false) { return false }
        if let before, !(message.received.map { $0 <= before } ?? false) { return false }
        if unreadOnly && message.isRead { return false }
        if hasAttachments && !message.hasAttachments { return false }
        return true
    }
}

/// Request bodies for OWA's service.svc. Only metadata is requested, never a body.
/// Shapes checked against the live server: IndexedPageView paging, SortResults ordering, and
/// GetCalendarView for the calendar. FindItem rejects Deep traversal and restriction bodies.
enum OWARequest {
    static let messageProperties = ["Subject", "DateTimeReceived", "From", "IsRead", "Importance", "HasAttachments"]
    static let meetingProperties = ["Subject", "Start", "End", "Location", "Organizer", "IsOrganizer"]

    /// Folders that make up "All Mail" for FindItem, which cannot traverse the whole mailbox at once.
    static let allMailFolders = ["inbox", "sentitems", "drafts", "deleteditems"]

    static let distinguishedFolders: [String: FolderRef] = [
        "inbox": FolderRef(id: "inbox", distinguished: true),
        "drafts": FolderRef(id: "drafts", distinguished: true),
        "sent items": FolderRef(id: "sentitems", distinguished: true),
        "sent": FolderRef(id: "sentitems", distinguished: true),
        "deleted items": FolderRef(id: "deleteditems", distinguished: true),
        "deleted": FolderRef(id: "deleteditems", distinguished: true),
        "junk email": FolderRef(id: "junkemail", distinguished: true),
        "junk": FolderRef(id: "junkemail", distinguished: true),
        "outbox": FolderRef(id: "outbox", distinguished: true),
    ]

    static func property(_ fieldURI: String) -> [String: Any] {
        ["__type": "PropertyUri:#Exchange", "FieldURI": fieldURI]
    }

    static func distinguished(_ id: String) -> [String: Any] {
        ["__type": "DistinguishedFolderId:#Exchange", "Id": id]
    }

    static func shape(_ properties: [String]) -> [String: Any] {
        [
            "__type": "ItemResponseShape:#Exchange",
            "BaseShape": "IdOnly",
            "AdditionalProperties": properties.map(property),
        ]
    }

    static func paging(_ limit: Int) -> [String: Any] {
        ["__type": "IndexedPageView:#Exchange", "BasePoint": "Beginning", "Offset": 0, "MaxEntriesReturned": limit]
    }

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter.withFraction.string(from: date)
    }

    // MARK: Folders

    static func getFolder(_ folder: FolderRef) -> [String: Any] {
        [
            "__type": "GetFolderRequest:#Exchange",
            "FolderShape": [
                "__type": "FolderResponseShape:#Exchange",
                "BaseShape": "IdOnly",
                "AdditionalProperties": [property("FolderDisplayName"), property("UnreadCount")],
            ],
            "FolderIds": [folder.json],
        ]
    }

    /// Every folder under the mailbox root, so a folder can be found by its display name.
    /// OWA calls the folder's name FolderDisplayName; it silently ignores a plain DisplayName.
    static func findFolders() -> [String: Any] {
        [
            "__type": "FindFolderRequest:#Exchange",
            "FolderShape": [
                "__type": "FolderResponseShape:#Exchange",
                "BaseShape": "IdOnly",
                "AdditionalProperties": [property("FolderDisplayName"), property("UnreadCount"), property("ParentFolderId")],
            ],
            "ParentFolderIds": [distinguished("msgfolderroot")],
            "Traversal": "Deep",
            "Paging": paging(1000),
        ]
    }

    // MARK: Messages

    /// The newest messages in the given folders, with metadata only. Filtering happens afterwards.
    static func messageSearch(parents: [[String: Any]], limit: Int) -> [String: Any] {
        [
            "__type": "FindItemRequest:#Exchange",
            "ItemShape": shape(messageProperties),
            "ParentFolderIds": parents,
            "Traversal": "Shallow",
            "Paging": paging(limit),
            "SortOrder": [[
                "__type": "SortResults:#Exchange",
                "Order": "Descending",
                "Path": property("DateTimeReceived"),
            ]],
        ]
    }

    static func getItems(ids: [String], properties: [String]) -> [String: Any] {
        [
            "__type": "GetItemRequest:#Exchange",
            "ItemShape": shape(properties),
            "ItemIds": ids.map { ["__type": "ItemId:#Exchange", "Id": $0] },
        ]
    }

    // MARK: Calendar

    /// Calendar items that overlap the range. Recurring meetings come back as occurrences.
    static func getCalendarView(from start: Date, to end: Date) -> [String: Any] {
        [
            "__type": "GetCalendarViewRequest:#Exchange",
            "CalendarId": [
                "__type": "TargetFolderId:#Exchange",
                "BaseFolderId": distinguished("calendar"),
            ],
            "RangeStart": iso(start),
            "RangeEnd": iso(end),
        ]
    }
}

// MARK: - Replies

/// A message's metadata. Never holds the body.
struct MessageRecord: Sendable {
    let id: String
    let senderName: String
    let senderEmail: String
    let subject: String
    let received: Date?
    let isRead: Bool
    let isImportant: Bool
    let hasAttachments: Bool
}

/// A calendar item's metadata. Never holds the body.
struct MeetingRecord: Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String
    let organizer: String
    let isOrganizer: Bool
    let joinURL: String?
}

struct FolderRecord: Sendable {
    let id: String
    let name: String
    let unreadCount: Int
    var parentID: String? = nil
}

extension Array where Element == FolderRecord {
    /// The folder a name refers to. "Inbox/PRs" names a folder by its path; a bare name that
    /// several folders share (such as an Inbox inside Archive) means the one nearest the top.
    func named(_ name: String) -> FolderRecord? {
        let byID = Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func ancestors(_ folder: FolderRecord) -> [String] {
            var names: [String] = []
            var parent = folder.parentID.flatMap { byID[$0] }
            while let current = parent, names.count < 50 {
                names.insert(current.name, at: 0)
                parent = current.parentID.flatMap { byID[$0] }
            }
            return names
        }
        let path = name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let leaf = path.last else { return nil }
        let same = { (a: String, b: String) in a.caseInsensitiveCompare(b) == .orderedSame }
        return filter { same($0.name, leaf) }
            .map { (folder: $0, ancestors: ancestors($0)) }
            .filter { candidate in
                // Each named parent must be one of the folder's ancestors, nearest last.
                let parents = path.dropLast()
                return parents.count <= candidate.ancestors.count
                    && zip(parents.reversed(), candidate.ancestors.reversed()).allSatisfy(same)
            }
            .min { $0.ancestors.count < $1.ancestors.count }?
            .folder
    }
}

enum OWAParse {
    /// The list under `key` ("Items" or "Folders"), from a plain reply or from the first response
    /// messages. Throws when the server reports an error for it.
    static func collection(_ reply: [String: Any], key: String) throws -> [[String: Any]] {
        for container in containers(reply) {
            if container["ResponseClass"] as? String == "Error" {
                throw OWAError.server(container["MessageText"] as? String ?? "unknown error")
            }
            if let root = container["RootFolder"] as? [String: Any], let items = root[key] as? [[String: Any]] {
                return items
            }
            if let items = container[key] as? [[String: Any]] {
                return items
            }
        }
        return []
    }

    private static func containers(_ reply: [String: Any]) -> [[String: Any]] {
        var result = [reply]
        if let messages = reply["ResponseMessages"] as? [String: Any],
           let items = messages["Items"] as? [[String: Any]] {
            result += items
        }
        return result
    }

    static func unreadCount(_ reply: [String: Any]) throws -> Int {
        guard let folder = try collection(reply, key: "Folders").first,
              let count = folder["UnreadCount"] as? Int
        else { throw OWAError.badReply }
        return count
    }

    static func folders(_ reply: [String: Any]) throws -> [FolderRecord] {
        try collection(reply, key: "Folders").compactMap { folder in
            guard let id = (folder["FolderId"] as? [String: Any])?["Id"] as? String else { return nil }
            return FolderRecord(
                id: id,
                name: folder["DisplayName"] as? String ?? "",
                unreadCount: folder["UnreadCount"] as? Int ?? 0,
                parentID: (folder["ParentFolderId"] as? [String: Any])?["Id"] as? String
            )
        }
    }

    static func messages(_ reply: [String: Any]) throws -> [MessageRecord] {
        try collection(reply, key: "Items").compactMap(message)
    }

    static func meetings(_ reply: [String: Any]) throws -> [MeetingRecord] {
        try collection(reply, key: "Items").compactMap(meeting)
    }

    static func message(_ item: [String: Any]) -> MessageRecord? {
        guard let id = itemID(item) else { return nil }
        let from = mailbox(item["From"])
        return MessageRecord(
            id: id,
            senderName: from.name,
            senderEmail: from.email,
            subject: item["Subject"] as? String ?? "",
            received: date(item["DateTimeReceived"]),
            isRead: item["IsRead"] as? Bool ?? true,
            isImportant: item["Importance"] as? String == "High",
            hasAttachments: item["HasAttachments"] as? Bool ?? false
        )
    }

    static func meeting(_ item: [String: Any]) -> MeetingRecord? {
        guard let id = itemID(item),
              let start = date(item["Start"]),
              let end = date(item["End"])
        else { return nil }
        // Only a link printed in the location is used. The meeting body is never requested.
        let location = locationText(item["Location"])
        return MeetingRecord(
            id: id,
            title: item["Subject"] as? String ?? "",
            start: start,
            end: end,
            location: location,
            organizer: mailbox(item["Organizer"]).name,
            isOrganizer: item["IsOrganizer"] as? Bool ?? false,
            joinURL: location.range(of: #"https://\S+"#, options: .regularExpression).map { String(location[$0]) }
        )
    }

    private static func itemID(_ item: [String: Any]) -> String? {
        (item["ItemId"] as? [String: Any])?["Id"] as? String
    }

    private static func mailbox(_ value: Any?) -> (name: String, email: String) {
        guard let dictionary = value as? [String: Any] else { return ("", "") }
        let box = dictionary["Mailbox"] as? [String: Any] ?? dictionary
        return (box["Name"] as? String ?? "", box["EmailAddress"] as? String ?? "")
    }

    private static func locationText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        return (value as? [String: Any])?["DisplayName"] as? String ?? ""
    }

    /// OWA sends ISO 8601 times, sometimes with more fraction digits than milliseconds.
    static func date(_ value: Any?) -> Date? {
        guard var text = value as? String else { return nil }
        text = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        if let date = ISO8601DateFormatter.withFraction.date(from: text) { return date }
        return ISO8601DateFormatter.plain.date(from: text)
    }
}

extension ISO8601DateFormatter {
    /// UTC with milliseconds, as OWA writes and reads them.
    static var withFraction: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static var plain: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

enum OWAError: LocalizedError {
    case notRunning
    case signedOut
    case notConfigured
    case badReply
    case composeNotFilled(String)
    case noSearchBox
    case noSuchFolder(String)
    case noMeeting(Int)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            "Outlook is not open. Open Outlook and sign in, then run the shortcut again."
        case .signedOut:
            "Outlook is signed out"
        case .notConfigured:
            "No Exchange server is set up in Outlook."
        case .badReply:
            "Outlook returned a reply that could not be read."
        case .composeNotFilled(let labels):
            "Opened a blank message, but Outlook's compose fields were not found, so nothing was filled in. Controls on the page: \(labels)"
        case .noSearchBox:
            "Outlook's search box was not found, so nothing was searched."
        case .noSuchFolder(let name):
            "There is no folder named \(name)."
        case .noMeeting(let hours):
            "No meeting in the next \(hours) hours."
        case .server(let text):
            "Outlook reported an error: \(text)"
        }
    }
}
