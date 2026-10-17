import AppKit
import WebKit

@MainActor
final class WebViewStore: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = WebViewStore()

    let dispatcher = CommandDispatcher()

    // Nil if bridge.js is missing from the bundle; the menu commands then do nothing.
    let bridgeScript = WebViewStore.loadBridgeScript()

    // A login the user typed, saved to the Keychain once the navigation that used it finishes.
    private var pendingLogin: (host: String, login: CredentialStore.Login)?

    private static let passwordMethods: Set<String> = [
        NSURLAuthenticationMethodNTLM,
        NSURLAuthenticationMethodNegotiate,
        NSURLAuthenticationMethodHTTPBasic,
        NSURLAuthenticationMethodHTTPDigest,
    ]

    private static func loadBridgeScript() -> WKUserScript? {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // Microsoft domains that stay in the web view, so their sign-in flow works there.
    private let microsoftDomains = [
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

    /// Loads the configured server, if one has been set up.
    func loadServer() {
        guard let url = ServerConfig.serverURL else { return }
        dispatcher.webView?.load(URLRequest(url: url))
    }

    // The Exchange server's registrable domain (for example example.com for mail.example.com),
    // so ADFS hosts such as sts.example.com stay in the web view too.
    private func staysInApp(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        if let serverHost = ServerConfig.serverURL?.host?.lowercased() {
            let domain = ServerConfig.registrableDomain(of: serverHost)
            if host == domain || host.hasSuffix("." + domain) { return true }
        }
        return microsoftDomains.contains { host == $0 || host.hasSuffix("." + $0) }
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

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard Self.passwordMethods.contains(space.authenticationMethod) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = space.host
        let failed = challenge.previousFailureCount > 0
        if failed {
            // The stored login was rejected, so drop it before asking again.
            CredentialStore.delete(host: host)
        } else if let stored = CredentialStore.login(for: host) {
            completionHandler(.useCredential, stored)
            return
        }

        guard let login = promptForLogin(host: host, failed: failed) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        pendingLogin = (host, login)
        completionHandler(
            .useCredential,
            URLCredential(user: login.user, password: login.password, persistence: .forSession)
        )
    }

    // The navigation finished without another challenge, so the login worked and can be kept.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let pending = pendingLogin else { return }
        pendingLogin = nil
        CredentialStore.save(pending.login, for: pending.host)
    }

    private func promptForLogin(host: String, failed: Bool) -> CredentialStore.Login? {
        let alert = NSAlert()
        alert.messageText = "Sign in to \(host)"
        alert.informativeText = failed
            ? "The credentials were not accepted. Try again."
            : "Enter your Exchange credentials."
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")

        let user = NSTextField(frame: NSRect(x: 0, y: 32, width: 300, height: 24))
        user.placeholderString = "DOMAIN\\user"
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        password.placeholderString = "Password"
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        fields.addSubview(user)
        fields.addSubview(password)
        alert.accessoryView = fields
        alert.window.initialFirstResponder = user

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = user.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return CredentialStore.Login(user: name, password: password.stringValue)
    }
}
