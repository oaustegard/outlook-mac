import OSLog
import WebKit

@MainActor
final class CommandDispatcher: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "omac"

    private let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "bridge")

    /// Runs one command in the given window's web view.
    func run(_ command: OutlookCommand, in webView: WKWebView?) {
        evaluate("window.__omac && window.__omac.run('\(command.rawValue)')", label: command.rawValue, in: webView)
    }

    /// Puts the query in the page's search box and submits it, in the given window's web view.
    func searchFor(_ query: String, in webView: WKWebView?) {
        evaluate(
            "window.__omac && window.__omac.searchFor(\(InjectedScript.literal(query)))",
            label: "searchFor",
            in: webView
        )
    }

    private func evaluate(_ script: String, label: String, in webView: WKWebView?) {
        guard let webView else {
            log.error("No web view attached; dropped \(label, privacy: .public)")
            return
        }
        webView.evaluateJavaScript(script) { [log] _, error in
            if let error {
                log.error("\(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        log.info("bridge: \(String(describing: message.body), privacy: .public)")
    }
}
