import AppKit
import SwiftUI

/// A small HUD that confirms a copy ("Copied · press ⌘V to paste") and fades away.
/// Shown when Hushclip copies instead of pasting: always in the Mac App Store build,
/// and in the direct build when auto-paste is off or not yet allowed.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func copied(hint: Bool = true) {
        show(title: "Copied", detail: hint ? "Press ⌘V to paste" : nil)
    }

    static func show(title: String, detail: String?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: ToastView(title: title, detail: detail))
        let size = hosting.fittingSize
        panel.contentView = hosting

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.16,
                                  width: size.width, height: size.height), display: false)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private struct ToastView: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
            Text(title).font(.system(size: 14, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .padding(20) // room for the shadow
        .fixedSize()
    }
}
