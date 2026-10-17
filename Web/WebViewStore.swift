import AppKit
import OSLog
import WebKit

@MainActor
final class WebViewStore: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = WebViewStore()

    let dispatcher = CommandDispatcher()
    let userStyles = UserStyles()
    private let nav = Logger(subsystem: "com.oaustegard.outlook-mac", category: "nav")
    private var popupWindows: [NSWindow] = []
    private var sessionStarted = false
    private var saveTimer: Timer?

    // Nil if bridge.js or keymap.json is missing from the bundle; the menu commands then do nothing.
    let bridgeScript = WebViewStore.loadBridgeScript()
    // Nil if theme.css is missing from the bundle; the page then keeps its own fonts.
    let themeScript = WebViewStore.loadThemeScript()

    // Page zoom, persisted across launches. 0.9 is the default.
    private(set) var pageZoom: Double = UserDefaults.standard.object(forKey: "pageZoom") as? Double ?? 0.9

    // A login the user typed, saved to the Keychain once the navigation that used it finishes.
    private var pendingLogin: (host: String, login: CredentialStore.Login)?

    private static let passwordMethods: Set<String> = [
        NSURLAuthenticationMethodNTLM,
        NSURLAuthenticationMethodNegotiate,
        NSURLAuthenticationMethodHTTPBasic,
        NSURLAuthenticationMethodHTTPDigest,
    ]

    private static func loadBridgeScript() -> WKUserScript? {
        guard let bridgeURL = Bundle.main.url(forResource: "bridge", withExtension: "js"),
              let keymapURL = Bundle.main.url(forResource: "keymap", withExtension: "json"),
              let bridge = try? String(contentsOf: bridgeURL, encoding: .utf8),
              let keymap = try? String(contentsOf: keymapURL, encoding: .utf8)
        else { return nil }
        // keymap.json is a JSON object literal, so it is also a valid JavaScript expression.
        let source = "window.__omacKeymap = \(keymap);\n" + bridge
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private static func loadThemeScript() -> WKUserScript? {
        guard let url = Bundle.main.url(forResource: "theme", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(
            source: InjectedScript.style(id: "omac-theme", css: css),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    // Nil if base.css is missing from the bundle; the page then keeps its own styling.
    let baseScript = WebViewStore.loadBaseScript()

    private static func loadBaseScript() -> WKUserScript? {
        guard let url = Bundle.main.url(forResource: "base", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        // Goes before the user's stylesheet in the page, so a rule in user.css overrides it.
        return WKUserScript(
            source: InjectedScript.style(id: "omac-base", css: css, first: true),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    /// Replaces the page's user scripts: the server origin, the bridge, the theme, the base
    /// stylesheet, and the user's stylesheet.
    func installUserScripts(on controller: WKUserContentController) {
        controller.removeAllUserScripts()
        if let originScript = serverOriginScript() { controller.addUserScript(originScript) }
        if let bridgeScript { controller.addUserScript(bridgeScript) }
        if let themeScript { controller.addUserScript(themeScript) }
        if let baseScript { controller.addUserScript(baseScript) }
        controller.addUserScript(userStyles.documentStartScript())
    }

    /// Sets window.__OWA_ORIGIN__ to the configured server's origin. The bridge acts only on that
    /// origin, so its shortcuts do nothing on sign-in pages such as Duo.
    private func serverOriginScript() -> WKUserScript? {
        guard let url = ServerConfig.serverURL, let scheme = url.scheme, let host = url.host else { return nil }
        var origin = "\(scheme)://\(host.lowercased())"
        if let port = url.port { origin += ":\(port)" }
        return WKUserScript(
            source: "window.__OWA_ORIGIN__ = \(InjectedScript.literal(origin));",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    private func reloadUserStyles() {
        guard let webView = dispatcher.webView else { return }
        installUserScripts(on: webView.configuration.userContentController)
        webView.evaluateJavaScript(userStyles.applyScript(), completionHandler: nil)
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

    /// Restores saved cookies, then loads the server. Runs once, when the web view is created.
    func startSession() {
        guard !sessionStarted else { return }
        sessionStarted = true
        userStyles.onChange = { [weak self] in self?.reloadUserStyles() }
        userStyles.startWatching()
        Task { [self] in
            // Cookies must be back before the first load, or the session starts signed out.
            await CookiePersistence.restore()
            loadServer()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.saveCookies() }
            }
        }
    }

    func saveCookies() async {
        await CookiePersistence.save()
    }

    func signOut() {
        Task {
            await CookiePersistence.signOut()
            dispatcher.webView?.reload()
        }
    }

    /// Loads the configured server, if one has been set up.
    func loadServer() {
        guard let url = ServerConfig.serverURL, let webView = dispatcher.webView else { return }
        // Reinstalled here so a server changed in Settings is the origin the bridge sees on this load.
        installUserScripts(on: webView.configuration.userContentController)
        webView.load(URLRequest(url: url))
    }

    func search(_ query: String) {
        dispatcher.searchFor(query)
    }

    func editStylesheet() {
        userStyles.openInEditor()
    }

    func zoomIn() { setZoom(pageZoom + 0.05) }
    func zoomOut() { setZoom(pageZoom - 0.05) }
    func actualSize() { setZoom(1.0) }

    private func setZoom(_ value: Double) {
        pageZoom = min(3.0, max(0.5, (value / 0.05).rounded() * 0.05))
        UserDefaults.standard.set(pageZoom, forKey: "pageZoom")
        dispatcher.webView?.pageZoom = CGFloat(pageZoom)
    }

    /// Writes the page's structure at three window widths to dom-survey-<view>.json in the app's
    /// support folder. A debug aid for layout work; the window is restored to its size afterwards.
    func exportSurvey() {
        Task {
            guard let webView = dispatcher.webView, let window = webView.window else { return }
            let original = window.frame
            var widths: [String] = []
            var view = "other"
            for width in [900, 1280, 1800] {
                var frame = original
                frame.size.width = CGFloat(width)
                window.setFrame(frame, display: true)
                try? await Task.sleep(for: .seconds(1.5))
                guard let json = try? await webView.evaluateJavaScript("window.__omac && window.__omac.survey()") as? String,
                      let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
                else {
                    nav.error("survey failed at width \(width, privacy: .public)")
                    continue
                }
                view = parsed["view"] as? String ?? view
                widths.append("\"\(width)\":\(json)")
            }
            window.setFrame(original, display: true)

            guard !widths.isEmpty else { return }
            do {
                try FileManager.default.createDirectory(at: UserStyles.directory, withIntermediateDirectories: true)
                let file = UserStyles.directory.appendingPathComponent("dom-survey-\(view).json")
                try Data("{\(widths.joined(separator: ","))}".utf8).write(to: file, options: .atomic)
                nav.info("survey written for \(view, privacy: .public)")
            } catch {
                nav.error("survey write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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
