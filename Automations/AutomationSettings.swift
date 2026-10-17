import Foundation
import Observation

/// Which events are on and which shortcut each one runs, as set in Settings > Automations.
struct AutomationSettings: Codable, Equatable {
    struct Event: Codable, Equatable {
        var enabled = false
        var shortcut = ""
    }

    var newMail = Event()
    var newMailFromContains = ""
    var newMailSubjectContains = ""
    var newMailImportantOnly = false

    var meeting = Event()
    var meetingMinutesBefore = 5

    var unreadChanged = Event()
    var signedOut = Event()
}

@MainActor
@Observable
final class AutomationStore {
    static let shared = AutomationStore()
    private static let defaultsKey = "automations"

    var settings: AutomationSettings {
        didSet { save() }
    }

    private init() {
        let stored = UserDefaults.standard.data(forKey: Self.defaultsKey)
        settings = stored.flatMap { try? JSONDecoder().decode(AutomationSettings.self, from: $0) } ?? AutomationSettings()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// What the monitor remembers between polls and relaunches, so an event never fires twice.
enum AutomationState {
    private static var defaults: UserDefaults { .standard }

    /// Ids of the newest inbox messages already seen. Nil until the first poll after enabling New Mail.
    static var seenMessageIDs: [String]? {
        get { defaults.stringArray(forKey: "automation.seenMessageIDs") }
        set { defaults.set(newValue, forKey: "automation.seenMessageIDs") }
    }

    static var notifiedMeetingIDs: [String] {
        get { defaults.stringArray(forKey: "automation.notifiedMeetingIDs") ?? [] }
        set { defaults.set(newValue, forKey: "automation.notifiedMeetingIDs") }
    }

    /// The inbox unread count the last settled poll saw. Nil until Unread Count Changed is on.
    static var lastUnreadCount: Int? {
        get { defaults.object(forKey: "automation.lastUnreadCount") as? Int }
        set { defaults.set(newValue, forKey: "automation.lastUnreadCount") }
    }

    /// True after Signed Out has fired, until a poll finds the session signed in again.
    static var signedOutReported: Bool {
        get { defaults.bool(forKey: "automation.signedOutReported") }
        set { defaults.set(newValue, forKey: "automation.signedOutReported") }
    }
}
