import SwiftUI
import WebKit

struct OutlookWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let store = WebViewStore.shared
        let webView = store.makeMailWebView()
        store.startSession()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
