import XCTest
@testable import HushclipCore

final class CategorizerTests: XCTestCase {
    private func assertCategory(_ text: String, _ expected: ClipCategory, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Categorizer.categorize(text: text), expected, "for \(text.debugDescription)", file: file, line: line)
    }

    func testSecrets() {
        assertCategory("AKIAIOSFODNN7EXAMPLE", .secret)
        assertCategory("ghp_abcdefghijklmnopqrstuvwxyz0123456789", .secret)
        assertCategory("sk-ant-api03-abcdefghijklmnopqrstuvwxyz012345", .secret)
        assertCategory("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U", .secret)
        assertCategory("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----", .secret)
        assertCategory("export API_KEY=9f8e7d6c5b4a3f2e1d0c", .secret)
        assertCategory("Xk9mQ2vL7pR4tW8yB3nF6hJ1sD5gA0cE", .secret)
    }

    func testPasswords() {
        assertCategory("hunter2", .text) // too short to call
        assertCategory("P@ssw0rd!2024", .password)
        assertCategory("correct-Horse7!battery", .password)
        assertCategory("Tr0ub4dorAndThree3x", .password)
        XCTAssertEqual(Categorizer.categorize(text: "anything at all", concealed: true), .password)
    }

    func testNotPasswords() {
        assertCategory("hello", .text)
        assertCategory("my_variable_name", .text)
        assertCategory("Thanks, see you tomorrow!", .text)
        assertCategory("print(\"hi\")", .text)
    }

    func testCards() {
        assertCategory("4111 1111 1111 1111", .card)
        assertCategory("5555-5555-5555-4444", .card)
        assertCategory("4111 1111 1111 1112", .text) // fails Luhn
    }

    func testContactAndNetwork() {
        assertCategory("https://github.com/arlintdev/hushclip", .url)
        assertCategory("www.apple.com/macos", .url)
        assertCategory("someone@example.com", .email)
        assertCategory("+1 (555) 123-4567", .phone)
        assertCategory("555-867-5309", .phone)
        assertCategory("10.0.0.1", .ip)
        assertCategory("192.168.1.0/24", .ip)
        assertCategory("fe80::1ff:fe23:4567:890a", .ip)
        assertCategory("12:30:45", .text)
    }

    func testIdentifiersAndValues() {
        assertCategory("#ff8800", .color)
        assertCategory("rgb(12, 34, 56)", .color)
        assertCategory("hsl(210 40% 50%)", .color)
        assertCategory("123e4567-e89b-12d3-a456-426614174000", .uuid)
        assertCategory("a94a8fe5ccb19ba61c4c0873d391e987982fbbd3", .hash)
        assertCategory("$1,234.56", .number)
        assertCategory("42", .number)
        assertCategory("2026-11-06", .text)
    }

    func testPathsCommandsCode() {
        assertCategory("~/Library/Application Support/Hushclip", .path)
        assertCategory("/usr/local/bin/swift", .path)
        assertCategory("git push origin main", .command)
        assertCategory("$ brew install --cask hushclip", .command)
        assertCategory("kubectl get pods -n kube-system", .command)
        assertCategory("find . -name '*.swift'", .command)
        assertCategory("find a good restaurant", .text)
        assertCategory("func greet(name: String) -> String {\n    return \"Hi \\(name)\"\n}", .code)
        assertCategory("const x = items.map(i => i.id);\nconsole.log(x);", .code)
        assertCategory("SELECT id, name FROM users WHERE active = 1;", .code)
        assertCategory("{\"name\": \"Hushclip\", \"version\": 1}", .json)
        assertCategory("[1, 2, 3]", .json)
    }

    func testProse() {
        assertCategory("Meeting moved to 3pm — bring the slides.", .text)
        assertCategory("Let me know if you need anything else.\nThanks!", .text)
    }

    func testImagesAndFiles() {
        XCTAssertEqual(Categorizer.categorizeImage(pasteboardTypes: ["public.png", "Apple PNG pasteboard type"], sourceBundleID: "com.apple.finder"), .screenshot)
        XCTAssertEqual(Categorizer.categorizeImage(pasteboardTypes: ["public.png", "public.html", "public.url"], sourceBundleID: "com.apple.Safari"), .image)
        XCTAssertEqual(Categorizer.categorizeImage(pasteboardTypes: ["public.png", "public.html"], sourceBundleID: "com.apple.screencaptureui"), .screenshot)
        XCTAssertEqual(Categorizer.categorizeFiles([URL(fileURLWithPath: "/Users/a/Desktop/Screenshot 2026-11-06 at 9.41.12 AM.png")]), .screenshot)
        XCTAssertEqual(Categorizer.categorizeFiles([URL(fileURLWithPath: "/tmp/photo.jpg")]), .image)
        XCTAssertEqual(Categorizer.categorizeFiles([URL(fileURLWithPath: "/tmp/report.pdf")]), .file)
    }

    func testColorParser() {
        XCTAssertEqual(ColorParser.parse("#fff"), .init(r: 1, g: 1, b: 1, a: 1))
        XCTAssertEqual(ColorParser.parse("rgb(255, 0, 0)"), .init(r: 1, g: 0, b: 0, a: 1))
        let blue = ColorParser.parse("hsl(240, 100%, 50%)")
        XCTAssertEqual(blue?.b ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(blue?.r ?? 1, 0, accuracy: 0.001)
    }
}
