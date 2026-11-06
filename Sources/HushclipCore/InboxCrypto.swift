import CryptoKit
import Foundation

/// Public-key encryption for clips copied while Hushclip is locked.
///
/// While locked, Hushclip holds no key that can read the vault. New clips are sealed to the
/// inbox *public* key with HPKE (X25519, HKDF-SHA256, ChaCha20-Poly1305). The matching private
/// key is stored only inside the vault, so the inbox can be read again only after unlocking.
///
/// File layout: `HUSHINB1` magic (8 bytes) ‖ encapsulated key (32) ‖ ciphertext ‖ tag (16).
/// The magic is bound in as associated data.
public enum InboxCrypto {
    static let magic = Data("HUSHINB1".utf8)
    static let info = Data("Hushclip inbox v1".utf8)
    static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    static let encapsulatedKeyLength = 32

    public static func seal(_ plaintext: Data, to publicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        var sender = try HPKE.Sender(recipientKey: publicKey, ciphersuite: suite, info: info)
        let ciphertext = try sender.seal(plaintext, authenticating: magic)
        return magic + sender.encapsulatedKey + ciphertext
    }

    public static func open(_ data: Data, with privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        let header = magic.count + encapsulatedKeyLength
        guard data.count > header + 16, data.prefix(magic.count) == magic else { throw VaultError.badFormat }
        let bytes = Data(data)   // re-base indices to 0
        let encapsulated = bytes.subdata(in: magic.count..<header)
        let ciphertext = bytes.subdata(in: header..<bytes.count)
        var recipient = try HPKE.Recipient(privateKey: privateKey, ciphersuite: suite, info: info,
                                           encapsulatedKey: encapsulated)
        return try recipient.open(ciphertext, authenticating: magic)
    }
}

/// One clip captured while locked, before it is merged into the vault.
public struct InboxEntry: Codable, Sendable {
    public var item: ClipItem
    /// PNG data for image clips.
    public var image: Data?
    public var thumbnail: Data?

    public init(item: ClipItem, image: Data? = nil, thumbnail: Data? = nil) {
        self.item = item
        self.image = image
        self.thumbnail = thumbnail
    }
}
