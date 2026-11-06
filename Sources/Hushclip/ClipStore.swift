import AppKit
import HushclipCore
import CryptoKit
import ImageIO

/// Where a clip came from.
struct SourceApp {
    var bundleID: String?
    var name: String?
}

/// The clipboard history. Lives in memory while unlocked; persisted as an AES-GCM encrypted
/// index (`history.vault`) plus one encrypted blob per image.
///
/// When locked, the decrypted history and the vault key are dropped from memory. Clips copied
/// while locked are sealed to the inbox public key (`inbox/*.sealed`) and merged on unlock.
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var isLocked = false
    /// Set when the vault can't be used (Keychain denied, etc). History then stays in memory only.
    @Published private(set) var problem: String?

    let directory: URL
    private let inMemory: Bool
    private var key: SymmetricKey?
    private var inboxPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private var inboxPublicKey: Curve25519.KeyAgreement.PublicKey?
    private var persistent: Bool { !inMemory && key != nil }

    private let ioQueue = DispatchQueue(label: "dev.arlint.clipster.io", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbCache = NSCache<NSString, NSImage>()
    private var expiryTimer: Timer?

    private var indexURL: URL { directory.appendingPathComponent("history.vault") }
    private var blobDirectory: URL { directory.appendingPathComponent("blobs", isDirectory: true) }
    private var inboxDirectory: URL { directory.appendingPathComponent("inbox", isDirectory: true) }
    private var inboxPublicKeyURL: URL { directory.appendingPathComponent("inbox.pub") }

    init(inMemory: Bool = false, startLocked: Bool = false) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Hushclip", isDirectory: true)
        self.inMemory = inMemory
        imageCache.countLimit = 20
        thumbCache.countLimit = 300
        if inMemory { return }

        // Hushclip was called Clipster before 1.1. Carry an existing history over to the new folder.
        let fm = FileManager.default
        let legacy = support.appendingPathComponent("Clipster", isDirectory: true)
        if !fm.fileExists(atPath: directory.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: directory)
        }
        for dir in [directory, blobDirectory, inboxDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }

        if startLocked {
            isLocked = true
            inboxPublicKey = (try? Data(contentsOf: inboxPublicKeyURL))
                .flatMap { try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0) }
        } else {
            openVault()
        }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforceLimits() }
        }
    }

    // MARK: - Locking

    /// Saves, then forgets the decrypted history and every key that can read it.
    func lock() {
        guard !isLocked, !inMemory else { return }
        saveNow()
        items = []
        key = nil
        inboxPrivateKey = nil
        imageCache.removeAllObjects()
        thumbCache.removeAllObjects()
        isLocked = true
    }

    /// Call only after the user has authenticated. Loads the vault and merges clips copied while locked.
    @discardableResult
    func unlock() -> Bool {
        guard isLocked else { return true }
        return openVault()
    }

    @discardableResult
    private func openVault() -> Bool {
        do {
            key = try KeychainKeyStore.loadOrCreateKey()
            problem = nil
        } catch {
            key = nil
            problem = "Couldn't access the Keychain (\(error)). History won't be saved this session."
        }
        isLocked = false
        guard key != nil else { return false }
        load()
        ensureInboxKey()
        mergeInbox()
        enforceLimits()
        return true
    }

    /// Makes sure there is an inbox key pair, and that `inbox.pub` matches the private key in the vault.
    private func ensureInboxKey() {
        guard persistent else { return }
        if inboxPrivateKey == nil {
            inboxPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            // Persist the private key before publishing its public half, so nothing is ever
            // sealed to a key we could lose.
            saveNow()
        }
        guard let publicKey = inboxPrivateKey?.publicKey else { return }
        inboxPublicKey = publicKey
        if (try? Data(contentsOf: inboxPublicKeyURL)) != publicKey.rawRepresentation {
            try? publicKey.rawRepresentation.write(to: inboxPublicKeyURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inboxPublicKeyURL.path)
        }
    }

    // MARK: - Adding

    func addText(_ text: String, category: ClipCategory, concealed: Bool, source: SourceApp?) {
        let item = ClipItem(kind: .text, text: text, category: category,
                            sourceBundleID: source?.bundleID, sourceAppName: source?.name,
                            concealed: concealed, contentHash: ClipItem.hash(text: text))
        if isLocked { return sealToInbox(InboxEntry(item: item)) }
        if bump(hash: item.contentHash, source: source) { return }
        insert(item)
    }

    func addFiles(_ urls: [URL], category: ClipCategory, source: SourceApp?) {
        let paths = urls.map(\.path)
        let item = ClipItem(kind: .files, filePaths: paths, category: category,
                            sourceBundleID: source?.bundleID, sourceAppName: source?.name,
                            contentHash: ClipItem.hash(paths: paths))
        if isLocked { return sealToInbox(InboxEntry(item: item)) }
        if bump(hash: item.contentHash, source: source) { return }
        insert(item)
    }

    func addImage(png: Data, width: Int, height: Int, category: ClipCategory, source: SourceApp?) {
        let hash = ClipItem.hash(png)
        let blobID = UUID().uuidString
        let item = ClipItem(kind: .image, blobID: blobID, pixelWidth: width, pixelHeight: height, category: category,
                            sourceBundleID: source?.bundleID, sourceAppName: source?.name, contentHash: hash)
        let thumb = Self.thumbnailPNG(from: png, maxPixel: 96)
        if isLocked { return sealToInbox(InboxEntry(item: item, image: png, thumbnail: thumb)) }
        if bump(hash: hash, source: source) { return }

        if let image = NSImage(data: png) { imageCache.setObject(image, forKey: blobID as NSString) }
        if let thumb, let image = NSImage(data: thumb) { thumbCache.setObject(image, forKey: blobID as NSString) }
        writeBlob(png, name: blobID)
        if let thumb { writeBlob(thumb, name: blobID + ".thumb") }
        insert(item)
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

    // MARK: - Inbox (clips copied while locked)

    private func sealToInbox(_ entry: InboxEntry) {
        // Without a public key there is nowhere safe to put the clip, so it isn't recorded.
        guard !inMemory, let publicKey = inboxPublicKey else { return }
        let name = String(format: "%013.0f", Date().timeIntervalSince1970 * 1000) + "-" + UUID().uuidString + ".sealed"
        let url = inboxDirectory.appendingPathComponent(name)
        ioQueue.async {
            do {
                let sealed = try InboxCrypto.seal(JSONEncoder().encode(entry), to: publicKey)
                try sealed.write(to: url, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                NSLog("Hushclip: failed to write inbox entry: \(error)")
            }
        }
    }

    private func mergeInbox() {
        guard persistent, let privateKey = inboxPrivateKey else { return }
        ioQueue.sync {}   // let queued inbox writes land
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: inboxDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "sealed" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }   // oldest first; newest ends on top
        guard !files.isEmpty else { return }

        for url in files {
            do {
                let entry = try JSONDecoder().decode(InboxEntry.self, from: InboxCrypto.open(Data(contentsOf: url), with: privateKey))
                ingest(entry)
                try? fm.removeItem(at: url)
            } catch {
                try? fm.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("unreadable"))
            }
        }
        scheduleSave()
    }

    private func ingest(_ entry: InboxEntry) {
        let item = entry.item
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: index)
            existing.lastUsedAt = max(existing.lastUsedAt, item.createdAt)
            existing.sourceBundleID = item.sourceBundleID ?? existing.sourceBundleID
            existing.sourceAppName = item.sourceAppName ?? existing.sourceAppName
            items.insert(existing, at: 0)
            return
        }
        if item.kind == .image, let blobID = item.blobID {
            guard let png = entry.image else { return }
            writeBlob(png, name: blobID)
            if let thumb = entry.thumbnail { writeBlob(thumb, name: blobID + ".thumb") }
        }
        items.insert(item, at: 0)
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
        guard !isLocked else { return }
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
            let vault = try JSONDecoder().decode(VaultFile.self, from: VaultCrypto.open(data, key: key))
            items = vault.items
            inboxPrivateKey = vault.inboxPrivateKey.flatMap { try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: $0) }
        } catch {
            // Never overwrite a vault we can't read: set it aside and start fresh.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = directory.appendingPathComponent("history.unreadable-\(stamp).vault")
            try? FileManager.default.moveItem(at: indexURL, to: aside)
            problem = "The previous history couldn't be decrypted and was set aside."
        }
    }

    private var vaultSnapshot: VaultFile {
        VaultFile(items: items, inboxPrivateKey: inboxPrivateKey?.rawRepresentation)
    }

    private func scheduleSave() {
        guard persistent, let key else { return }
        pendingSave?.cancel()
        let snapshot = vaultSnapshot
        let url = indexURL
        let work = DispatchWorkItem {
            Self.write(snapshot, to: url, key: key)
        }
        pendingSave = work
        ioQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Synchronous save, used when locking and at quit.
    func saveNow() {
        guard persistent, let key else { return }
        pendingSave?.cancel()
        let snapshot = vaultSnapshot
        let url = indexURL
        ioQueue.sync { Self.write(snapshot, to: url, key: key) }
    }

    nonisolated private static func write(_ vault: VaultFile, to url: URL, key: SymmetricKey) {
        do {
            let sealed = try VaultCrypto.seal(JSONEncoder().encode(vault), key: key)
            try sealed.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Hushclip: failed to save vault: \(error)")
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
                NSLog("Hushclip: failed to write blob: \(error)")
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
