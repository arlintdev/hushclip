import AppKit
import ApplicationServices
import HushclipCore

/// Puts a history item back on the pasteboard and (optionally) types ⌘V into the frontmost app.
@MainActor
enum Paster {
    static func write(_ item: ClipItem, store: ClipStore) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let png = store.imageData(for: item) {
                pb.setData(png, forType: .png)
                if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .files:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        }
        // Tell other clipboard tools not to record secrets we hand back.
        if item.concealed || item.category.isSensitive {
            pb.setString("", forType: PasteboardMonitor.concealedType)
        }
        pb.setString(Bundle.main.bundleIdentifier ?? "dev.arlint.clipster", forType: PasteboardMonitor.sourceType)
    }

    /// Whether Hushclip may post the ⌘V keystroke. Uses the post-event permission API,
    /// which (unlike the AXUIElement APIs) works inside the App Sandbox. It is shown to
    /// the user under Privacy & Security → Accessibility.
    static var isTrusted: Bool { CGPreflightPostEventAccess() }

    static func promptForAccessibility() {
        _ = CGRequestPostEventAccess()
    }

    static func openAccessibilitySettings() {
        promptForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Synthesizes ⌘V. Requires Accessibility permission.
    static func sendPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(9) // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
