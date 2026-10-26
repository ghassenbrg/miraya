import Foundation
import Security

/// macOS's login Keychain rejects MatchLimitAll combined with ReturnData.
/// Enumerate non-secret account attributes first, then read each item separately.
public struct KeychainVault {
    public let service: String
    public init(service: String) { self.service = service }

    private func query(account: String? = nil) -> [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let account { result[kSecAttrAccount as String] = account }
        return result
    }

    public func records() throws -> [Data] {
        var search = query()
        search[kSecReturnAttributes as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw VaultError(status: status, action: "load TV pairings") }
        guard let attributes = result as? [[String: Any]] else { throw VaultError(status: errSecDecode, action: "load TV pairings") }
        return try attributes.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String else { return nil }
            return try read(account: account)
        }
    }

    public func read(account: String) throws -> Data? {
        var search = query(account: account)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError(status: status == errSecSuccess ? errSecDecode : status, action: "read TV pairing") }
        return data
    }

    public func save(_ data: Data, account: String) throws {
        let match = query(account: account)
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let inserted = SecItemAdd(add as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw VaultError(status: inserted, action: "save TV pairing") }
        } else if status != errSecSuccess { throw VaultError(status: status, action: "save TV pairing") }
    }

    public func remove(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status, action: "forget TV pairing") }
    }

    public struct VaultError: Error, LocalizedError {
        public let status: OSStatus
        public let action: String
        public var errorDescription: String? {
            "Couldn’t \(action) in Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status)). Unlock your login Keychain and try again."
        }
    }
}
