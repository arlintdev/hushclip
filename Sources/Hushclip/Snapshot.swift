import AppKit
import HushclipCore
import SwiftUI

/// `Hushclip --snapshot out.png [--light]` renders the overlay with sample data
/// (in memory only — the real vault and Keychain are never touched). Used for the
/// README screenshot and for checking layout without the hotkey.
@MainActor
enum Snapshot {
    static func run(arguments: [String]) -> Never {
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else {
            FileHandle.standardError.write(Data("usage: Hushclip --snapshot <out.png> [--light] [--reveal] [--select N]\n".utf8))
            exit(2)
        }
        let output = URL(fileURLWithPath: arguments[index + 1])
        let dark = !arguments.contains("--light")
        let selectIndex = arguments.firstIndex(of: "--select").flatMap { Int(arguments[$0 + 1]) } ?? 0
        Prefs.register()

        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApp.appearance = appearance

        let store = ClipStore(inMemory: true)
        let (samples, images) = sampleItems()
        store.loadSamples(samples, images: images)
        let model = OverlayModel(store: store)
        model.reset()
        model.selectedID = samples[min(selectIndex, samples.count - 1)].id
        model.reveal = arguments.contains("--reveal")
        model.accessibilityTrusted = true

        let size = OverlayController.size
        let padding: CGFloat = 40
        let root = ZStack {
            LinearGradient(colors: dark
                           ? [Color(red: 0.16, green: 0.12, blue: 0.32), Color(red: 0.05, green: 0.22, blue: 0.36)]
                           : [Color(red: 0.78, green: 0.84, blue: 1.0), Color(red: 0.95, green: 0.82, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            OverlayView(model: model, opaqueBackground: true)
                .clipShape(RoundedRectangle(cornerRadius: OverlayController.cornerRadius))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        }
        .frame(width: size.width + padding * 2, height: size.height + padding * 2)
        .environment(\.colorScheme, dark ? .dark : .light)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: size.width + padding * 2, height: size.height + padding * 2)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: output)
            print("wrote \(output.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func sampleItems() -> ([ClipItem], [String: NSImage]) {
        let now = Date()
        func text(_ s: String, app: String, bundle: String, minutesAgo: Double, concealed: Bool = false, pinned: Bool = false) -> ClipItem {
            var item = ClipItem(kind: .text, text: s, category: Categorizer.categorize(text: s, concealed: concealed),
                                sourceBundleID: bundle, sourceAppName: app,
                                createdAt: now.addingTimeInterval(-minutesAgo * 60), pinned: pinned,
                                concealed: concealed, contentHash: ClipItem.hash(text: s))
            item.useCount = pinned ? 4 : 0
            return item
        }

        let screenshotID = "sample-screenshot"
        let screenshot = ClipItem(kind: .image, blobID: screenshotID, pixelWidth: 2880, pixelHeight: 1800,
                                  category: .screenshot, sourceBundleID: "com.apple.finder", sourceAppName: "Finder",
                                  createdAt: now.addingTimeInterval(-60 * 2), contentHash: "s")
        let items = [
            text("""
            func categorize(_ text: String) -> ClipCategory {
                if strongSecrets.contains(where: { matches($0, text) }) {
                    return .secret
                }
                return singleLineCategory(text) ?? .text
            }
            """, app: "Xcode", bundle: "com.apple.dt.Xcode", minutesAgo: 0.1),
            screenshot,
            text("Tr0ub4dor&3-horse!", app: "1Password", bundle: "com.1password.1password", minutesAgo: 4, concealed: true),
            text("https://github.com/arlintdev/hushclip/releases", app: "Safari", bundle: "com.apple.Safari", minutesAgo: 9),
            text("kubectl get pods -n kube-system -o wide", app: "Terminal", bundle: "com.apple.Terminal", minutesAgo: 14),
            text("AKIAIOSFODNN7EXAMPLE", app: "Terminal", bundle: "com.apple.Terminal", minutesAgo: 21),
            text("#7C5CFF", app: "Figma", bundle: "com.figma.Desktop", minutesAgo: 33),
            text("hello@arlint.dev", app: "Mail", bundle: "com.apple.mail", minutesAgo: 48, pinned: true),
            text("{\"name\": \"hushclip\", \"version\": \"1.1.0\", \"encrypted\": true}", app: "Visual Studio Code", bundle: "com.microsoft.VSCode", minutesAgo: 65),
            text("10.20.30.40/24", app: "Terminal", bundle: "com.apple.Terminal", minutesAgo: 90),
            text("+1 (555) 010-4242", app: "Messages", bundle: "com.apple.MobileSMS", minutesAgo: 140),
            text("Remember to send the Q4 roadmap to the team before Friday.", app: "Notes", bundle: "com.apple.Notes", minutesAgo: 200),
            text("4111 1111 1111 1111", app: "Safari", bundle: "com.apple.Safari", minutesAgo: 260),
        ]
        return (items, [screenshotID: sampleScreenshot()])
    }

    /// A stand-in "screenshot": a little window mock drawn in code.
    private static func sampleScreenshot() -> NSImage {
        NSImage(size: NSSize(width: 720, height: 450), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.98, green: 0.55, blue: 0.40, alpha: 1),
                                NSColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1)])?.draw(in: rect, angle: -35)
            let window = NSRect(x: 90, y: 60, width: 540, height: 330)
            NSColor(white: 0.12, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: window, xRadius: 16, yRadius: 16).fill()
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: window.minX + 18 + CGFloat(i) * 22, y: window.maxY - 30, width: 13, height: 13)).fill()
            }
            for line in 0..<7 {
                let width = [380, 300, 440, 220, 340, 400, 260][line]
                NSColor(white: 1, alpha: line == 0 ? 0.85 : 0.35).setFill()
                NSBezierPath(roundedRect: NSRect(x: window.minX + 30, y: window.maxY - 70 - CGFloat(line) * 34, width: CGFloat(width), height: 14),
                             xRadius: 7, yRadius: 7).fill()
            }
            return true
        }
    }
}
