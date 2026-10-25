import Foundation
import Security
import LocalAuthentication

protocol BWSessionStore: Sendable {
    func read() async throws -> BWSession
    func write(_ value: BWSession) async throws
    func remove() async throws
}

/// Only refresh credentials and the user key are persisted. No master password.
/// Uses the login Keychain, whose default ACL trusts the signed creating app.
/// Developer ID distribution does not have a Data Protection Keychain profile.
/// LocalAuthentication separately gates restoration in EasyPaste after a lock.
actor BWKeychainSessionStore: BWSessionStore {
    private let service: String
    private let authenticate: @Sendable () async throws -> Void
    init(service: String = "app.easypaste.mac.bitwarden", authenticate: @escaping @Sendable () async throws -> Void = { try await BWLocalAuthentication.verify() }) {
        self.service = service; self.authenticate = authenticate
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session-v1", kSecUseDataProtectionKeychain as String: false,
         kSecAttrSynchronizable as String: false]
    }
    func read() async throws -> BWSession {
        try Task.checkCancellation()
        try await authenticate()
        try Task.checkCancellation()
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        guard status == errSecSuccess, let data = value as? Data else { throw BWError.keychain(status) }
        guard data.count < 64 * 1024 else { throw BWError.invalidCipher }
        let session = try JSONDecoder().decode(BWSession.self, from: data)
        guard session.userKey.count == 64, !session.refreshToken.isEmpty else { throw BWError.invalidCipher }
        return session
    }
    func write(_ value: BWSession) async throws {
        try Task.checkCancellation()
        guard value.userKey.count == 64, !value.refreshToken.isEmpty else { throw BWError.invalidCipher }
        var persisted = value; persisted.accessToken = ""; persisted.expires = .distantPast
        let data = try JSONEncoder().encode(persisted)
        guard data.count < 64 * 1024 else { throw BWError.invalidCipher }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw BWError.keychain(status) }
        // Do not set an empty/all-apps ACL. The Keychain default restricts access
        // to the signed creating application and asks before another app reads.
        var add = query; add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "EasyPaste — connexion Bitwarden"
        let result = SecItemAdd(add as CFDictionary, nil)
        guard result == errSecSuccess else { throw BWError.keychain(result) }
    }
    func remove() async throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw BWError.keychain(result) }
    }
}

enum BWLocalAuthentication {
    static func verify() async throws {
        let context = LAContext()
        defer { context.invalidate() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let allowed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Déverrouiller le partage Bitwarden dans EasyPaste")
            try Task.checkCancellation()
            guard allowed else { throw BWError.locked }
        } onCancel: { context.invalidate() }
    }
}
