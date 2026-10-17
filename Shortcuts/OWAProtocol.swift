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
}

/// Request bodies for OWA's service.svc. Only metadata is requested: no body, no preview text.
enum OWARequest {
    static let messageProperties = ["Subject", "DateTimeReceived", "From", "IsRead", "Importance", "HasAttachments"]
    static let meetingProperties = ["Subject", "Start", "End", "Location", "Organizer", "IsOrganizer"]

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
        ["__type": "IndexedPageItemView:#Exchange", "BasePoint": "Beginning", "Offset": 0, "MaxEntriesReturned": limit]
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
                "AdditionalProperties": [property("DisplayName"), property("UnreadCount")],
            ],
            "FolderIds": [folder.json],
        ]
    }

    /// Every folder under the mailbox root, so a folder can be found by its display name.
    static func findFolders() -> [String: Any] {
        [
            "__type": "FindFolderRequest:#Exchange",
            "FolderShape": [
                "__type": "FolderResponseShape:#Exchange",
                "BaseShape": "IdOnly",
                "AdditionalProperties": [property("DisplayName"), property("UnreadCount")],
            ],
            "ParentFolderIds": [distinguished("msgfolderroot")],
            "Traversal": "Deep",
            "Paging": [
                "__type": "IndexedPageFolderView:#Exchange",
                "BasePoint": "Beginning",
                "Offset": 0,
                "MaxEntriesReturned": 1000,
            ],
        ]
    }

    // MARK: Messages

    /// A FindItem over message folders, newest first. Conditions are ANDed; `query` is AQS text.
    static func findMessages(_ filter: MessageFilter, parents: [[String: Any]], deep: Bool) -> [String: Any] {
        var conditions: [[String: Any]] = []
        if let subject = filter.subject, !subject.isEmpty {
            conditions.append(contains("Subject", subject))
        }
        if let after = filter.after {
            conditions.append(compare("IsGreaterThanOrEqualToType", "DateTimeReceived", iso(after)))
        }
        if let before = filter.before {
            conditions.append(compare("IsLessThanOrEqualToType", "DateTimeReceived", iso(before)))
        }
        if filter.unreadOnly {
            conditions.append(equal("IsRead", "false"))
        }
        if filter.hasAttachments {
            conditions.append(equal("HasAttachments", "true"))
        }

        var terms: [String] = []
        if let text = filter.text, !text.isEmpty { terms.append("\"\(unquoted(text))\"") }
        if let from = filter.from, !from.isEmpty { terms.append("from:\"\(unquoted(from))\"") }

        var body = messageSearch(parents: parents, deep: deep, limit: filter.limit)
        if let restriction = restriction(conditions) { body["Restriction"] = restriction }
        if !terms.isEmpty {
            body["QueryString"] = ["__type": "QueryStringType:#Exchange", "Value": terms.joined(separator: " ")]
        }
        return body
    }

    static func messageSearch(parents: [[String: Any]], deep: Bool, limit: Int) -> [String: Any] {
        [
            "__type": "FindItemRequest:#Exchange",
            "ItemShape": shape(messageProperties),
            "ParentFolderIds": parents,
            "Traversal": deep ? "Deep" : "Shallow",
            "Paging": paging(limit),
            "SortOrder": [[
                "__type": "FieldOrder:#Exchange",
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

    /// Calendar items that overlap the range, in start order. Recurring meetings are expanded by the server.
    static func calendarView(from start: Date, to end: Date, limit: Int) -> [String: Any] {
        [
            "__type": "FindItemRequest:#Exchange",
            "ItemShape": shape(meetingProperties),
            "ParentFolderIds": [distinguished("calendar")],
            "Traversal": "Shallow",
            "CalendarView": [
                "__type": "CalendarViewType:#Exchange",
                "StartDate": iso(start),
                "EndDate": iso(end),
                "MaxEntriesReturned": limit,
            ],
        ]
    }

    // MARK: Restriction helpers

    private static func restriction(_ conditions: [[String: Any]]) -> [String: Any]? {
        switch conditions.count {
        case 0: nil
        case 1: conditions[0]
        default: ["__type": "AndType:#Exchange", "Items": conditions]
        }
    }

    private static func equal(_ field: String, _ value: String) -> [String: Any] {
        [
            "__type": "IsEqualToType:#Exchange",
            "Item": property(field),
            "FieldURIOrConstant": constant(value),
        ]
    }

    private static func compare(_ type: String, _ field: String, _ value: String) -> [String: Any] {
        [
            "__type": type + ":#Exchange",
            "Item": property(field),
            "FieldURIOrConstant": constant(value),
        ]
    }

    private static func contains(_ field: String, _ text: String) -> [String: Any] {
        [
            "__type": "ContainsExpressionType:#Exchange",
            "ContainmentMode": "Substring",
            "ContainmentComparison": "IgnoreCase",
            "Item": property(field),
            "Constant": ["__type": "ConstantValueType:#Exchange", "Value": text],
        ]
    }

    private static func constant(_ value: String) -> [String: Any] {
        [
            "__type": "FieldURIOrConstantType:#Exchange",
            "Constant": ["__type": "ConstantValueType:#Exchange", "Value": value],
        ]
    }

    /// Removes quotes so user text cannot close an AQS phrase early.
    private static func unquoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "")
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
                unreadCount: folder["UnreadCount"] as? Int ?? 0
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
        case .noSuchFolder(let name):
            "There is no folder named \(name)."
        case .noMeeting(let hours):
            "No meeting in the next \(hours) hours."
        case .server(let text):
            "Outlook reported an error: \(text)"
        }
    }
}
