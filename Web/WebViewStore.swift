import AppKit
import WebKit

@MainActor
final class WebViewStore: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = WebViewStore()
    static let homeURL = URL(string: "https://outlook.office.com/mail/")!

    // Hosts that stay in the web view so sign-in completes there.
    // Placeholder list for M1; confirm against Oskar's tenant sign-in flow.
    private let inAppHosts = [
        "outlook.office.com",
        "outlook.live.com",
        "login.microsoftonline.com",
        "login.live.com",
    ]

    private func staysInApp(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return inAppHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private func openExternally(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto"
        else {
            decisionHandler(.allow)
            return
        }

        if staysInApp(url) {
            decisionHandler(.allow)
        } else {
            openExternally(url)
            decisionHandler(.cancel)
        }
    }

    // Links that ask for a new window (target=_blank) follow the same rule:
    // in-app hosts load in the existing view, everything else opens in the browser.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if staysInApp(url) {
                webView.load(navigationAction.request)
            } else {
                openExternally(url)
            }
        }
        return nil
    }
}
