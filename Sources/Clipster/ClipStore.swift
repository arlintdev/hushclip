import AppKit
import ClipsterCore
import CryptoKit
import ImageIO

/// Where a clip came from.
struct SourceApp {
    var bundleID: String?
    var name: String?
}

/// The clipboard history. Lives in memory while running; persisted as an
/// AES-GCM encrypted index (`history.vault`) plus one encrypted blob per image.
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    /// Set when the vault can't be used (Keychain denied, etc). History then stays in memory only.
    @Published private(set) var problem: String?

    let directory: URL
    private let key: SymmetricKey?
    private let persistent: Bool
    private let ioQueue = DispatchQueue(label: "dev.arlint.clipster.io", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbCache = NSCache<NSString, NSImage>()
    private var expiryTimer: Timer?

    private var indexURL: URL { directory.appendingPathComponent("history.vault") }
    private var blobDirectory: URL { directory.appendingPathComponent("blobs", isDirectory: true) }

    init(inMemory: Bool = false) {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipster", isDirectory: true)
        imageCache.countLimit = 20
        thumbCache.countLimit = 300

        if inMemory {
            key = nil
            persistent = false
            return
        }

        var loadedKey: SymmetricKey?
        do {
            loadedKey = try KeychainKeyStore.loadOrCreateKey()
        } catch {
            problem = "Couldn't access the Keychain (\(error)). History won't be saved this session."
        }
        key = loadedKey
        persistent = loadedKey != nil

        let fm = FileManager.default
        try? fm.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blobDirectory.path)

        load()
        enforceLimits()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforceLimits() }
        }
    }

    // MARK: - Adding

    func addText(_ text: String, category: ClipCategory, concealed: Bool, source: SourceApp?) {
        let hash = ClipItem.hash(text: text)
        if bump(hash: hash, source: source) { return }
        insert(ClipItem(kind: .text, text: text, category: category,
                        sourceBundleID: source?.bundleID, sourceAppName: source?.name,
                        concealed: concealed, contentHash: hash))
    }

    func addFiles(_ urls: [URL], category: ClipCategory, source: SourceApp?) {
        let paths = urls.map(\.path)
        let hash = ClipItem.hash(paths: paths)
        if bump(hash: hash, source: source) { return }
        insert(ClipItem(kind: .files, filePaths: paths, category: category,
                        sourceBundleID: source?.bundleID, sourceAppName: source?.name, contentHash: hash))
    }

    func addImage(png: Data, width: Int, height: Int, category: ClipCategory, source: SourceApp?) {
        let hash = ClipItem.hash(png)
        if bump(hash: hash, source: source) { return }
        let blobID = UUID().uuidString
        let thumb = Self.thumbnailPNG(from: png, maxPixel: 96)

        if let image = NSImage(data: png) { imageCache.setObject(image, forKey: blobID as NSString) }
        if let thumb, let image = NSImage(data: thumb) { thumbCache.setObject(image, forKey: blobID as NSString) }
        writeBlob(png, name: blobID)
        if let thumb { writeBlob(thumb, name: blobID + ".thumb") }

        insert(ClipItem(kind: .image, blobID: blobID, pixelWidth: width, pixelHeight: height, category: category,
                        sourceBundleID: source?.bundleID, sourceAppName: source?.name, contentHash: hash))
    }

    /// Re-copying something already in history moves it to the top instead of duplicating it.
    private func bump(hash: String, source: SourceApp?) -> Bool {
        guard let index = items.firstIndex(where: { $0.contentHash == hash }) else { return false }
        var item = items.remove(at: index)
        item.lastUsedAt = Date()
        if let source {
            item.sourceBundleID = source.bundleID
            item.sourceAppName = source.name
        }
        items.insert(item, at: 0)
        scheduleSave()
        return true
    }

    private func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        enforceLimits()
        scheduleSave()
    }

    // MARK: - Editing

    func markUsed(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.lastUsedAt = Date()
        item.useCount += 1
        items.insert(item, at: 0)
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        removeBlobs(of: [items.remove(at: index)])
        scheduleSave()
    }

    func clear(keepPinned: Bool) {
        let removed = items.filter { !keepPinned || !$0.pinned }
        items.removeAll { !keepPinned || !$0.pinned }
        removeBlobs(of: removed)
        scheduleSave()
    }

    /// Drops expired sensitive items and trims history to the configured size. Pinned items are kept.
    func enforceLimits() {
        var removed: [ClipItem] = []
        let expiry = Prefs.sensitiveExpiryMinutes
        if expiry > 0 {
            let cutoff = Date().addingTimeInterval(-Double(expiry) * 60)
            items.removeAll { item in
                let expired = !item.pinned && (item.category.isSensitive || item.concealed) && item.lastUsedAt < cutoff
                if expired { removed.append(item) }
                return expired
            }
        }
        var unpinned = 0
        let limit = Prefs.maxItems
        items.removeAll { item in
            guard !item.pinned else { return false }
            unpinned += 1
            if unpinned > limit { removed.append(item); return true }
            return false
        }
        if !removed.isEmpty {
            removeBlobs(of: removed)
            scheduleSave()
        }
    }

    // MARK: - Images

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let blobID = item.blobID else { return nil }
        if let cached = thumbCache.object(forKey: blobID as NSString) { return cached }
        guard let data = readBlob(blobID + ".thumb") ?? readBlob(blobID), let image = NSImage(data: data) else { return nil }
        thumbCache.setObject(image, forKey: blobID as NSString)
        return image
    }

    func image(for item: ClipItem) -> NSImage? {
        guard let blobID = item.blobID else { return nil }
        if let cached = imageCache.object(forKey: blobID as NSString) { return cached }
        guard let data = readBlob(blobID), let image = NSImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: blobID as NSString)
        return image
    }

    func imageData(for item: ClipItem) -> Data? {
        item.blobID.flatMap { readBlob($0) }
    }

    private static func thumbnailPNG(from data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    // MARK: - Persistence

    private func load() {
        guard let key, let data = try? Data(contentsOf: indexURL) else { return }
        do {
            let plain = try VaultCrypto.open(data, key: key)
            items = try JSONDecoder().decode(VaultFile.self, from: plain).items
        } catch {
            // Never overwrite a vault we can't read: set it aside and start fresh.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = directory.appendingPathComponent("history.unreadable-\(stamp).vault")
            try? FileManager.default.moveItem(at: indexURL, to: aside)
            problem = "The previous history couldn't be decrypted and was set aside."
        }
    }

    private func scheduleSave() {
        guard persistent, let key else { return }
        pendingSave?.cancel()
        let snapshot = items
        let url = indexURL
        let work = DispatchWorkItem {
            Self.write(VaultFile(items: snapshot), to: url, key: key)
        }
        pendingSave = work
        ioQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Synchronous save, used at quit.
    func saveNow() {
        guard persistent, let key else { return }
        pendingSave?.cancel()
        let snapshot = items
        let url = indexURL
        ioQueue.sync { Self.write(VaultFile(items: snapshot), to: url, key: key) }
    }

    nonisolated private static func write(_ vault: VaultFile, to url: URL, key: SymmetricKey) {
        do {
            let sealed = try VaultCrypto.seal(JSONEncoder().encode(vault), key: key)
            try sealed.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Clipster: failed to save vault: \(error)")
        }
    }

    private func writeBlob(_ data: Data, name: String) {
        guard persistent, let key else { return }
        let url = blobDirectory.appendingPathComponent(name + ".vault")
        ioQueue.async {
            do {
                try VaultCrypto.seal(data, key: key).write(to: url, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                NSLog("Clipster: failed to write blob: \(error)")
            }
        }
    }

    private func readBlob(_ name: String) -> Data? {
        guard let key else { return nil }
        let url = blobDirectory.appendingPathComponent(name + ".vault")
        // Writes are async; make sure a just-queued write has landed.
        ioQueue.sync {}
        guard let sealed = try? Data(contentsOf: url) else { return nil }
        return try? VaultCrypto.open(sealed, key: key)
    }

    private func removeBlobs(of removed: [ClipItem]) {
        let names = removed.compactMap(\.blobID)
        guard !names.isEmpty else { return }
        for name in names {
            imageCache.removeObject(forKey: name as NSString)
            thumbCache.removeObject(forKey: name as NSString)
        }
        let dir = blobDirectory
        ioQueue.async {
            for name in names {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name + ".vault"))
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name + ".thumb.vault"))
            }
        }
    }

    // MARK: - Samples (screenshots / --snapshot only; never persisted)

    func loadSamples(_ samples: [ClipItem], images: [String: NSImage]) {
        items = samples
        for (id, image) in images {
            imageCache.setObject(image, forKey: id as NSString)
            thumbCache.setObject(image, forKey: id as NSString)
        }
    }
}
