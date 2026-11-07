import XCTest
@testable import HushclipCore

final class QuickActionsTests: XCTestCase {
    private func text(_ s: String, _ category: ClipCategory? = nil) -> ClipItem {
        ClipItem(kind: .text, text: s, category: category ?? Categorizer.categorize(text: s),
                 contentHash: ClipItem.hash(text: s))
    }

    private func ids(_ item: ClipItem) -> [String] { QuickActions.actions(for: item, home: "/Users/me").map(\.id) }

    private func pasted(_ item: ClipItem, _ id: String) -> String? {
        let action = QuickActions.actions(for: item, home: "/Users/me").first { $0.id == id }
        if case .paste(let s) = action?.effect { return s }
        return nil
    }

    func testLinkOpensAndCleans() {
        let item = text("https://example.com/post?id=7&utm_source=x&fbclid=abc#top")
        let actions = QuickActions.actions(for: item)
        XCTAssertEqual(actions.first?.effect, .open(URL(string: "https://example.com/post?id=7&utm_source=x&fbclid=abc#top")!))
        XCTAssertTrue(actions.first!.opens)
        XCTAssertEqual(pasted(item, "clean"), "https://example.com/post?id=7#top")
        XCTAssertEqual(pasted(item, "markdown"), "[example.com](https://example.com/post?id=7#top)")
    }

    func testCleanLinkHasNoCleanAction() {
        XCTAssertEqual(ids(text("https://www.apple.com/mac/")), ["open", "markdown"])
        XCTAssertEqual(pasted(text("https://www.apple.com/mac/"), "markdown"), "[apple.com](https://www.apple.com/mac/)")
        XCTAssertNil(QuickActions.removingTracking("https://a.com/?q=swift"))
        XCTAssertEqual(QuickActions.removingTracking("https://a.com/?utm_medium=e"), "https://a.com/")
    }

    func testWwwLinkGetsScheme() {
        let open = QuickActions.actions(for: text("www.example.com")).first
        XCTAssertEqual(open?.effect, .open(URL(string: "https://www.example.com")!))
    }

    func testEmailAndPhone() {
        XCTAssertEqual(QuickActions.actions(for: text("a@b.co")).first?.effect, .open(URL(string: "mailto:a@b.co")!))
        let phone = text("+1 (406) 555-0123")
        XCTAssertEqual(phone.category, .phone)
        XCTAssertEqual(ids(phone), ["call", "message", "digits"])
        XCTAssertEqual(QuickActions.actions(for: phone).first?.effect, .open(URL(string: "tel:+14065550123")!))
    }

    func testIPAddress() {
        XCTAssertEqual(ids(text("10.0.0.5")), ["browse", "ssh"])
        let actions = QuickActions.actions(for: text("10.0.0.5:8080"))
        XCTAssertEqual(actions[0].effect, .open(URL(string: "http://10.0.0.5:8080/")!))
        XCTAssertEqual(actions[1].effect, .open(URL(string: "ssh://10.0.0.5")!))
        XCTAssertEqual(pasted(text("10.0.0.0/24"), "address"), "10.0.0.0")
    }

    func testColorConversions() {
        let item = text("#3366cc")
        XCTAssertEqual(ids(item), ["rgb", "hsl", "swiftui"])
        XCTAssertEqual(pasted(item, "rgb"), "rgb(51, 102, 204)")
        XCTAssertEqual(pasted(item, "hsl"), "hsl(220, 60%, 50%)")
        XCTAssertEqual(pasted(item, "swiftui"), "Color(red: 0.2, green: 0.4, blue: 0.8)")
        XCTAssertEqual(pasted(text("rgba(255, 0, 0, 0.5)"), "hex"), "#ff000080")
    }

    func testJSONKeepsKeyOrder() {
        let item = text(#"{"b": 1, "a": [1, 2, {}], "s": "x, y: {z}"}"#)
        XCTAssertEqual(item.category, .json)
        XCTAssertEqual(pasted(item, "minify"), #"{"b":1,"a":[1,2,{}],"s":"x, y: {z}"}"#)
        XCTAssertEqual(pasted(item, "pretty"), """
        {
          "b": 1,
          "a": [
            1,
            2,
            {}
          ],
          "s": "x, y: {z}"
        }
        """)
    }

    func testCommandPrompt() {
        let item = text("$ brew install hushclip")
        XCTAssertEqual(pasted(item, "noprompt"), "brew install hushclip")
        XCTAssertEqual(pasted(item, "codeblock"), "```sh\nbrew install hushclip\n```")
    }

    func testPath() {
        let item = text("~/Library/Application Support/Hushclip", .path)
        let actions = QuickActions.actions(for: item, home: "/Users/me")
        XCTAssertEqual(actions.first?.effect, .reveal(["/Users/me/Library/Application Support/Hushclip"]))
        XCTAssertEqual(pasted(item, "quote"), "~/'Library/Application Support/Hushclip'")
        XCTAssertEqual(QuickActions.shellQuoted("/tmp/it's here"), #"'/tmp/it'\''s here'"#)
        XCTAssertNil(QuickActions.shellQuoted("/usr/local/bin"))
    }

    func testTextTransforms() {
        let item = text("  hello world\nsee https://swift.org/blog for more  ")
        XCTAssertEqual(ids(item).first, "open")
        XCTAssertEqual(QuickActions.actions(for: item).first?.effect, .open(URL(string: "https://swift.org/blog")!))
        XCTAssertEqual(pasted(item, "oneline"), "hello world see https://swift.org/blog for more")
        XCTAssertEqual(pasted(item, "trim"), "hello world\nsee https://swift.org/blog for more")
        XCTAssertEqual(pasted(text("hello there"), "upper"), "HELLO THERE")
        XCTAssertEqual(pasted(text("hello there"), "title"), "Hello There")
    }

    func testSecretsHaveNoActions() {
        XCTAssertTrue(ids(text("ghp_abcdefghijklmnopqrstuvwxyz0123456789")).isEmpty)
        // Card actions never put the number in `detail`, which is shown unmasked.
        let card = QuickActions.actions(for: text("4242 4242 4242 4242"))
        XCTAssertEqual(card.map(\.id), ["digits"])
        XCTAssertNil(card[0].detail)
    }

    func testFilesAndImages() {
        let files = ClipItem(kind: .files, filePaths: ["/Users/me/a.pdf"], category: .file, contentHash: "x")
        XCTAssertEqual(ids(files), ["reveal", "openfile", "paths"])
        let image = ClipItem(kind: .image, blobID: "b", category: .screenshot, contentHash: "y")
        XCTAssertEqual(QuickActions.actions(for: image).first?.effect, .pasteRecognizedText)
    }
}
