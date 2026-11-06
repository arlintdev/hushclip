import AppKit
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
        panel.orderOut(nil)
        model.reveal = false
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
        case 53:                                                          // esc
            if !model.query.isEmpty { model.query = "" }
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
            case ",": hide(); model.openSettings(); return true
            case "w": hide(); return true
            default: break
            }
        }
        return false
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
