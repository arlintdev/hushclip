import CryptoKit
import XCTest
@testable import HushclipCore

final class InboxTests: XCTestCase {
    func testRoundTrip() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let item = ClipItem(kind: .text, text: "copied while locked", category: .text,
                            contentHash: ClipItem.hash(text: "copied while locked"))
        let plain = try JSONEncoder().encode(InboxEntry(item: item))
        let sealed = try InboxCrypto.seal(plain, to: privateKey.publicKey)

        XCTAssertTrue(sealed.starts(with: Data("HUSHINB1".utf8)))
        XCTAssertNil(sealed.range(of: Data("copied while locked".utf8)), "plaintext must not appear on disk")

        let opened = try JSONDecoder().decode(InboxEntry.self, from: InboxCrypto.open(sealed, with: privateKey))
        XCTAssertEqual(opened.item, item)
    }

    func testEachSealIsUnique() throws {
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey
        let a = try InboxCrypto.seal(Data("same".utf8), to: key)
        let b = try InboxCrypto.seal(Data("same".utf8), to: key)
        XCTAssertNotEqual(a, b, "a fresh ephemeral key per clip")
    }

    func testWrongKeyFails() throws {
        let sealed = try InboxCrypto.seal(Data("hello".utf8), to: Curve25519.KeyAgreement.PrivateKey().publicKey)
        XCTAssertThrowsError(try InboxCrypto.open(sealed, with: Curve25519.KeyAgreement.PrivateKey()))
    }

    func testTamperingFails() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        var sealed = try InboxCrypto.seal(Data("hello world".utf8), to: privateKey.publicKey)
        sealed[sealed.count - 5] ^= 0x01
        XCTAssertThrowsError(try InboxCrypto.open(sealed, with: privateKey))
    }

    func testOpensSlicedData() throws {
        // Data read from disk or sliced elsewhere may not start at index 0.
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try InboxCrypto.seal(Data("slice".utf8), to: privateKey.publicKey)
        let sliced = (Data([0, 1, 2]) + sealed).dropFirst(3)
        XCTAssertEqual(try InboxCrypto.open(sliced, with: privateKey), Data("slice".utf8))
    }

    func testOldVaultWithoutInboxKeyStillDecodes() throws {
        let json = #"{"version":1,"items":[]}"#
        let vault = try JSONDecoder().decode(VaultFile.self, from: Data(json.utf8))
        XCTAssertNil(vault.inboxPrivateKey)
    }
}
