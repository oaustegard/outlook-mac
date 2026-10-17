import Foundation
import OSLog
import Security
import WebKit

/// Keeps the Exchange session across quits. OWA's session cookies have no expiry, so WebKit
/// drops them on quit. Matching cookies go into one Keychain item and are restored at launch.
@MainActor
enum CookiePersistence {
    private static let service = "com.oaustegard.outlook-mac.cookies"
    private static let account = "cookies"
    private static let sessionLifetime: TimeInterval = 12 * 60 * 60
    private static let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "cookies")

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
        guard let data = try? JSONEncoder().encode(stored) else { return }
        writeKeychain(data)
    }

    static func restore() async {
        guard let data = readKeychain(),
              let stored = try? JSONDecoder().decode([StoredCookie].self, from: data)
        else { return }

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
        deleteKeychain()
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

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func writeKeychain(_ data: Data) {
        deleteKeychain()
        var attributes = keychainQuery()
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Cookie save to Keychain failed: \(status)")
        }
    }

    private static func readKeychain() -> Data? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func deleteKeychain() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }
}
