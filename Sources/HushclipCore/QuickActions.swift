import Foundation

/// Something useful to do with a clip besides pasting it as is: open a link, call a number,
/// paste a color in another format, pretty-print JSON, and so on.
public struct QuickAction: Identifiable, Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        /// Open a URL with its default app (browser, Mail, FaceTime, Messages, Terminal).
        case open(URL)
        /// Open a file or folder with its default app.
        case openFile(String)
        /// Select files in Finder.
        case reveal([String])
        /// Paste this text instead of the clip.
        case paste(String)
        /// Recognize the text in an image, then paste it.
        case pasteRecognizedText
    }

    public let id: String
    /// Full title, used in menus ("Paste as Markdown Link").
    public let title: String
    /// Compact title for buttons ("Markdown").
    public let shortTitle: String
    /// SF Symbol name.
    public let symbol: String
    /// What the action produces, when that's worth showing (a converted color, a cleaned link).
    public let detail: String?
    public let effect: Effect

    public init(id: String, title: String, shortTitle: String? = nil, symbol: String,
                detail: String? = nil, effect: Effect) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle ?? title
        self.symbol = symbol
        self.detail = detail
        self.effect = effect
    }

    /// Opens something rather than pasting. The first of these is bound to ⌘O.
    public var opens: Bool {
        switch effect {
        case .open, .openFile, .reveal: true
        case .paste, .pasteRecognizedText: false
        }
    }
}

public enum QuickActions {
    /// Actions for a clip, most useful first. `home` expands `~` in paths; pass the real
    /// home folder (inside the App Sandbox `NSHomeDirectory()` is the app's container).
    public static func actions(for item: ClipItem, home: String = NSHomeDirectory()) -> [QuickAction] {
        switch item.kind {
        case .image:
            return [QuickAction(id: "ocr", title: "Paste Text from Image", shortTitle: "Paste Text",
                                symbol: "text.viewfinder", effect: .pasteRecognizedText)]
        case .files:
            return fileActions(item.filePaths ?? [])
        case .text:
            let text = item.text ?? ""
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return [] }
            switch item.category {
            case .url: return linkActions(t)
            case .email: return emailActions(t)
            case .phone: return phoneActions(t)
            case .ip: return ipActions(t)
            case .color: return colorActions(t)
            case .json: return jsonActions(text)
            case .path: return pathActions(t, home: home)
            case .command: return commandActions(text)
            case .code: return [codeBlock(text, language: "")]
            case .uuid: return caseActions(t) + [newUUID(lowercase: t == t.lowercased())]
            case .hash: return caseActions(t)
            case .number: return numberActions(t)
            case .card: return cardActions(t)
            case .text: return textActions(text)
            case .password, .secret, .screenshot, .image, .file: return []
            }
        }
    }

    // MARK: - Links

    /// Query parameters that only exist to track who clicked what.
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "li_fat_id", "mc_cid", "mc_eid", "igshid", "igsh", "si", "_hsenc", "_hsmi", "mkt_tok", "ref_src",
        "ref_url", "oly_anon_id", "oly_enc_id", "vero_id", "wickedid", "rb_clickid", "s_cid", "_ga", "_gl",
    ]

    static func isTracking(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("utm_") || trackingParameters.contains(n)
    }

    /// The link with tracking parameters removed, or nil if it had none.
    public static func removingTracking(_ link: String) -> String? {
        guard var components = URLComponents(string: link),
              let items = components.percentEncodedQueryItems, !items.isEmpty else { return nil }
        let kept = items.filter { !isTracking($0.name) }
        guard kept.count < items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string
    }

    static func url(fromLink t: String) -> URL? {
        let full = t.lowercased().hasPrefix("www.") ? "https://" + t : t
        guard let url = URL(string: full), url.scheme != nil else { return nil }
        return url
    }

    static func linkActions(_ t: String) -> [QuickAction] {
        guard let url = url(fromLink: t) else { return [] }
        let scheme = url.scheme?.lowercased() ?? ""
        var actions = [QuickAction(
            id: "open", title: scheme.hasPrefix("http") ? "Open Link" : "Open \(scheme.uppercased()) Link",
            shortTitle: "Open", symbol: "arrow.up.right.square.fill", detail: url.host, effect: .open(url))]
        if let clean = removingTracking(url.absoluteString) {
            actions.append(QuickAction(id: "clean", title: "Paste Without Tracking", shortTitle: "Remove Tracking",
                                       symbol: "eye.slash", detail: clean, effect: .paste(clean)))
        }
        let link = removingTracking(url.absoluteString) ?? url.absoluteString
        let label = url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? link
        actions.append(QuickAction(id: "markdown", title: "Paste as Markdown Link", shortTitle: "Markdown",
                                   symbol: "text.badge.plus", detail: "[\(label)](\(link))",
                                   effect: .paste("[\(label)](\(link))")))
        return actions
    }

    // MARK: - People

    static func emailActions(_ t: String) -> [QuickAction] {
        let address = t.lowercased().hasPrefix("mailto:") ? String(t.dropFirst(7)) : t
        var actions: [QuickAction] = []
        if let url = URL(string: "mailto:" + address) {
            actions.append(QuickAction(id: "mail", title: "New Email", shortTitle: "Email", symbol: "envelope.fill",
                                       detail: address, effect: .open(url)))
        }
        if address != t {
            actions.append(QuickAction(id: "address", title: "Paste Address Only", shortTitle: "Address Only",
                                       symbol: "at", detail: address, effect: .paste(address)))
        }
        return actions
    }

    /// Digits with an optional leading +, the form tel: and sms: links want.
    public static func dialable(_ t: String) -> String {
        let digits = t.filter(\.isASCII).filter(\.isNumber)
        return (t.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : "") + digits
    }

    static func phoneActions(_ t: String) -> [QuickAction] {
        let number = dialable(t)
        var actions: [QuickAction] = []
        if let tel = URL(string: "tel:" + number) {
            actions.append(QuickAction(id: "call", title: "Call", symbol: "phone.fill", detail: number, effect: .open(tel)))
        }
        if let sms = URL(string: "sms:" + number) {
            actions.append(QuickAction(id: "message", title: "Send Message", shortTitle: "Message",
                                       symbol: "message.fill", detail: number, effect: .open(sms)))
        }
        if number != t {
            actions.append(QuickAction(id: "digits", title: "Paste Digits Only", shortTitle: "Digits Only",
                                       symbol: "textformat.123", detail: number, effect: .paste(number)))
        }
        return actions
    }

    // MARK: - Network

    static func ipActions(_ t: String) -> [QuickAction] {
        if let slash = t.firstIndex(of: "/") {
            let address = String(t[..<slash])
            return [QuickAction(id: "address", title: "Paste Address Without Prefix", shortTitle: "Address Only",
                                symbol: "network", detail: address, effect: .paste(address))]
        }
        let isV6 = t.filter { $0 == ":" }.count > 1
        let host: String
        let hostPort: String
        if isV6 {
            let bare = t.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            host = "[\(bare)]"
            hostPort = host
        } else {
            host = String(t.split(separator: ":").first ?? Substring(t))
            hostPort = t
        }
        var actions: [QuickAction] = []
        if let web = URL(string: "http://\(hostPort)/") {
            actions.append(QuickAction(id: "browse", title: "Open in Browser", shortTitle: "Browser",
                                       symbol: "safari.fill", detail: web.absoluteString, effect: .open(web)))
        }
        if let ssh = URL(string: "ssh://\(host)") {
            actions.append(QuickAction(id: "ssh", title: "Connect with SSH", shortTitle: "SSH",
                                       symbol: "terminal.fill", detail: ssh.absoluteString, effect: .open(ssh)))
        }
        return actions
    }

    // MARK: - Developer formats

    static func colorActions(_ t: String) -> [QuickAction] {
        guard let rgba = ColorParser.parse(t) else { return [] }
        let s = t.lowercased()
        var actions: [QuickAction] = []
        let formats: [(id: String, name: String, skip: Bool, value: String)] = [
            ("hex", "HEX", s.hasPrefix("#"), ColorParser.hex(rgba)),
            ("rgb", "RGB", s.hasPrefix("rgb"), ColorParser.rgb(rgba)),
            ("hsl", "HSL", s.hasPrefix("hsl"), ColorParser.hsl(rgba)),
            ("swiftui", "SwiftUI", false, ColorParser.swiftUI(rgba)),
        ]
        for f in formats where !f.skip && f.value != t {
            actions.append(QuickAction(id: f.id, title: "Paste as \(f.name)", shortTitle: f.name,
                                       symbol: "paintpalette", detail: f.value, effect: .paste(f.value)))
        }
        return actions
    }

    static func jsonActions(_ text: String) -> [QuickAction] {
        // Reformatting megabytes of JSON on every redraw isn't worth it.
        guard text.utf8.count <= 1_000_000 else { return [] }
        var actions: [QuickAction] = []
        let pretty = JSONFormat.pretty(text)
        if pretty != text {
            actions.append(QuickAction(id: "pretty", title: "Paste Pretty-Printed", shortTitle: "Pretty",
                                       symbol: "text.alignleft", effect: .paste(pretty)))
        }
        let minified = JSONFormat.minify(text)
        if minified != text {
            actions.append(QuickAction(id: "minify", title: "Paste Minified", shortTitle: "Minify",
                                       symbol: "arrow.right.and.line.vertical.and.arrow.left", effect: .paste(minified)))
        }
        actions.append(codeBlock(pretty, language: "json"))
        return actions
    }

    static func codeBlock(_ text: String, language: String) -> QuickAction {
        let body = text.trimmingCharacters(in: .newlines)
        return QuickAction(id: "codeblock", title: "Paste as Code Block", shortTitle: "Code Block",
                           symbol: "chevron.left.forwardslash.chevron.right",
                           effect: .paste("```\(language)\n\(body)\n```"))
    }

    /// The command without a leading `$ ` or `% ` shell prompt on each line, or nil if there was none.
    public static func strippingPrompts(_ text: String) -> String? {
        var changed = false
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            for prompt in ["$ ", "% ", "# ", "> "] where trimmed.hasPrefix(prompt) {
                changed = true
                return String(trimmed.dropFirst(prompt.count))
            }
            return line
        }
        return changed ? lines.joined(separator: "\n") : nil
    }

    static func commandActions(_ text: String) -> [QuickAction] {
        var actions: [QuickAction] = []
        let clean = strippingPrompts(text)
        if let clean {
            actions.append(QuickAction(id: "noprompt", title: "Paste Without Prompt", shortTitle: "No Prompt",
                                       symbol: "dollarsign.square", effect: .paste(clean)))
        }
        actions.append(codeBlock(clean ?? text, language: "sh"))
        return actions
    }

    static func pathActions(_ t: String, home: String) -> [QuickAction] {
        var path = t
        if path == "~" { path = home } else if path.hasPrefix("~/") { path = home + path.dropFirst(1) }
        var actions: [QuickAction] = []
        if path.hasPrefix("/") {
            actions.append(QuickAction(id: "reveal", title: "Show in Finder", shortTitle: "Finder",
                                       symbol: "folder.fill", effect: .reveal([path])))
            actions.append(QuickAction(id: "openfile", title: "Open", symbol: "arrow.up.forward.app.fill",
                                       effect: .openFile(path)))
        }
        if let quoted = shellQuoted(t) {
            actions.append(QuickAction(id: "quote", title: "Paste Quoted for Shell", shortTitle: "Shell-Quoted",
                                       symbol: "quote.closing", detail: quoted, effect: .paste(quoted)))
        }
        return actions
    }

    /// Single-quoted for a POSIX shell (keeping a leading `~/` expandable), or nil if no quoting is needed.
    public static func shellQuoted(_ path: String) -> String? {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-~+,:@%")
        guard path.unicodeScalars.contains(where: { !safe.contains($0) }) else { return nil }
        let quote = { (s: Substring) in "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
        if path.hasPrefix("~/") { return "~/" + quote(path.dropFirst(2)) }
        return quote(Substring(path))
    }

    static func fileActions(_ paths: [String]) -> [QuickAction] {
        guard !paths.isEmpty else { return [] }
        var actions = [QuickAction(id: "reveal", title: "Show in Finder", shortTitle: "Finder",
                                   symbol: "folder.fill", effect: .reveal(paths))]
        if paths.count == 1 {
            actions.append(QuickAction(id: "openfile", title: "Open", symbol: "arrow.up.forward.app.fill",
                                       effect: .openFile(paths[0])))
        }
        let joined = paths.joined(separator: "\n")
        actions.append(QuickAction(id: "paths", title: paths.count == 1 ? "Paste Path" : "Paste Paths",
                                   shortTitle: paths.count == 1 ? "Path" : "Paths", symbol: "text.cursor",
                                   detail: joined, effect: .paste(joined)))
        return actions
    }

    static func caseActions(_ t: String) -> [QuickAction] {
        var actions: [QuickAction] = []
        if t != t.uppercased() {
            actions.append(QuickAction(id: "upper", title: "Paste Uppercase", shortTitle: "UPPERCASE",
                                       symbol: "textformat.size.larger", effect: .paste(t.uppercased())))
        }
        if t != t.lowercased() {
            actions.append(QuickAction(id: "lower", title: "Paste Lowercase", shortTitle: "lowercase",
                                       symbol: "textformat.size.smaller", effect: .paste(t.lowercased())))
        }
        return actions
    }

    static func newUUID(lowercase: Bool) -> QuickAction {
        let fresh = lowercase ? UUID().uuidString.lowercased() : UUID().uuidString
        return QuickAction(id: "newuuid", title: "Paste a New UUID", shortTitle: "New UUID",
                           symbol: "sparkles", detail: fresh, effect: .paste(fresh))
    }

    static func numberActions(_ t: String) -> [QuickAction] {
        let plain = t.filter { !"$€£¥, ".contains($0) }
        guard plain != t, !plain.isEmpty else { return [] }
        return [QuickAction(id: "plain", title: "Paste Plain Number", shortTitle: "Plain Number",
                            symbol: "textformat.123", detail: plain, effect: .paste(plain))]
    }

    static func cardActions(_ t: String) -> [QuickAction] {
        let digits = t.filter(\.isNumber)
        guard digits != t else { return [] }
        // No `detail`: the number stays masked.
        return [QuickAction(id: "digits", title: "Paste Digits Only", shortTitle: "Digits Only",
                            symbol: "textformat.123", effect: .paste(digits))]
    }

    // MARK: - Plain text

    /// The first web link inside a piece of text.
    public static func firstLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let head = String(text.prefix(20_000))
        for match in detector.matches(in: head, range: NSRange(head.startIndex..., in: head)) {
            if let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url
            }
        }
        return nil
    }

    static func textActions(_ text: String) -> [QuickAction] {
        var actions: [QuickAction] = []
        if let link = firstLink(in: text) {
            actions.append(QuickAction(id: "open", title: "Open Link in Text", shortTitle: "Open Link",
                                       symbol: "arrow.up.right.square.fill", detail: link.absoluteString,
                                       effect: .open(link)))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(where: \.isNewline) {
            let oneLine = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
            actions.append(QuickAction(id: "oneline", title: "Paste as One Line", shortTitle: "One Line",
                                       symbol: "arrow.right.to.line", effect: .paste(oneLine)))
        }
        if trimmed != text {
            actions.append(QuickAction(id: "trim", title: "Paste Trimmed", shortTitle: "Trimmed",
                                       symbol: "scissors", effect: .paste(trimmed)))
        }
        actions += caseActions(trimmed)
        let title = trimmed.capitalized
        if title != trimmed {
            actions.append(QuickAction(id: "title", title: "Paste Title Case", shortTitle: "Title Case",
                                       symbol: "textformat", effect: .paste(title)))
        }
        return actions
    }
}

/// Reformats JSON without reordering keys (`JSONSerialization` would).
/// Expects text that already parses as JSON.
public enum JSONFormat {
    public static func minify(_ json: String) -> String {
        var out = ""
        out.reserveCapacity(json.utf8.count)
        var inString = false
        var escaped = false
        for c in json {
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
                out.append(c)
            } else if !c.isWhitespace {
                out.append(c)
            }
        }
        return out
    }

    public static func pretty(_ json: String, indent: String = "  ") -> String {
        let chars = Array(minify(json))
        var out = ""
        var level = 0
        var inString = false
        var escaped = false
        var i = 0
        func newline() { out += "\n" + String(repeating: indent, count: max(level, 0)) }
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                i += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                let close: Character = c == "{" ? "}" : "]"
                if i + 1 < chars.count, chars[i + 1] == close {
                    out.append(c)
                    out.append(close)
                    i += 2
                    continue
                }
                out.append(c)
                level += 1
                newline()
            case "}", "]":
                level -= 1
                newline()
                out.append(c)
            case ",":
                out.append(c)
                newline()
            case ":":
                out += ": "
            default:
                out.append(c)
            }
            i += 1
        }
        return out
    }
}
