import SwiftUI

struct RootView: View {
    @State private var showingServerSetup = ServerConfig.serverURL == nil
    @State private var searchText = ""

    var body: some View {
        OutlookWebView()
            .frame(minWidth: 720, minHeight: 480)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
            .onSubmit(of: .search) {
                WebViewStore.shared.search(searchText)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Message", systemImage: "square.and.pencil") {
                        WebViewStore.shared.dispatcher.run(.newMail)
                    }
                }
            }
            .sheet(isPresented: $showingServerSetup) {
                ServerSetupView(isPresented: $showingServerSetup)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showServerSetup)) { _ in
                showingServerSetup = true
            }
    }
}
