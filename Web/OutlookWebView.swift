import SwiftUI
import WebKit

struct OutlookWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let store = WebViewStore.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"
        store.installUserScripts(on: configuration.userContentController)
        configuration.userContentController.add(store.dispatcher, name: CommandDispatcher.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.pageZoom = CGFloat(store.pageZoom)
        // Shows behind the page while it loads or overscrolls. Set to the page's own colour once the
        // DOM survey has it.
        webView.underPageBackgroundColor = .windowBackgroundColor
        store.dispatcher.webView = webView
        webView.navigationDelegate = store
        webView.uiDelegate = store
        store.startSession()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
