import AppKit
import WebKit

@MainActor
final class WebViewStore: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = WebViewStore()
    static let homeURL = URL(string: "https://outlook.office.com/mail/")!

    let dispatcher = CommandDispatcher()

    // Nil if bridge.js is missing from the bundle; the menu commands then do nothing.
    let bridgeScript = WebViewStore.loadBridgeScript()

    private static func loadBridgeScript() -> WKUserScript? {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // Domains that stay in the web view, so Outlook and its sign-in flow work there.
    private let inAppDomains = [
        "office.com",
        "office365.com",
        "outlook.com",
        "live.com",
        "microsoftonline.com",
        "microsoft.com",
        "msauth.net",
        "msftauth.net",
        "windows.net",
    ]

    private func staysInApp(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return inAppDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private func openExternally(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
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
