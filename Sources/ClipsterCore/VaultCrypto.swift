import CryptoKit
import Foundation
import Security

public enum VaultError: Error, Equatable {
    case badFormat
    case sealFailed
    case keychain(OSStatus)
}

/// AES-256-GCM authenticated encryption for everything Clipster writes to disk.
///
/// File layout: `CLIPSTR1` magic (8 bytes) ‖ nonce (12) ‖ ciphertext ‖ tag (16).
/// The magic is bound in as associated data, so it can't be swapped.
public enum VaultCrypto {
    static let magic = Data("CLIPSTR1".utf8)

    public static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: magic)
        guard let combined = box.combined else { throw VaultError.sealFailed }
        return magic + combined
    }

    public static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        guard data.count > magic.count + 28, data.prefix(magic.count) == magic else { throw VaultError.badFormat }
        let box = try AES.GCM.SealedBox(combined: Data(data.dropFirst(magic.count)))
        return try AES.GCM.open(box, using: key, authenticating: magic)
    }
}

/// Holds the vault key in the user's login Keychain. The key is random,
/// generated on first launch, and marked this-device-only / non-synchronizable.
public enum KeychainKeyStore {
    public static let service = "dev.arlint.clipster"
    public static let account = "vault-key"

    public static func loadOrCreateKey(service: String = service, account: String = account) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw VaultError.keychain(status) }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Clipster vault key",
            kSecAttrDescription as String: "Encrypts Clipster clipboard history",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: keyData,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw VaultError.keychain(addStatus) }
        return key
    }
}
