import AppKit
import Carbon.HIToolbox
import HushclipCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: ClipStore!
    private var monitor: PasteboardMonitor!
    private var overlay: OverlayController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var lockItem: NSMenuItem!
    private var lock: LockController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()

        store = ClipStore(startLocked: Prefs.lockEnabled)
        lock = LockController(store: store)
        monitor = PasteboardMonitor(store: store)
        monitor.start()

        let model = OverlayModel(store: store)
        model.perform = { [weak self] item, action in self?.use(item, action) }
        model.runAction = { [weak self] item, action in self?.run(action, on: item) }
        model.openSettings = { [weak self] in self?.openSettings() }
        overlay = OverlayController(model: model)
        model.showActionsMenu = { [weak self] in self?.overlay.showActionsMenu() }
        lock.willLock = { [weak self] in self?.overlay.hide() }

        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in
            MainActor.assumeIsolated { self?.toggleOverlay() }
        }
        setUpStatusItem()

        if hotKey?.isRegistered != true {
            alert("⌘⇧V is taken",
                  "Another app has already registered ⌘⇧V. Quit it and relaunch Hushclip, or open history from the menu bar icon.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: - Overlay

    private func toggleOverlay() {
        if overlay.isShown {
            overlay.hide()
        } else {
            let overlay = overlay!
            lock.whenUnlocked { overlay.show() }
        }
    }

    // MARK: - Paste

    private func use(_ item: ClipItem, _ action: OverlayModel.Action) {
        lock.noteActivity()
        Paster.write(item, store: store)
        monitor.ignoreCurrentContents()
        store.markUsed(item.id)
        overlay.hide()
        if action == .paste { autoPaste() }
    }

    /// Presses ⌘V in the app the user was in, if auto-paste is on and allowed.
    private func autoPaste() {
        guard Prefs.autoPaste else { return }
        if Paster.isTrusted {
            // Give the previous app a moment to regain key focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { Paster.sendPasteKeystroke() }
        } else if !Prefs.askedAccessibility {
            Prefs.askedAccessibility = true
            Paster.promptForAccessibility()
        }
    }

    // MARK: - Quick actions

    private func run(_ action: QuickAction, on item: ClipItem) {
        lock.noteActivity()
        overlay.hide()
        switch action.effect {
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .openFile(let path):
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                // The App Sandbox may not let us open a file we were never given; show it instead.
                guard error != nil else { return }
                DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        case .reveal(let paths):
            NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
        case .paste(let text):
            pasteText(text, sensitive: item.concealed || item.category.isSensitive)
        case .pasteRecognizedText:
            guard let image = store.image(for: item)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                NSSound.beep()
                return
            }
            TextRecognizer.recognize(image) { [weak self] text in
                guard let text else { NSSound.beep(); return }
                self?.pasteText(text, sensitive: false)
            }
        }
    }

    /// Pastes text Hushclip made (a converted color, a cleaned link) without recording it as a new clip.
    private func pasteText(_ text: String, sensitive: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if sensitive { pb.setString("", forType: PasteboardMonitor.concealedType) }
        pb.setString(Bundle.main.bundleIdentifier ?? "dev.arlint.clipster", forType: PasteboardMonitor.sourceType)
        monitor.ignoreCurrentContents()
        autoPaste()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Hushclip")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        let show = NSMenuItem(title: "Show Clipboard History", action: #selector(showOverlay), keyEquivalent: "v")
        show.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(show)
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(pauseItem)
        lockItem = NSMenuItem(title: "Lock Now", action: #selector(lockNow), keyEquivalent: "")
        menu.addItem(lockItem)
        menu.addItem(NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About Hushclip", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Hushclip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.state = monitor.isPaused ? .on : .off
        lockItem.isHidden = !Prefs.lockEnabled
        lockItem.title = store.isLocked ? "Locked" : "Lock Now"
        lockItem.isEnabled = !store.isLocked
    }

    @objc private func lockNow() {
        lock.lockNow()
    }

    @objc private func showOverlay() {
        // Let the menu finish closing first so the panel can take key focus.
        let overlay = overlay!, lock = lock!
        DispatchQueue.main.async { lock.whenUnlocked { overlay.show() } }
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        statusItem.button?.image = NSImage(
            systemSymbolName: monitor.isPaused ? "list.clipboard.fill" : "list.clipboard",
            accessibilityDescription: "Hushclip")
        statusItem.button?.appearsDisabled = monitor.isPaused
    }

    @objc private func clearHistory() {
        lock.whenUnlocked { [weak self] in self?.confirmClearHistory() }
    }

    private func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This permanently deletes \(store.items.filter { !$0.pinned }.count) items. Pinned items are kept."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear(keepPinned: true)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                onClearHistory: { [weak self] in self?.clearHistory() },
                onRevealData: { [weak self] in
                    guard let self else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([self.store.directory])
                },
                onLimitsChanged: { [weak self] in self?.store.enforceLimits() },
                authenticate: { [weak self] reason, done in self?.lock.authenticate(reason: reason, completion: done) },
                onLockChanged: { [weak self] in
                    guard let self else { return }
                    // Turning the lock off (already authenticated) opens history again.
                    if !Prefs.lockEnabled { self.store.unlock() }
                    self.lock.noteActivity()
                })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Hushclip Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Encrypted clipboard history.\ngithub.com/arlintdev/hushclip",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
