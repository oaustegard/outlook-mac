import SwiftUI
import WebKit

struct OutlookWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let store = WebViewStore.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"
        if let bridgeScript = store.bridgeScript {
            configuration.userContentController.addUserScript(bridgeScript)
        }
        configuration.userContentController.add(store.dispatcher, name: CommandDispatcher.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        store.dispatcher.webView = webView
        webView.navigationDelegate = store
        webView.uiDelegate = store
        if let url = ServerConfig.serverURL {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
