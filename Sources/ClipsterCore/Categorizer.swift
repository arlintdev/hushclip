import Foundation

/// Regex/heuristic classifier for clipboard contents. Everything runs locally.
public enum Categorizer {

    // MARK: - Public API

    /// Categorize a text clip. `concealed` is true when the source app marked the
    /// pasteboard item with `org.nspasteboard.ConcealedType` (password managers do).
    public static func categorize(text raw: String, concealed: Bool = false) -> ClipCategory {
        if concealed { return .password }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .text }
        let head = t.count > 50_000 ? String(t.prefix(50_000)) : t

        if strongSecrets.contains(where: { matches($0, head) }) { return .secret }

        let singleLine = !t.contains(where: \.isNewline)
        if singleLine, t.count <= 4096, let category = singleLineCategory(t) {
            return category
        }
        if isJSON(t) { return .json }

        let score = codeScore(head)
        if isCommand(t, codeScore: score) { return .command }
        if score >= 2 { return .code }

        if singleLine, t.count <= 256 {
            if isGenericSecret(t) { return .secret }
            if looksLikePassword(t) { return .password }
        }
        return .text
    }

    /// Categorize a raw image on the pasteboard. A bare image with no other
    /// representations (no HTML, URL, text) is what the system screenshot tool
    /// produces, so it's labelled a screenshot.
    public static func categorizeImage(pasteboardTypes: [String], sourceBundleID: String?) -> ClipCategory {
        if let id = sourceBundleID?.lowercased(),
           screenshotApps.contains(where: { id.contains($0) }) {
            return .screenshot
        }
        let extra = pasteboardTypes.filter {
            !$0.hasPrefix("dyn.") && !imagePasteboardTypes.contains($0) && !metadataPasteboardTypes.contains($0)
        }
        return extra.isEmpty ? .screenshot : .image
    }

    /// Categorize copied files (e.g. from Finder).
    public static func categorizeFiles(_ urls: [URL]) -> ClipCategory {
        let names = urls.map(\.lastPathComponent)
        if !names.isEmpty, names.allSatisfy({ matches(screenshotFileName, $0) }) { return .screenshot }
        let exts = Set(urls.map { $0.pathExtension.lowercased() })
        if !exts.isEmpty, exts.isSubset(of: imageExtensions) { return .image }
        return .file
    }

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp"]

    // MARK: - Patterns

    static func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: pattern, options: options) } catch {
            fatalError("Invalid regex \(pattern): \(error)")
        }
    }

    static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Unambiguous credential formats — matched anywhere in the text.
    static let strongSecrets: [NSRegularExpression] = [
        rx(#"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----"#),
        rx(#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),                         // AWS access key id
        rx(#"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#),                        // GitHub tokens
        rx(#"\bgithub_pat_[A-Za-z0-9_]{40,}\b"#),
        rx(#"\bglpat-[A-Za-z0-9_\-]{20,}\b"#),                         // GitLab
        rx(#"\bxox[abposr]-[A-Za-z0-9-]{10,}"#),                       // Slack
        rx(#"\bsk-(?:ant-|proj-)?[A-Za-z0-9_\-]{20,}"#),               // Anthropic / OpenAI
        rx(#"\b[rsp]k_(?:live|test)_[A-Za-z0-9]{16,}"#),               // Stripe
        rx(#"\bAIza[0-9A-Za-z_\-]{35}\b"#),                            // Google API key
        rx(#"\bSG\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}"#),        // SendGrid
        rx(#"\bnpm_[A-Za-z0-9]{36}\b"#),                               // npm
        rx(#"\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#), // JWT
    ]

    /// `API_KEY=...`, `password: ...` as a whole line.
    static let assignedSecret = rx(
        #"^\s*(?:export\s+)?[\w.-]*(?:api[_-]?key|secret|token|passw(?:or)?d|pwd|client[_-]?secret|access[_-]?key)[\w.-]*\s*[:=]\s*['"]?[^\s'"]{8,}['"]?\s*$"#,
        .caseInsensitive)

    static let url = rx(#"^(?:(?:https?|ftp|sftp|ssh|git|s3|file|vnc|rdp|smb)://|www\.)[^\s]+$"#, .caseInsensitive)
    static let email = rx(#"^(?:mailto:)?[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#, .caseInsensitive)
    static let ipv4 = rx(#"^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:/(?:3[0-2]|[12]?\d))?(?::\d{1,5})?$"#)
    static let ipv6 = rx(#"^\[?(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}\]?(?:/\d{1,3})?$"#, .caseInsensitive)
    static let uuid = rx(#"^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$"#, .caseInsensitive)
    static let hexColor = rx(#"^#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$"#, .caseInsensitive)
    static let functionalColor = rx(#"^(?:rgba?|hsla?|hwb|oklch|oklab|lab|lch)\(\s*[-\d.%\s,/a-z]+\)$"#, .caseInsensitive)
    static let number = rx(#"^[-+]?[$€£¥]?\s?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s?%?$"#)
    static let phoneShape = rx(#"^\+?[\d\s().\-]{7,22}$"#)
    static let dateLike = rx(#"^(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})$"#)
    static let hash = rx(#"^(?:[0-9a-f]{7,12}|[0-9a-f]{32}|[0-9a-f]{40}|[0-9a-f]{56}|[0-9a-f]{64}|[0-9a-f]{96}|[0-9a-f]{128})$"#, .caseInsensitive)
    static let path = rx(#"^(?:(?:~|\.{1,2})?/[^\n\x00]*|[a-z]:\\[^\n\x00]*)$"#, .caseInsensitive)
    static let card = rx(#"^(?:\d[ -]?){12,18}\d$"#)
    static let functionCall = rx(#"^[A-Za-z_$][\w$.]*\(.*\)$"#)

    static let screenshotFileName = rx(
        #"^(?:Screenshot|Screen ?Shot|CleanShot|Shottr|Bildschirmfoto|Capture d.écran|Schermafbeelding|Skärmavbild|Captura de pantalla|スクリーンショット|截屏).*\.(?:png|jpe?g|heic|tiff?|gif|webp)$"#,
        .caseInsensitive)

    static let screenshotApps = ["com.apple.screencapture", "com.apple.screenshot", "cleanshot", "shottr", "xnipapp", "snagit"]
    static let imagePasteboardTypes: Set<String> = [
        "public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif",
        "Apple PNG pasteboard type", "NeXT TIFF v4.0 pasteboard type", "com.apple.pict",
    ]
    static let metadataPasteboardTypes: Set<String> = [
        "org.nspasteboard.source", "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "com.apple.is-remote-clipboard", "com.apple.linkpresentation.metadata",
    ]

    static let codeSignals: [NSRegularExpression] = [
        rx(#"(?m)^\s*(?:import\s+[\w.{*"']|from\s+[\w.]+\s+import\s|#include\s*[<"]|#import\s|using\s+[\w.]+;|package\s+[\w.]+;?$|require\(['"])"#),
        rx(#"\b(?:func|def|fn|function|class|struct|enum|interface|trait|impl|let|var|val|const|type)\s+[A-Za-z_$][\w$]*\s*[(<:={]"#),
        rx(#"(?m)[{}]\s*$"#),
        rx(#"(?m);\s*$"#),
        rx(#"=>|::|&&|\|\||!==?|===|\+=|<<|>>|\?\?"#),
        rx(#"(?i)\bSELECT\b[\s\S]+?\bFROM\b|\bINSERT\s+INTO\b|\bCREATE\s+TABLE\b|\bUPDATE\s+\w+\s+SET\b"#),
        rx(#"</[a-z][a-z0-9-]*>|<[a-z][a-z0-9-]*(?:\s[^>]*)?/>"#, .caseInsensitive),
        rx(#"\b\w+\.\w+\([^)\n]*\)"#),
        rx(#"(?m)^\s*(?://|/\*|\*\s|#!/)"#),
    ]

    static let unambiguousCommands: Set<String> = [
        "sudo", "git", "cd", "ls", "brew", "npm", "npx", "pnpm", "yarn", "kubectl", "helm", "docker", "podman",
        "aws", "az", "gcloud", "curl", "wget", "ssh", "scp", "sftp", "rsync", "terraform", "tofu", "terragrunt",
        "python3", "pip", "pip3", "cargo", "swift", "xcodebuild", "xcrun", "grep", "rg", "chmod", "chown", "mkdir",
        "launchctl", "systemctl", "journalctl", "ansible", "ansible-playbook", "packer", "gh", "jq", "yq",
        "defaults", "xattr", "codesign", "openssl", "ssh-keygen", "nmap", "dig", "nslookup", "kubectx", "k9s",
    ]
    static let ambiguousCommands: Set<String> = [
        "find", "open", "make", "go", "cat", "echo", "top", "kill", "pkill", "tail", "head", "less", "touch", "rm",
        "mv", "cp", "ln", "tar", "zip", "unzip", "ps", "du", "df", "nc", "ping", "traceroute", "vim", "nano",
        "code", "sed", "awk", "security", "uv", "bun", "export", "python", "node", "ruby", "bash", "zsh", "sh",
    ]

    // MARK: - Rules

    static func singleLineCategory(_ t: String) -> ClipCategory? {
        if matches(assignedSecret, t) { return .secret }
        if matches(card, t), luhnValid(t) { return .card }
        if matches(url, t) { return .url }
        if matches(email, t) { return .email }
        if matches(ipv4, t) { return .ip }
        if matches(ipv6, t), t.contains("::") || t.filter({ $0 == ":" }).count == 7 { return .ip }
        if matches(uuid, t) { return .uuid }
        if matches(hexColor, t) || matches(functionalColor, t) { return .color }
        if matches(number, t) { return .number }
        if matches(phoneShape, t), !matches(dateLike, t) {
            let digits = t.filter(\.isNumber).count
            if (7...15).contains(digits), t.contains(where: { " ().-+".contains($0) }) { return .phone }
        }
        if matches(hash, t), t.contains(where: \.isNumber), t.contains(where: \.isLetter) { return .hash }
        if matches(path, t), !t.contains(" -") { return .path }
        return nil
    }

    static func luhnValid(_ s: String) -> Bool {
        let digits = s.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), let first = digits.first, (3...6).contains(first) else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let x = d * 2
                sum += x > 9 ? x - 9 : x
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    static func isJSON(_ t: String) -> Bool {
        guard let f = t.first, let l = t.last,
              (f == "{" && l == "}") || (f == "[" && l == "]"),
              let data = t.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    static func codeScore(_ t: String) -> Int {
        var score = codeSignals.reduce(0) { $0 + (matches($1, t) ? 1 : 0) }
        let indented = t.split(whereSeparator: \.isNewline).filter {
            $0.hasPrefix("\t") || $0.hasPrefix("  ")
        }.count
        if indented >= 2 { score += 1 }
        return score
    }

    static func isCommand(_ t: String, codeScore: Int) -> Bool {
        let lines = t.split(whereSeparator: \.isNewline)
        guard let firstLine = lines.first, lines.count <= 12, codeScore < 3 else { return false }
        let line = firstLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("$ ") || line.hasPrefix("% ") || line.hasPrefix("./") { return true }
        let word = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? line
        if unambiguousCommands.contains(word) { return true }
        if ambiguousCommands.contains(word),
           line.split(separator: " ").count <= 30,
           line.contains(where: { "-/|>=~$*\"'".contains($0) }) {
            return true
        }
        return false
    }

    static func isGenericSecret(_ t: String) -> Bool {
        guard t.count >= 24,
              t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=_-.".contains($0)) })
        else { return false }
        return t.contains(where: \.isUppercase) && t.contains(where: \.isLowercase)
            && t.contains(where: \.isNumber) && entropy(t) >= 4.0
    }

    static func looksLikePassword(_ t: String) -> Bool {
        guard (8...128).contains(t.count), !t.contains(where: \.isWhitespace), !matches(functionCall, t) else { return false }
        let lower = t.contains(where: \.isLowercase)
        let upper = t.contains(where: \.isUppercase)
        let digit = t.contains(where: \.isNumber)
        let symbol = t.contains { !$0.isLetter && !$0.isNumber && !"_-./".contains($0) }
        let classes = [lower, upper, digit].filter { $0 }.count
        if symbol && classes >= 2 { return true }
        if t.count >= 14 && classes == 3 && entropy(t) >= 3.3 { return true }
        return false
    }

    /// Shannon entropy in bits per character.
    static func entropy(_ s: String) -> Double {
        var freq: [Character: Int] = [:]
        for c in s { freq[c, default: 0] += 1 }
        let n = Double(s.count)
        return freq.values.reduce(0) { acc, count in
            let p = Double(count) / n
            return acc - p * log2(p)
        }
    }
}
