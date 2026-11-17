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

    /// Whether this build can press ⌘V for the user.
    ///
    /// The Mac App Store build (compiled with `APPSTORE`, see project.yml) can't: posting
    /// keystrokes needs the Accessibility permission, which App Review only allows for
    /// accessibility features (guideline 2.4.5). That build copies the item and the user
    /// pastes; the code that posts events isn't compiled into it at all.
    #if APPSTORE
    static let canAutoPaste = false
    #else
    static let canAutoPaste = true
    #endif

    #if APPSTORE
    static var isTrusted: Bool { false }
    static func promptForAccessibility() {}
    static func openAccessibilitySettings() {}
    static func sendPasteKeystroke() {}
    #else
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
    #endif

    /// What choosing an item does, for labels: "Paste" when Hushclip pastes, "Copy" when it copies.
    static var verb: String { canAutoPaste && Prefs.autoPaste ? "Paste" : "Copy" }
}

@MainActor
extension QuickAction {
    /// The title as shown: "Paste as HEX" becomes "Copy as HEX" when this build copies.
    var displayTitle: String { Self.relabel(title) }
    var displayShortTitle: String { Self.relabel(shortTitle) }

    private static func relabel(_ s: String) -> String {
        guard Paster.verb == "Copy", s.hasPrefix("Paste") else { return s }
        return "Copy" + s.dropFirst(5)
    }
}
