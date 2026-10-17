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
