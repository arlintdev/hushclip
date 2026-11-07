import AppKit
import HushclipCore
import SwiftUI

/// A screen-sized preview of the selected clip, Quick Look style: images you can pinch to zoom
/// and drag around, and long text or code at a readable size. It follows the selection, so the
/// arrow keys flip through clips while it's open.
///
/// It never takes key focus: the overlay stays key and keeps handling the keyboard
/// (Space, ⌘Y or Esc close it). Images are drawn from memory; nothing is written to disk.
final class LightboxPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Which clips get the enlarge button, Space and ⌘Y.
extension OverlayModel {
    func canEnlarge(_ item: ClipItem) -> Bool {
        if item.category.isSensitive || item.concealed { return false }
        switch item.kind {
        case .image:
            return true
        case .files:
            guard let paths = item.filePaths, paths.count == 1 else { return false }
            return Categorizer.imageExtensions.contains((paths[0] as NSString).pathExtension.lowercased())
        case .text:
            let text = item.text ?? ""
            switch item.category {
            case .json, .code: return true
            default: return text.count > 200 || text.split(whereSeparator: \.isNewline).count > 3
            }
        }
    }
}

struct LightboxView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .contentShape(Rectangle())
                .onTapGesture { model.enlarged = false }
            if let item = model.selectedItem {
                VStack(spacing: 14) {
                    titleBar(item)
                    content(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
                .id(item.id) // reset zoom when the selection changes
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func titleBar(_ item: ClipItem) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: item.category.symbol)
                Text(item.category.title)
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(item.category.color.gradient))
            Text(subtitle(item))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 20)
            Text(hint(item))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Button {
                model.enlarged = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(0.16)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 1200)
    }

    private func subtitle(_ item: ClipItem) -> String {
        guard item.kind == .text, let text = item.text else { return Format.title(item, reveal: false) }
        let lines = text.split(whereSeparator: \.isNewline).count
        let chars = text.count.formatted()
        return lines > 1 ? "\(lines) lines · \(chars) characters" : "\(chars) characters"
    }

    private func hint(_ item: ClipItem) -> String {
        let flip = "↑↓ next clip  ·  Space or Esc to close"
        return isImage(item) ? "Pinch or scroll to zoom  ·  Double-click for actual size  ·  " + flip : flip
    }

    private func isImage(_ item: ClipItem) -> Bool {
        item.kind == .image || (item.kind == .files && model.canEnlarge(item))
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        if !model.canEnlarge(item) && !(item.kind == .text && !item.category.isSensitive && !item.concealed) {
            Text(item.category.isSensitive || item.concealed ? "Hidden for privacy" : "No large preview for this clip")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        } else {
            switch item.kind {
            case .image:
                if let image = model.store.image(for: item) {
                    ZoomableImage(image: image, pixelSize: CGSize(width: item.pixelWidth ?? Int(image.size.width),
                                                                  height: item.pixelHeight ?? Int(image.size.height)))
                }
            case .files:
                if let path = item.filePaths?.first, let image = NSImage(contentsOfFile: path) {
                    let rep = image.representations.first
                    ZoomableImage(image: image, pixelSize: CGSize(width: rep?.pixelsWide ?? Int(image.size.width),
                                                                  height: rep?.pixelsHigh ?? Int(image.size.height)))
                } else {
                    Text("Can't read this file").foregroundStyle(.white.opacity(0.7))
                }
            case .text:
                textCard(item)
            }
        }
    }

    private func textCard(_ item: ClipItem) -> some View {
        var text = item.text ?? ""
        if item.category == .json, text.utf8.count <= 1_000_000 { text = JSONFormat.pretty(text) }
        let technical = item.category.isTechnical || item.category == .json
        let body = Text(String(text.prefix(200_000)))
            .font(technical ? .system(size: 15, design: .monospaced) : .system(size: 18))
            .lineSpacing(technical ? 4 : 6)
            .foregroundStyle(.white.opacity(0.92))
            .fixedSize(horizontal: technical, vertical: false)
            .frame(maxWidth: technical ? nil : 820, alignment: .leading)
            .padding(28)
            .frame(minWidth: 460, alignment: .leading)
        // Hug the content: monospaced text is as wide as its longest line (SF Mono is 0.6 em
        // per character); prose wraps at a readable 820 points. Long clips scroll.
        let longest = text.prefix(200_000).split(whereSeparator: \.isNewline).map(\.count).max() ?? 0
        let width = technical ? min(max(CGFloat(longest) * 9 + 60, 460), 1200) : 876
        return ViewThatFits(in: .vertical) {
            body
            ScrollView([.vertical, .horizontal]) { body }
        }
        .frame(maxWidth: width)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
    }
}

/// An image fitted to the space, which you can pinch (or scroll) to zoom and drag to pan.
/// Double-click toggles between fitted and actual pixels.
struct ZoomableImage: View {
    let image: NSImage
    let pixelSize: CGSize
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private static let maxScale: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let backing = NSScreen.main?.backingScaleFactor ?? 2
            let natural = CGSize(width: max(pixelSize.width, 1) / backing, height: max(pixelSize.height, 1) / backing)
            // Fill the space, but don't blow small images up more than 2×.
            let fit = min(geo.size.width / natural.width, geo.size.height / natural.height, 2)
            let fitted = CGSize(width: natural.width * fit, height: natural.height * fit)

            Image(nsImage: image)
                .resizable()
                .interpolation(scale * fit >= 2 ? .none : .high) // crisp pixels when zoomed way in
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: scale > 1 ? 0 : 10, style: .continuous))
                .shadow(color: .black.opacity(scale > 1 ? 0 : 0.45), radius: 30, y: 12)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in setScale(baseScale * value.magnification) }
                        .onEnded { _ in baseScale = scale }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: baseOffset.width + value.translation.width,
                                            height: baseOffset.height + value.translation.height)
                        }
                        .onEnded { _ in baseOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        if scale > 1.01 {
                            setScale(1)
                        } else {
                            setScale(max(1 / fit, 2)) // actual pixels, or 2× for small images
                        }
                    }
                    baseScale = scale
                    baseOffset = offset
                }
                .background(ScrollWheelZoom { delta in
                    setScale(scale * (1 + delta * 0.01))
                    baseScale = scale
                    baseOffset = offset
                })
                .clipped()
        }
    }

    private func setScale(_ value: CGFloat) {
        scale = min(max(value, 1), Self.maxScale)
        if scale <= 1.001 {
            offset = .zero
            baseOffset = .zero
        }
    }
}

/// Scroll-wheel / two-finger scroll to zoom, for mice without pinch.
private struct ScrollWheelZoom: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollCatcher {
        let view = ScrollCatcher()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ScrollCatcher, context: Context) {
        view.onScroll = onScroll
    }

    final class ScrollCatcher: NSView {
        var onScroll: (CGFloat) -> Void = { _ in }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            // The panel can't become key, so catch scrolls aimed at it with a local monitor.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
                self.onScroll(delta)
                return nil
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}
