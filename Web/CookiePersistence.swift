import Foundation
import OSLog
import Security
import WebKit

/// Keeps the Exchange session across quits. OWA's session cookies have no expiry, so WebKit
/// drops them on quit. Matching cookies go into session.json in the app's support folder and are
/// restored at launch. The file is readable only by its owner, the same threat model as Safari's
/// cookie store.
@MainActor
enum CookiePersistence {
    // Earlier builds kept the cookies in the Keychain. That item is removed on every launch.
    private static let keychainService = "com.oaustegard.outlook-mac.cookies"
    private static let keychainAccount = "cookies"
    private static let sessionLifetime: TimeInterval = 12 * 60 * 60
    private static let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "cookies")
    private static let fileURL = UserStyles.directory.appendingPathComponent("session.json")

    private struct StoredCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let httpOnly: Bool
        let expires: Date?
        let sameSite: String?
    }

    private static var cookieStore: WKHTTPCookieStore {
        WKWebsiteDataStore.default().httpCookieStore
    }

    /// Cookies for the Exchange server's registrable domain, plus Duo's, which OWA's 2FA flow uses.
    private static func isRelevant(_ cookie: HTTPCookie, serverHost: String) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let base = ServerConfig.registrableDomain(of: serverHost)
        return [base, "duosecurity.com"].contains { domain == $0 || domain.hasSuffix("." + $0) }
    }

    static func save() async {
        guard let serverHost = ServerConfig.serverURL?.host else { return }
        let cookies = await cookieStore.allCookies().filter { isRelevant($0, serverHost: serverHost) }
        let stored = cookies.map { cookie in
            StoredCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                secure: cookie.isSecure,
                httpOnly: cookie.isHTTPOnly,
                expires: cookie.expiresDate,
                sameSite: cookie.sameSitePolicy?.rawValue
            )
        }
        do {
            try write(JSONEncoder().encode(stored))
        } catch {
            log.error("Cookie save failed: \(describe(error), privacy: .public)")
        }
    }

    static func restore() async {
        removeKeychainItem()

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            log.info("No saved session to restore")
            return
        } catch {
            log.error("Cookie read failed: \(describe(error), privacy: .public)")
            return
        }

        let stored: [StoredCookie]
        do {
            stored = try JSONDecoder().decode([StoredCookie].self, from: data)
        } catch {
            log.error("Cookie decode failed: \(describe(error), privacy: .public)")
            return
        }

        let now = Date()
        var restored = 0
        for item in stored {
            // Session cookies have no expiry, so they get the session lifetime from this launch.
            let expires = item.expires ?? now.addingTimeInterval(sessionLifetime)
            guard expires > now,
                  let cookie = HTTPCookie(properties: properties(for: item, expires: expires))
            else { continue }
            await cookieStore.setCookie(cookie)
            restored += 1
        }
        log.info("Restored \(restored) of \(stored.count) cookies")
    }

    static func signOut() async {
        removeKeychainItem()
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            log.error("Session file not removed: \(describe(error), privacy: .public)")
        }
        guard let serverHost = ServerConfig.serverURL?.host else { return }
        for cookie in await cookieStore.allCookies() where isRelevant(cookie, serverHost: serverHost) {
            await cookieStore.deleteCookie(cookie)
        }
    }

    private static func properties(for item: StoredCookie, expires: Date) -> [HTTPCookiePropertyKey: Any] {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: item.name,
            .value: item.value,
            .domain: item.domain,
            .path: item.path,
            .expires: expires,
        ]
        if item.secure { properties[.secure] = "TRUE" }
        if item.httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let sameSite = item.sameSite {
            properties[.sameSitePolicy] = HTTPCookieStringPolicy(rawValue: sameSite)
        }
        return properties
    }

    /// Writes the file atomically, then restricts it to the owner.
    private static func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: UserStyles.directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Removes the Keychain item from earlier builds. A status of errSecItemNotFound is the normal
    /// case after the first launch. Any other status is logged, not treated as fatal.
    private static func removeKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            log.info("Old cookie Keychain item: OSStatus \(status)")
        } else {
            log.error("Old cookie Keychain item not removed: OSStatus \(status)")
        }
    }

    // NSError keeps the domain and code, so a failure is identifiable in the log.
    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
    }
}
