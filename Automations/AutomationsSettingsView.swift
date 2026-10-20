import SwiftUI

/// Settings > Automations: the Dock badge and banner switches, then each event, the shortcut it runs, and its switch.
struct AutomationsSettingsView: View {
    @Bindable private var store = AutomationStore.shared
    @Bindable private var alerts = MailAlertStore.shared
    @State private var shortcuts: [String] = []

    var body: some View {
        Form {
            Section("Dock and Notifications") {
                Toggle("Show unread count in Dock", isOn: $alerts.showsDockBadge)
                Toggle("Show notifications for new mail", isOn: $alerts.showsNotifications)
            }

            Section("New Mail") {
                eventRow("New mail arrives", $store.settings.newMail)
                TextField("Sender contains", text: $store.settings.newMailFromContains)
                TextField("Subject contains", text: $store.settings.newMailSubjectContains)
                Toggle("Important only", isOn: $store.settings.newMailImportantOnly)
            }

            Section("Meeting Starting Soon") {
                eventRow("Meeting starts soon", $store.settings.meeting)
                Stepper(
                    "Minutes before: \(store.settings.meetingMinutesBefore)",
                    value: $store.settings.meetingMinutesBefore,
                    in: 1...60
                )
            }

            Section("Unread Count Changed") {
                eventRow("Unread count changes", $store.settings.unreadChanged)
            }

            Section("Signed Out") {
                eventRow("Session expires", $store.settings.signedOut)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .task { shortcuts = await ShortcutRunner.names() }
    }

    private func eventRow(_ title: String, _ rule: Binding<AutomationSettings.Event>) -> some View {
        Group {
            Toggle(title, isOn: rule.enabled)
            Picker("Run shortcut", selection: rule.shortcut) {
                Text("None").tag("")
                // A shortcut renamed or deleted since it was chosen stays visible, so it can be changed.
                ForEach(options(keeping: rule.wrappedValue.shortcut), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }
    }

    private func options(keeping current: String) -> [String] {
        guard !current.isEmpty, !shortcuts.contains(current) else { return shortcuts }
        return [current] + shortcuts
    }
}
