import SwiftUI
import WebKit

struct OutlookWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let store = WebViewStore.shared
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = store
        webView.uiDelegate = store
        webView.load(URLRequest(url: WebViewStore.homeURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
