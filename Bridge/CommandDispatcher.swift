import OSLog
import WebKit

@MainActor
final class CommandDispatcher: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "omac"

    weak var webView: WKWebView?
    private let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "bridge")

    func run(_ command: OutlookCommand) {
        guard let webView else {
            log.error("No web view attached; dropped \(command.rawValue, privacy: .public)")
            return
        }
        let script = "window.__omac && window.__omac.run('\(command.rawValue)')"
        webView.evaluateJavaScript(script) { [log] _, error in
            if let error {
                log.error("run \(command.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        log.info("bridge: \(String(describing: message.body), privacy: .public)")
    }
}
