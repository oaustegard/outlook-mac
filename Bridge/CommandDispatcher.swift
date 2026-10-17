import OSLog
import WebKit

@MainActor
final class CommandDispatcher: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "omac"

    weak var webView: WKWebView?
    private let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "bridge")

    func run(_ command: OutlookCommand) {
        evaluate("window.__omac && window.__omac.run('\(command.rawValue)')", label: command.rawValue)
    }

    /// Puts the query in the page's search box and submits it.
    func searchFor(_ query: String) {
        evaluate("window.__omac && window.__omac.searchFor(\(InjectedScript.literal(query)))", label: "searchFor")
    }

    private func evaluate(_ script: String, label: String) {
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
