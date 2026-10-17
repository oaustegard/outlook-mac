import Foundation

extension Notification.Name {
    static let showServerSetup = Notification.Name("showServerSetup")
}

enum ServerConfig {
    static let defaultsKey = "serverURL"

    /// The Exchange OWA base URL the user entered, or nil before first setup.
    static var serverURL: URL? {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(URL.init(string:))
    }

    static func save(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: defaultsKey)
    }

    /// Microsoft's own domains. Their sign-in and OWA pages stay in the web view.
    static let microsoftDomains = [
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

    static func isMicrosoftHosted(_ host: String) -> Bool {
        microsoftDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The scheme, host and port of a URL, in the form the bridge compares with the page's origin.
    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var origin = "\(scheme)://\(host.lowercased())"
        if let port = url.port { origin += ":\(port)" }
        return origin
    }

    /// Accepts only an https URL with a host name.
    static func validate(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// The last two labels of a host, so mail.example.com and sts.example.com share example.com.
    /// An IP address is returned unchanged, since its last two labels are not a domain.
    static func registrableDomain(of host: String) -> String {
        let labels = host.lowercased().split(separator: ".")
        guard let last = labels.last, last.allSatisfy(\.isNumber) == false else { return host.lowercased() }
        return labels.suffix(2).joined(separator: ".")
    }
}
