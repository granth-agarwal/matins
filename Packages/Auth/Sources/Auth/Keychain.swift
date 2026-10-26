import Foundation
import Security

public struct Keychain: Sendable {
    public let service: String
    public init(service: String = "com.granth.morningbrief") { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    public func read(_ key: String) throws -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthError.keychain }
        return result as? Data
    }
    public func write(_ data: Data, key: String) throws {
        let q = query(key)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AuthError.keychain }
        } else if status != errSecSuccess { throw AuthError.keychain }
    }
    public func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthError.keychain }
    }
}

public enum AuthError: Error, LocalizedError {
    case missingClient, keychain, signInAgain, cancelled, network, expired
    public var errorDescription: String? {
        switch self {
        case .missingClient: "Add your OAuth client ID in config.yaml."
        case .keychain: "Keychain could not be accessed."
        case .signInAgain: "Sign in again"
        case .cancelled: "Sign-in cancelled."
        case .network: "Sign-in could not connect. Try again."
        case .expired: "Sign-in code expired. Try again."
        }
    }
}
