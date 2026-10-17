import SwiftUI

struct RootView: View {
    @State private var showingServerSetup = ServerConfig.serverURL == nil

    var body: some View {
        OutlookWebView()
            .frame(minWidth: 900, minHeight: 600)
            .sheet(isPresented: $showingServerSetup) {
                ServerSetupView(isPresented: $showingServerSetup)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showServerSetup)) { _ in
                showingServerSetup = true
            }
    }
}
