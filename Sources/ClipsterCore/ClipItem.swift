import CryptoKit
import Foundation

/// One entry in the clipboard history. Stored only inside the encrypted vault.
public struct ClipItem: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, image, files }

    public var id: UUID
    public var kind: Kind
    public var text: String?
    public var filePaths: [String]?
    /// Name of the encrypted image blob on disk (images only).
    public var blobID: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var category: ClipCategory
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var createdAt: Date
    public var lastUsedAt: Date
    public var pinned: Bool
    /// The source app marked this item concealed (password managers).
    public var concealed: Bool
    public var useCount: Int
    public var contentHash: String

    public init(
        id: UUID = UUID(), kind: Kind, text: String? = nil, filePaths: [String]? = nil,
        blobID: String? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil,
        category: ClipCategory, sourceBundleID: String? = nil, sourceAppName: String? = nil,
        createdAt: Date = Date(), pinned: Bool = false, concealed: Bool = false, contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.filePaths = filePaths
        self.blobID = blobID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.category = category
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.lastUsedAt = createdAt
        self.pinned = pinned
        self.concealed = concealed
        self.useCount = 0
        self.contentHash = contentHash
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func hash(text: String) -> String { hash(Data(("t:" + text).utf8)) }
    public static func hash(paths: [String]) -> String { hash(Data(("f:" + paths.joined(separator: "\n")).utf8)) }

    /// Case-insensitive search across content, source app and category name.
    /// Concealed content is never matched, only its metadata.
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        var fields = [category.title, sourceAppName ?? ""]
        if !concealed {
            fields.append(text ?? "")
            fields.append(contentsOf: filePaths ?? [])
        }
        return q.split(separator: " ").allSatisfy { term in
            fields.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

/// The plaintext layout of the vault, before encryption.
public struct VaultFile: Codable, Sendable {
    public var version: Int
    public var items: [ClipItem]

    public init(version: Int = 1, items: [ClipItem]) {
        self.version = version
        self.items = items
    }
}
