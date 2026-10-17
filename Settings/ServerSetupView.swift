import SwiftUI

struct ServerSetupView: View {
    @Binding var isPresented: Bool
    @State private var address = ServerConfig.serverURL?.absoluteString ?? "https://webmail.meso-scale.com/"
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exchange Server")
                .font(.headline)
            Text("Enter the Outlook Web Access address your organization gives you, for example https://mail.example.com/owa/.")
                .foregroundStyle(.secondary)
            TextField("https://", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        guard let url = ServerConfig.validate(address) else {
            errorText = "Enter an https:// address with a host name."
            return
        }
        ServerConfig.save(url)
        WebViewStore.shared.loadServer()
        isPresented = false
    }
}
