import Foundation
import OSLog
import Security

/// Internet-password entries in the Keychain, one per host, for Exchange sign-in.
enum CredentialStore {
    struct Login {
        let user: String
        let password: String
    }

    private static let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "credentials")

    static func login(for host: String) -> URLCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let user = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return URLCredential(user: user, password: password, persistence: .forSession)
    }

    static func save(_ login: Login, for host: String) {
        delete(host: host)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: login.user,
            kSecValueData as String: Data(login.password.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Keychain save for \(host, privacy: .public) failed: \(status)")
        }
    }

    static func delete(host: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
