import AppKit
import OSLog
import WebKit

@MainActor
final class WebViewStore: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = WebViewStore()

    let dispatcher = CommandDispatcher()
    private let nav = Logger(subsystem: "com.oaustegard.outlook-mac", category: "nav")
    private var popupWindows: [NSWindow] = []

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
        guard let url = navigationAction.request.url else {
            logNavigation(nil, navigationAction, decision: "allow")
            decisionHandler(.allow)
            return
        }

        // Only a user's click on a main-frame link leaves the web view. Redirects, form posts,
        // script navigations and subframes stay put, so sign-in round trips (for example 2FA) survive.
        let leaves = navigationAction.navigationType == .linkActivated
            && (navigationAction.targetFrame?.isMainFrame ?? true)
            && isExternal(url)
        logNavigation(url, navigationAction, decision: leaves ? "external" : "allow")
        if leaves {
            openExternally(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    // mailto links and web links outside the in-app domains open in the browser.
    private func isExternal(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "mailto": return true
        case "http", "https": return !staysInApp(url)
        default: return false
        }
    }

    private func logNavigation(_ url: URL?, _ action: WKNavigationAction, decision: String) {
        // Scheme, host and path only: queries can carry tokens.
        var target = url?.scheme ?? "none"
        if let host = url?.host {
            target += "://\(host)\(url?.path ?? "")"
        }
        nav.info("\(decision, privacy: .public) type=\(action.navigationType.rawValue) main=\(action.targetFrame?.isMainFrame ?? true) url=\(target, privacy: .public)")
    }

    // Popups (target=_blank, window.open). A user's click on an external link goes to the browser.
    // Anything else, including sign-in popups, gets a child web view on the passed-in configuration,
    // so window.opener and postMessage keep working.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           isExternal(url) {
            logNavigation(url, navigationAction, decision: "popup-external")
            openExternally(url)
            return nil
        }

        logNavigation(navigationAction.request.url, navigationAction, decision: "popup-child")
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        showPopup(popup)
        return popup
    }

    private func showPopup(_ popup: WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Outlook"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        if let content = window.contentView {
            popup.frame = content.bounds
            popup.autoresizingMask = [.width, .height]
            content.addSubview(popup)
        }
        popupWindows.append(window)
        window.makeKeyAndOrderFront(nil)
    }

    func webViewDidClose(_ webView: WKWebView) {
        nav.info("popup-close")
        let window = popupWindows.first { window in
            window.contentView?.subviews.contains { $0 === webView } == true
        }
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        popupWindows.removeAll { $0 === window }
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
