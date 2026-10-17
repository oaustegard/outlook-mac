import Foundation
import WebKit

/// Calls Outlook Web's own service.svc from the signed-in page. The page's session cookies go
/// with each request, and the X-OWA-CANARY cookie is sent as the header OWA checks. Nothing
/// else is needed, so no password or token ever leaves the web view.
@MainActor
enum OWAService {
    /// Runs one service.svc action and returns the reply's Body.
    static func send(_ action: String, body: [String: Any]) async throws -> [String: Any] {
        let webView = try await readyWebView()
        guard let server = ServerConfig.serverURL, let origin = originString(server) else {
            throw OWAError.notConfigured
        }
        guard let canary = await canaryValue(host: server.host) else { throw OWAError.signedOut }

        let envelope: [String: Any] = [
            "__type": "\(action)JsonRequest:#Exchange",
            "Header": requestHeader,
            "Body": body,
        ]
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
        let raw = try await webView.callAsyncJavaScript(
            callScript,
            arguments: ["action": action, "payload": payload, "canary": canary, "origin": origin],
            in: nil,
            contentWorld: .page
        )

        guard let reply = raw as? [String: Any] else { throw OWAError.badReply }
        let status = reply["status"] as? Int ?? 0
        let isJSON = reply["json"] as? Bool ?? false
        // A sign-in page or a session timeout answers with HTML or 401/403/440, never JSON.
        if status == 401 || status == 403 || status == 440 || !isJSON { throw OWAError.signedOut }
        guard (200..<300).contains(status) else { throw OWAError.server("HTTP \(status)") }
        guard let text = reply["text"] as? String,
              let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { throw OWAError.badReply }
        return parsed["Body"] as? [String: Any] ?? parsed
    }

    // MARK: Folders and counts

    /// The folder for a name. "Inbox" and the other common names map without a server call.
    static func folder(named name: String) async throws -> FolderRef {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let known = OWARequest.distinguishedFolders[trimmed.lowercased()] { return known }
        if trimmed.isEmpty { return FolderRef(id: "inbox", distinguished: true) }
        let reply = try await send("FindFolder", body: OWARequest.findFolders())
        let match = try OWAParse.folders(reply).first {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard let match else { throw OWAError.noSuchFolder(trimmed) }
        return FolderRef(id: match.id, distinguished: false)
    }

    static func unreadCount(folder name: String) async throws -> Int {
        let ref = try await folder(named: name)
        let reply = try await send("GetFolder", body: OWARequest.getFolder(ref))
        return try OWAParse.unreadCount(reply)
    }

    // MARK: Messages

    static func recentMessages(folder name: String, unreadOnly: Bool, limit: Int) async throws -> [MessageRecord] {
        let ref = try await folder(named: name)
        var filter = MessageFilter()
        filter.unreadOnly = unreadOnly
        filter.limit = clamp(limit, 1, 500)
        let body = OWARequest.findMessages(filter, parents: [ref.json], deep: false)
        return try OWAParse.messages(await send("FindItem", body: body))
    }

    static func findMessages(_ filter: MessageFilter) async throws -> [MessageRecord] {
        let parents: [[String: Any]]
        let deep: Bool
        if filter.folder.trimmingCharacters(in: .whitespaces).isEmpty || filter.folder == "All Mail" {
            parents = [OWARequest.distinguished("msgfolderroot")]
            deep = true
        } else {
            parents = [try await folder(named: filter.folder).json]
            deep = false
        }
        var bounded = filter
        bounded.limit = clamp(filter.limit, 1, 500)
        let body = OWARequest.findMessages(bounded, parents: parents, deep: deep)
        return try OWAParse.messages(await send("FindItem", body: body))
    }

    /// Message metadata for item ids that Shortcuts kept from an earlier run.
    static func messages(ids: [String]) async throws -> [MessageRecord] {
        guard !ids.isEmpty else { return [] }
        let body = OWARequest.getItems(ids: ids, properties: OWARequest.messageProperties)
        return try OWAParse.messages(await send("GetItem", body: body))
    }

    // MARK: Calendar

    static func meetings(from start: Date, to end: Date, limit: Int) async throws -> [MeetingRecord] {
        let body = OWARequest.calendarView(from: start, to: end, limit: clamp(limit, 1, 500))
        return try OWAParse.meetings(await send("FindItem", body: body))
    }

    static func meetings(ids: [String]) async throws -> [MeetingRecord] {
        guard !ids.isEmpty else { return [] }
        let body = OWARequest.getItems(ids: ids, properties: OWARequest.meetingProperties)
        return try OWAParse.meetings(await send("GetItem", body: body))
    }

    // MARK: Opening Outlook

    /// Puts the query in Outlook's search box and runs it.
    static func search(_ query: String) async throws {
        _ = try await waitForWebView()
        WebViewStore.shared.search(query)
    }

    static func openView(_ view: OutlookView, folder name: String?) async throws {
        let path: String
        switch view {
        case .mail:
            path = "/owa/#path=/mail"
        case .calendar:
            path = "/owa/#path=/calendar"
        case .people:
            path = "/owa/#path=/people"
        case .folder:
            let ref = try await folder(named: name ?? "")
            path = ref.distinguished ? "/owa/#path=/mail/\(ref.id)" : "/owa/#path=/mail/folder/\(encoded(ref.id))"
        }
        try await load(path)
    }

    static func openMessage(id: String) async throws {
        try await load("/owa/#ItemID=\(encoded(id))&exvsurl=1&viewmodel=ReadMessageItem")
    }

    /// Opens a new message with the fields filled in. It is never sent: the user reviews and sends it.
    static func compose(to: String, cc: String?, subject: String, body: String) async throws {
        guard let server = ServerConfig.serverURL, let origin = originString(server),
              var components = URLComponents(string: origin + "/owa/")
        else { throw OWAError.notConfigured }
        var items = [
            URLQueryItem(name: "ae", value: "Item"),
            URLQueryItem(name: "a", value: "New"),
            URLQueryItem(name: "to", value: to),
        ]
        if let cc, !cc.isEmpty { items.append(URLQueryItem(name: "cc", value: cc)) }
        items.append(URLQueryItem(name: "subject", value: subject))
        items.append(URLQueryItem(name: "body", value: body))
        components.queryItems = items
        guard let url = components.url else { throw OWAError.badReply }
        let webView = try await waitForWebView()
        webView.load(URLRequest(url: url))
    }

    private static func load(_ path: String) async throws {
        guard let server = ServerConfig.serverURL, let origin = originString(server),
              let url = URL(string: origin + path)
        else { throw OWAError.notConfigured }
        let webView = try await waitForWebView()
        webView.load(URLRequest(url: url))
    }

    // MARK: Page state

    /// The web view once the app has created it. Waits up to 15 seconds for a window that is still opening.
    static func waitForWebView() async throws -> WKWebView {
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            if let webView = WebViewStore.shared.dispatcher.webView { return webView }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw OWAError.notRunning
    }

    /// The web view on the Exchange server, after any load in progress has finished.
    /// Throws signedOut when the page is elsewhere, such as a Duo or ADFS sign-in.
    private static func readyWebView() async throws -> WKWebView {
        let webView = try await waitForWebView()
        let deadline = ContinuousClock.now + .seconds(15)
        while webView.isLoading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        guard let url = webView.url else { throw OWAError.notRunning }
        guard let server = ServerConfig.serverURL, isSameOrigin(url, server) else { throw OWAError.signedOut }
        return webView
    }

    /// True when the page is on the configured Exchange server, so the bridge's commands are live.
    static func isSameOrigin(_ url: URL, _ server: URL) -> Bool {
        url.scheme?.lowercased() == server.scheme?.lowercased()
            && url.host?.lowercased() == server.host?.lowercased()
            && url.port == server.port
    }

    /// scheme://host[:port] of the server, the origin the page must be on.
    static func originString(_ url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var origin = "\(scheme)://\(host.lowercased())"
        if let port = url.port { origin += ":\(port)" }
        return origin
    }

    /// The X-OWA-CANARY cookie for the server. Read from the web view's own store, so an HttpOnly
    /// cookie is found too. Nil when the session has no canary, which means signed out.
    private static func canaryValue(host: String?) async -> String? {
        guard let host = host?.lowercased() else { return nil }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.first { cookie in
            guard cookie.name == "X-OWA-CANARY", !cookie.value.isEmpty else { return false }
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }?.value
    }

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(high, max(low, value))
    }

    // MARK: JavaScript

    private static let requestHeader: [String: Any] = [
        "__type": "JsonRequestHeaders:#Exchange",
        "RequestServerVersion": "Exchange2013",
        "TimeZoneContext": [
            "__type": "TimeZoneContext:#Exchange",
            "TimeZoneDefinition": ["__type": "TimeZoneDefinitionType:#Exchange", "Id": "UTC"],
        ],
    ]

    /// Runs inside the page (content world .page), so fetch sends the page's cookies. Arguments
    /// are action, payload, canary and origin. Returns { status, json, text }. Pages on another
    /// origin return status 0, which the caller reads as signed out.
    private static let callScript = #"""
    if (location.origin !== origin) { return { status: 0, json: false, text: '' }; }
    const response = await fetch(origin + '/owa/service.svc?action=' + encodeURIComponent(action) + '&app=Mail', {
      method: 'POST',
      credentials: 'same-origin',
      cache: 'no-store',
      headers: {
        'Action': action,
        'Content-Type': 'application/json; charset=utf-8',
        'X-OWA-CANARY': canary
      },
      body: payload
    });
    const type = response.headers.get('content-type') || '';
    return { status: response.status, json: type.indexOf('json') !== -1, text: await response.text() };
    """#
}
