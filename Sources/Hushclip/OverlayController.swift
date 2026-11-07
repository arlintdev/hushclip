import AppKit
import Combine
import HushclipCore
import SwiftUI

/// A borderless panel that can take keyboard focus without activating Hushclip,
/// so the app you were typing in stays frontmost and receives the paste.
final class OverlayPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class OverlayController {
    static let size = NSSize(width: 800, height: 520)
    static let cornerRadius: CGFloat = 18

    let model: OverlayModel
    private let panel: OverlayPanel
    private var eventMonitor: Any?
    private lazy var lightbox: LightboxPanel = {
        let panel = LightboxPanel()
        panel.contentView = NSHostingView(rootView: LightboxView(model: model))
        return panel
    }()
    private var cancellables: Set<AnyCancellable> = []
    private(set) var isShown = false

    init(model: OverlayModel) {
        self.model = model
        panel = OverlayPanel(size: Self.size)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        panel.contentView = effect

        panel.onResignKey = { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        model.$enlarged.removeDuplicates().dropFirst().sink { [weak self] on in
            on ? self?.showLightbox() : self?.hideLightbox()
        }.store(in: &cancellables)
    }

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        model.reset()
        position()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installEventMonitor()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        removeEventMonitor()
        model.enlarged = false
        hideLightbox()
        panel.orderOut(nil)
        model.reveal = false
    }

    // MARK: - Full-screen preview

    private func showLightbox() {
        guard isShown else { model.enlarged = false; return }
        let screen = panel.screen ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        lightbox.setFrame(frame, display: false)
        lightbox.alphaValue = 0
        lightbox.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            lightbox.animator().alphaValue = 1
        }
    }

    private func hideLightbox() {
        guard lightbox.isVisible else { return }
        lightbox.orderOut(nil)
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = Self.size
        let origin = NSPoint(x: frame.midX - size.width / 2,
                             y: frame.midY - size.height / 2 + frame.height * 0.08)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    // MARK: - Keyboard

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isShown else { return false }
                return self.handle(event)
            }
            return consumed ? nil : event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.type == .flagsChanged {
            model.reveal = flags.contains(.option)
            return false
        }
        guard event.window === panel else { return false }

        let command = flags.contains(.command)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case 125: model.moveSelection(1); return true                     // ↓
        case 126: model.moveSelection(-1); return true                    // ↑
        case 121: model.moveSelection(8); return true                     // page down
        case 116: model.moveSelection(-8); return true                    // page up
        case 36, 76: model.activate(command ? .copy : .paste); return true // ↩
        case 48: model.cycleFilter(forward: !flags.contains(.shift)); return true // ⇥
        case 49 where model.enlarged || (model.query.isEmpty && !command): // space, Quick Look style
            model.toggleEnlarged(); return true
        case 53:                                                          // esc
            if model.enlarged { model.enlarged = false }
            else if !model.query.isEmpty { model.query = "" }
            else if model.filter != .all { model.setFilter(.all) }
            else { hide() }
            return true
        case 51 where command: model.deleteSelected(); return true        // ⌘⌫
        default: break
        }

        if command {
            if let digit = Int(chars), (1...9).contains(digit) {
                model.activate(index: digit - 1)
                return true
            }
            switch chars {
            case "p": model.togglePinSelected(); return true
            case "o": model.openSelected(); return true
            case "k": showActionsMenu(); return true
            case "y": model.toggleEnlarged(); return true
            case ",": hide(); model.openSettings(); return true
            case "w": hide(); return true
            default: break
            }
        }
        return false
    }

    // MARK: - Actions menu (⌘K)

    func showActionsMenu() {
        guard isShown, let item = model.selectedItem, let view = panel.contentView else { return }
        let model = model
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(BlockMenuItem("Paste", symbol: "doc.on.clipboard", key: "\r", modifiers: []) {
            model.perform(item, .paste)
        })
        menu.addItem(BlockMenuItem("Copy", symbol: "square.on.square", key: "\r", modifiers: .command) {
            model.perform(item, .copy)
        })

        if model.canEnlarge(item) {
            menu.addItem(BlockMenuItem("Quick Look", symbol: "eye", key: "y", modifiers: .command) {
                model.enlarged = true
            })
        }

        let actions = model.actions(for: item)
        if !actions.isEmpty {
            menu.addItem(.separator())
            let primary = model.primaryAction(for: item)?.id
            for action in actions {
                let entry = BlockMenuItem(action.title, symbol: action.symbol,
                                          key: action.id == primary ? "o" : "", modifiers: .command) {
                    model.runAction(item, action)
                }
                if let detail = action.detail, #available(macOS 14.4, *) {
                    entry.subtitle = detail.count > 70 ? String(detail.prefix(69)) + "…" : detail
                }
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(item.pinned ? "Unpin" : "Pin", symbol: item.pinned ? "pin.slash" : "pin",
                                   key: "p", modifiers: .command) { model.store.togglePin(item.id) })
        menu.addItem(BlockMenuItem("Delete", symbol: "trash", key: "\u{8}", modifiers: .command) {
            model.selectedID = item.id
            model.deleteSelected()
        })

        // Open beside the preview pane's action bar. Run after this key event finishes.
        DispatchQueue.main.async {
            menu.popUp(positioning: menu.items.first, at: NSPoint(x: 356, y: 150), in: view)
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A menu item that runs a closure.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String, key: String, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
