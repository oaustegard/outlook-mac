import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Message") {
                WebViewStore.shared.dispatcher.run(.newMail)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Button("Search") {
                WebViewStore.shared.dispatcher.run(.search)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }

        CommandMenu("Go") {
            Button("Inbox") {
                WebViewStore.shared.dispatcher.run(.gotoInbox)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Calendar") {
                WebViewStore.shared.dispatcher.run(.gotoCalendar)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("People") {
                WebViewStore.shared.dispatcher.run(.gotoPeople)
            }
            .keyboardShortcut("3", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Reload") {
                WebViewStore.shared.dispatcher.run(.refresh)
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
