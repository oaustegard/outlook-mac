import AppKit
import WebKit

/// One window that shows a single OWA page: the Calendar or the People window. Each has its own web
/// view, on the same website data store as the mail window, so the signed-in session carries over.
@MainActor
final class SecondaryWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    enum Kind: String, CaseIterable {
        case calendar
        case people

        var title: String { rawValue.capitalized }
        var newCommand: OutlookCommand { self == .calendar ? .newEvent : .newContact }
        var newLabel: String { self == .calendar ? "New Event" : "New Contact" }
        var symbol: String { self == .calendar ? "calendar.badge.plus" : "person.crop.circle.badge.plus" }
        var frameName: String { "omac-\(rawValue)" }
        var openedKey: String { "\(rawValue)WindowOpen" }

        /// The page on the configured server. Mirrors bridge.js: on-premises OWA routes by hash under
        /// /owa/, and only Microsoft-hosted domains use plain paths unless the server URL is under /owa.
        func url(on server: URL) -> URL? {
            guard let origin = ServerConfig.origin(of: server), let host = server.host?.lowercased() else { return nil }
            let onOwa = server.path.contains("/owa") || !ServerConfig.isMicrosoftHosted(host)
            return URL(string: origin + (onOwa ? "/owa/#path=/\(rawValue)" : "/\(rawValue)"))
        }
    }

    let kind: Kind
    private let webView: WKWebView
    private let newItem = NSToolbarItem.Identifier("omac.new")
    private var loadRequested = false

    init(kind: Kind) {
        self.kind = kind
        webView = WebViewStore.shared.makeWebView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = kind.title
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 480)
        window.toolbarStyle = .unified
        window.contentView = webView
        window.center()
        // Restores the frame this window was last left at, if it has one.
        window.setFrameAutosaveName(kind.frameName)

        super.init(window: window)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "omac.\(kind.rawValue)")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) {
        fatalError("SecondaryWindow is created in code only")
    }

    /// Shows the window. The page loads the first time the window opens, once a server is configured.
    func show(activate: Bool) {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if activate {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        UserDefaults.standard.set(true, forKey: kind.openedKey)
        if !loadRequested, ServerConfig.serverURL != nil {
            loadRequested = true
            loadPage()
        }
    }

    private func loadPage() {
        Task { [self] in
            await WebViewStore.shared.restoredSession()
            guard let server = ServerConfig.serverURL, let url = kind.url(on: server) else { return }
            WebViewStore.shared.installUserScripts(on: webView.configuration.userContentController)
            webView.load(URLRequest(url: url))
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Windows closed by quitting keep their open state, so they reopen at the next launch.
        if !SecondaryWindows.isQuitting {
            UserDefaults.standard.set(false, forKey: kind.openedKey)
        }
    }

    @objc private func runNew() {
        // The key window's web view, as for menu commands. This window is key when its button is clicked.
        WebViewStore.shared.run(kind.newCommand)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [newItem, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, newItem]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == newItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = kind.newLabel
        item.toolTip = kind.newLabel
        item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.newLabel)
        item.target = self
        item.action = #selector(runNew)
        return item
    }
}

/// The Calendar and People windows. Each is a single window: opening it again brings it forward. The
/// ones open at quit reopen at launch.
@MainActor
enum SecondaryWindows {
    /// Set once quitting starts, so the windows AppKit closes on the way out keep their open state.
    private(set) static var isQuitting = false
    private static var controllers: [SecondaryWindow.Kind: SecondaryWindow] = [:]

    static func show(_ kind: SecondaryWindow.Kind) {
        controller(for: kind).show(activate: true)
    }

    /// Reopens the windows that were open at quit, behind the main window.
    static func restoreOpen() {
        for kind in SecondaryWindow.Kind.allCases where UserDefaults.standard.bool(forKey: kind.openedKey) {
            controller(for: kind).show(activate: false)
        }
    }

    static func prepareToQuit() {
        isQuitting = true
    }

    private static func controller(for kind: SecondaryWindow.Kind) -> SecondaryWindow {
        if let existing = controllers[kind] { return existing }
        let created = SecondaryWindow(kind: kind)
        controllers[kind] = created
        return created
    }
}
