import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        // Removes File > New Window and File > New Message; New Message lives under Mail.
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .appInfo) {
            Button("Change Server…") {
                NotificationCenter.default.post(name: .showServerSetup, object: nil)
            }
            Button("Sign Out") {
                WebViewStore.shared.signOut()
            }
        }

        CommandGroup(after: .textEditing) {
            item("Search", .search, "f", [.command, .option])
        }

        CommandMenu("Mail") {
            item("Inbox", .gotoInbox, "1")
            item("New Message", .newMail, "n")
            item("Reply", .reply, "r")
            item("Reply All", .replyAll, "r", [.command, .shift])
            item("Forward", .forward, "f", [.command, .shift])
            item("Send", .send, .return)
            item("Delete", .delete, .delete)
            item("Archive", .archive, "a", [.command, .control])
            item("Mark as Read", .markRead, "u", [.command, .shift])
            item("Mark as Unread", .markUnread, "u", [.command, .option, .shift])
            item("Flag", .flag, "l", [.command, .shift])
            item("Pin", .pin, "p", [.command, .option])
            item("Mark as Junk", .markJunk, "j", [.command, .shift])
        }

        CommandMenu("Calendar") {
            item("Calendar", .gotoCalendar, "2")
            item("New Event", .newEvent, "n", [.command, .option])
            item("Today", .calToday, "t")
            Divider()
            item("Day", .calDay, "1", [.command, .control])
            item("Work Week", .calWorkWeek, "2", [.command, .control])
            item("Week", .calWeek, "3", [.command, .control])
            item("Month", .calMonth, "4", [.command, .control])
        }

        CommandMenu("People") {
            item("People", .gotoPeople, "3")
            item("New Contact", .newContact, "n", [.command, .control])
        }

        CommandMenu("Tasks") {
            item("Tasks", .gotoTasks, "4")
            item("New Task", .newTask, "n", [.command, .control, .option])
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") {
                WebViewStore.shared.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") {
                WebViewStore.shared.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") {
                WebViewStore.shared.actualSize()
            }
            .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Edit Stylesheet…") {
                WebViewStore.shared.editStylesheet()
            }
            Divider()
            item("Reload", .refresh, "r", [.command, .option])
        }

        CommandGroup(after: .windowArrangement) {
            Button("Calendar Window") {
                SecondaryWindows.show(.calendar)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            Button("People Window") {
                SecondaryWindows.show(.people)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
        }

        CommandGroup(after: .help) {
            Button("Export Page Survey") {
                WebViewStore.shared.exportSurvey()
            }
        }
    }

    private func item(
        _ title: String,
        _ command: OutlookCommand,
        _ key: KeyEquivalent,
        _ modifiers: EventModifiers = .command
    ) -> some View {
        Button(title) {
            WebViewStore.shared.run(command)
        }
        .keyboardShortcut(key, modifiers: modifiers)
    }
}
