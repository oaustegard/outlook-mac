import SwiftUI
import WebKit

struct OutlookWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"

        let store = WebViewStore.shared
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = store
        webView.uiDelegate = store
        webView.load(URLRequest(url: WebViewStore.homeURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
