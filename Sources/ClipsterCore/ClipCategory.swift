import Foundation

/// What a clipboard item is, decided by `Categorizer`.
public enum ClipCategory: String, Codable, CaseIterable, Sendable {
    case screenshot, image, file
    case password, secret, card
    case url, email, phone, ip
    case color, uuid, hash, json, code, command, path, number
    case text

    /// Unknown values (from a newer version's vault) decode as `.text` instead of failing.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ClipCategory(rawValue: raw) ?? .text
    }

    public var title: String {
        switch self {
        case .screenshot: "Screenshot"
        case .image: "Image"
        case .file: "File"
        case .password: "Password"
        case .secret: "Secret"
        case .card: "Card"
        case .url: "Link"
        case .email: "Email"
        case .phone: "Phone"
        case .ip: "IP Address"
        case .color: "Color"
        case .uuid: "UUID"
        case .hash: "Hash"
        case .json: "JSON"
        case .code: "Code"
        case .command: "Command"
        case .path: "Path"
        case .number: "Number"
        case .text: "Text"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .screenshot: "camera.viewfinder"
        case .image: "photo"
        case .file: "doc.fill"
        case .password: "key.fill"
        case .secret: "lock.shield.fill"
        case .card: "creditcard.fill"
        case .url: "link"
        case .email: "envelope.fill"
        case .phone: "phone.fill"
        case .ip: "network"
        case .color: "paintpalette.fill"
        case .uuid: "number.square.fill"
        case .hash: "number"
        case .json: "curlybraces"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .command: "terminal.fill"
        case .path: "folder.fill"
        case .number: "textformat.123"
        case .text: "text.alignleft"
        }
    }

    /// Accent color as sRGB components.
    public var tint: (r: Double, g: Double, b: Double) {
        switch self {
        case .screenshot: (0.69, 0.42, 0.98)
        case .image: (0.96, 0.38, 0.62)
        case .file: (0.35, 0.60, 1.00)
        case .password: (1.00, 0.33, 0.36)
        case .secret: (1.00, 0.55, 0.18)
        case .card: (0.92, 0.66, 0.10)
        case .url: (0.22, 0.62, 1.00)
        case .email: (0.20, 0.74, 0.86)
        case .phone: (0.25, 0.78, 0.42)
        case .ip: (0.45, 0.52, 0.96)
        case .color: (0.88, 0.42, 0.94)
        case .uuid: (0.55, 0.58, 0.70)
        case .hash: (0.50, 0.60, 0.70)
        case .json: (0.95, 0.62, 0.28)
        case .code: (0.24, 0.80, 0.66)
        case .command: (0.48, 0.84, 0.32)
        case .path: (0.38, 0.68, 0.95)
        case .number: (0.68, 0.55, 1.00)
        case .text: (0.58, 0.62, 0.70)
        }
    }

    /// Masked in the UI and auto-expired.
    public var isSensitive: Bool {
        self == .password || self == .secret || self == .card
    }

    /// Shown in a monospaced font.
    public var isTechnical: Bool {
        switch self {
        case .code, .json, .command, .path, .secret, .password, .hash, .uuid, .ip: true
        default: false
        }
    }
}
