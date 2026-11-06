import AppKit
import Carbon.HIToolbox
import ClipsterCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: ClipStore!
    private var monitor: PasteboardMonitor!
    private var overlay: OverlayController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()

        store = ClipStore()
        monitor = PasteboardMonitor(store: store)
        monitor.start()

        let model = OverlayModel(store: store)
        model.perform = { [weak self] item, action in self?.use(item, action) }
        model.openSettings = { [weak self] in self?.openSettings() }
        overlay = OverlayController(model: model)

        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in
            MainActor.assumeIsolated { self?.overlay.toggle() }
        }
        setUpStatusItem()

        if hotKey?.isRegistered != true {
            alert("⌘⇧V is taken",
                  "Another app has already registered ⌘⇧V. Quit it and relaunch Clipster, or open history from the menu bar icon.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: - Paste

    private func use(_ item: ClipItem, _ action: OverlayModel.Action) {
        Paster.write(item, store: store)
        monitor.ignoreCurrentContents()
        store.markUsed(item.id)
        overlay.hide()

        guard action == .paste, Prefs.autoPaste else { return }
        if Paster.isTrusted {
            // Give the previous app a moment to regain key focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { Paster.sendPasteKeystroke() }
        } else if !Prefs.askedAccessibility {
            Prefs.askedAccessibility = true
            Paster.promptForAccessibility()
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipster")
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
        menu.addItem(NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About Clipster", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clipster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.state = monitor.isPaused ? .on : .off
    }

    @objc private func showOverlay() {
        // Let the menu finish closing first so the panel can take key focus.
        DispatchQueue.main.async { self.overlay.show() }
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        statusItem.button?.image = NSImage(
            systemSymbolName: monitor.isPaused ? "list.clipboard.fill" : "list.clipboard",
            accessibilityDescription: "Clipster")
        statusItem.button?.appearsDisabled = monitor.isPaused
    }

    @objc private func clearHistory() {
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
                onLimitsChanged: { [weak self] in self?.store.enforceLimits() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Clipster Settings"
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
                string: "Encrypted clipboard history.\ngithub.com/arlintdev/clipster",
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
