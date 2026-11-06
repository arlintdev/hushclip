import CryptoKit
import XCTest
@testable import HushclipCore

final class VaultTests: XCTestCase {
    func testRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let items = [
            ClipItem(kind: .text, text: "secret stuff", category: .text, contentHash: ClipItem.hash(text: "secret stuff")),
            ClipItem(kind: .files, filePaths: ["/tmp/a.png"], category: .image, contentHash: ClipItem.hash(paths: ["/tmp/a.png"])),
        ]
        let plain = try JSONEncoder().encode(VaultFile(items: items))
        let sealed = try VaultCrypto.seal(plain, key: key)

        XCTAssertTrue(sealed.starts(with: Data("CLIPSTR1".utf8)))
        XCTAssertNil(sealed.range(of: Data("secret stuff".utf8)), "plaintext must not appear on disk")

        let opened = try VaultCrypto.open(sealed, key: key)
        let decoded = try JSONDecoder().decode(VaultFile.self, from: opened)
        XCTAssertEqual(decoded.items, items)
    }

    func testWrongKeyFails() throws {
        let sealed = try VaultCrypto.seal(Data("hello".utf8), key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: SymmetricKey(size: .bits256)))
    }

    func testTamperingFails() throws {
        let key = SymmetricKey(size: .bits256)
        var sealed = try VaultCrypto.seal(Data("hello world".utf8), key: key)
        sealed[sealed.count - 20] ^= 0x01
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: key))
    }

    func testBadFormat() {
        XCTAssertThrowsError(try VaultCrypto.open(Data("not a vault".utf8), key: SymmetricKey(size: .bits256))) {
            XCTAssertEqual($0 as? VaultError, .badFormat)
        }
    }

    func testUnknownCategoryDecodesAsText() throws {
        let json = #"["hologram"]"#
        let decoded = try JSONDecoder().decode([ClipCategory].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, [.text])
    }

    func testSearchSkipsConcealedContent() {
        var item = ClipItem(kind: .text, text: "Tr0ub4dor&3", category: .password, contentHash: "x")
        item.concealed = true
        XCTAssertFalse(item.matches("troub"))
        XCTAssertTrue(item.matches("password"))
    }
}
