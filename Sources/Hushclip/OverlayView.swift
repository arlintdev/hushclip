import AppKit
import HushclipCore
import SwiftUI

extension ClipCategory {
    var color: Color { Color(red: tint.r, green: tint.g, blue: tint.b) }
}

/// Caches app icons by bundle id.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

enum Format {
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        switch s {
        case ..<10: return "now"
        case ..<60: return "\(s)s"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        case ..<(86400 * 7): return "\(s / 86400)d"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    static func mask(_ item: ClipItem) -> String {
        let text = item.text ?? ""
        if item.category == .card {
            let digits = text.filter(\.isNumber)
            return "•••• •••• •••• " + digits.suffix(4)
        }
        return String(repeating: "•", count: 14) // fixed width: don't leak length
    }

    static func title(_ item: ClipItem, reveal: Bool) -> String {
        switch item.kind {
        case .image:
            let size = item.pixelWidth.map { "  \($0)×\(item.pixelHeight ?? 0)" } ?? ""
            return item.category.title + size
        case .files:
            let paths = item.filePaths ?? []
            if paths.count == 1 { return (paths[0] as NSString).lastPathComponent }
            return "\(paths.count) files"
        case .text:
            if item.category.isSensitive && !reveal { return mask(item) }
            let text = item.text ?? ""
            let firstLines = text.prefix(400)
            return firstLines.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }
}

// MARK: - Root

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    var opaqueBackground = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = model.filtered
        let selected = model.selectedItem

        VStack(spacing: 0) {
            header
            chips
            Divider().opacity(0.6)

            if items.isEmpty {
                EmptyStateView(hasHistory: !model.store.items.isEmpty, query: model.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ItemListView(model: model, items: items, selectedID: selected?.id)
                        .frame(width: 340)
                    Divider().opacity(0.6)
                    PreviewPane(model: model, item: selected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider().opacity(0.6)
            footer
        }
        .frame(width: OverlayController.size.width, height: OverlayController.size.height)
        .background {
            if opaqueBackground {
                RoundedRectangle(cornerRadius: OverlayController.cornerRadius).fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: OverlayController.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($searchFocused)
                .onChange(of: model.query) { model.selectedID = model.filtered.first?.id }
            if let problem = model.store.problem {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(problem)
            }
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                Text("Encrypted")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green.opacity(0.14)))
            .help("History is stored with AES-256-GCM; the key lives in your Keychain.")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ChipView(title: "All", symbol: "square.grid.2x2.fill", color: .accentColor,
                         count: model.store.items.count, selected: model.filter == .all) {
                    model.setFilter(.all)
                }
                if model.pinnedCount > 0 {
                    ChipView(title: "Pinned", symbol: "pin.fill", color: .yellow,
                             count: model.pinnedCount, selected: model.filter == .pinned) {
                        model.setFilter(.pinned)
                    }
                }
                ForEach(model.categoryCounts) { entry in
                    ChipView(title: entry.category.title, symbol: entry.category.symbol, color: entry.category.color,
                             count: entry.count, selected: model.filter == .category(entry.category)) {
                        model.setFilter(.category(entry.category))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(keys: "↩", label: "Paste")
            KeyHint(keys: "⌘↩", label: "Copy")
            KeyHint(keys: "⌘P", label: "Pin")
            KeyHint(keys: "⌘⌫", label: "Delete")
            KeyHint(keys: "⇥", label: "Filter")
            KeyHint(keys: "⌥", label: "Reveal")
            Spacer()
            if !model.accessibilityTrusted && Prefs.autoPaste {
                Button {
                    Paster.openAccessibilitySettings()
                } label: {
                    Label("Enable auto-paste", systemImage: "hand.raised.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help("Hushclip needs Accessibility permission to press ⌘V for you. Until then, items are copied and you paste.")
            } else {
                Text("Hushclip")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Chips

struct ChipView: View {
    let title: String
    let symbol: String
    let color: Color
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 12, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.65)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : color)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(hovering ? 0.2 : 0.11)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

// MARK: - List

struct ItemListView: View {
    @ObservedObject var model: OverlayModel
    let items: [ClipItem]
    let selectedID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(model: model, item: item, index: index, selected: item.id == selectedID)
                            .id(item.id)
                            .onTapGesture(count: 2) { model.perform(item, .paste) }
                            .simultaneousGesture(TapGesture().onEnded { model.selectedID = item.id })
                            .contextMenu {
                                Button("Paste") { model.perform(item, .paste) }
                                Button("Copy") { model.perform(item, .copy) }
                                Button(item.pinned ? "Unpin" : "Pin") { model.store.togglePin(item.id) }
                                Divider()
                                Button("Delete", role: .destructive) { model.store.delete(item.id) }
                            }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
            }
        }
    }
}

struct ItemRow: View {
    @ObservedObject var model: OverlayModel
    let item: ClipItem
    let index: Int
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ItemThumb(model: model, item: item, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.title(item, reveal: model.reveal))
                    .font(.system(size: 13, weight: .medium, design: item.category.isSensitive && !model.reveal ? .monospaced : .default))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(item.category.title).foregroundStyle(item.category.color)
                    if let app = item.sourceAppName {
                        Text("·")
                        Text(app)
                    }
                    Text("·")
                    Text(Format.relative(item.lastUsedAt))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : (hovering ? Color.primary.opacity(0.05) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct ItemThumb: View {
    @ObservedObject var model: OverlayModel
    let item: ClipItem
    let size: CGFloat

    var body: some View {
        Group {
            if item.kind == .image, let image = model.store.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomTrailing) { badge.offset(x: 4, y: 4) }
            } else if item.category == .color, let rgba = ColorParser.parse(item.text ?? "") {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a))
                    .frame(width: size, height: size)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            } else if item.kind == .files, let path = item.filePaths?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: size, height: size)
                    .overlay(alignment: .bottomTrailing) { badge.offset(x: 4, y: 4) }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.category.color.opacity(0.16))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: item.category.symbol)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(item.category.color)
                    )
            }
        }
        .frame(width: size, height: size)
    }

    private var badge: some View {
        Image(systemName: item.category.symbol)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(item.category.color))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.15)))
    }
}

// MARK: - Preview

struct PreviewPane: View {
    @ObservedObject var model: OverlayModel
    let item: ClipItem?

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                header(item)
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider().opacity(0.5)
                MetadataView(item: item)
            }
        } else {
            Color.clear
        }
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: item.category.symbol)
                Text(item.category.title)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(item.category.color.gradient))

            if item.concealed {
                Label("Concealed", systemImage: "eye.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if item.pinned {
                Label("Pinned", systemImage: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
            Spacer()
            if let name = item.sourceAppName {
                HStack(spacing: 6) {
                    if let icon = AppIcons.icon(for: item.sourceBundleID) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        if item.category.isSensitive && !model.reveal && item.kind == .text {
            VStack(spacing: 14) {
                Image(systemName: "eye.slash.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(item.category.color.gradient)
                Text(Format.mask(item))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                Text("Hold ⌥ Option to reveal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch item.kind {
            case .image:
                if let image = model.store.image(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                        .padding(18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Image unavailable").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .files:
                FilesPreview(paths: item.filePaths ?? [])
            case .text:
                textContent(item)
            }
        }
    }

    @ViewBuilder
    private func textContent(_ item: ClipItem) -> some View {
        let text = item.text ?? ""
        if item.category == .color, let rgba = ColorParser.parse(text) {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a))
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                Text(text).font(.system(size: 20, weight: .semibold, design: .monospaced)).textSelection(.enabled)
            }
            .padding(18)
        } else if item.category == .url, let url = URL(string: text) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 22))
                        .foregroundStyle(item.category.color)
                    Text(url.host ?? text)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                }
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(18)
        } else if item.category.isTechnical && text.contains(where: \.isNewline) {
            // Code keeps its line structure; scroll sideways instead of wrapping.
            ScrollView([.vertical, .horizontal]) {
                Text(String(text.prefix(20_000)))
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ScrollView {
                Text(String(text.prefix(20_000)))
                    .font(item.category.isTechnical
                          ? .system(size: 12.5, design: .monospaced)
                          : .system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            }
        }
    }
}

struct FilesPreview: View {
    let paths: [String]

    var body: some View {
        if paths.count == 1, Categorizer.imageExtensions.contains((paths[0] as NSString).pathExtension.lowercased()),
           let image = NSImage(contentsOfFile: paths[0]) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(paths, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((path as NSString).lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                Text((path as NSString).deletingLastPathComponent)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct MetadataView: View {
    let item: ClipItem

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            entry("Copied", item.createdAt.formatted(date: .abbreviated, time: .shortened))
            switch item.kind {
            case .text:
                let text = item.text ?? ""
                if !item.category.isSensitive {
                    entry("Characters", "\(text.count)")
                    entry("Words", "\(text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count)")
                    entry("Lines", "\(text.split(whereSeparator: \.isNewline).count)")
                }
            case .image:
                entry("Dimensions", "\(item.pixelWidth ?? 0) × \(item.pixelHeight ?? 0)")
            case .files:
                entry("Files", "\(item.filePaths?.count ?? 0)")
            }
            if item.useCount > 0 { entry("Pasted", "\(item.useCount)×") }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func entry(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Misc

struct EmptyStateView: View {
    let hasHistory: Bool
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasHistory ? "magnifyingglass" : "list.clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(hasHistory ? "No matches" : "Your clipboard history is empty")
                .font(.system(size: 16, weight: .semibold))
            Text(hasHistory
                 ? (query.isEmpty ? "Nothing in this category yet." : "Nothing matches “\(query)”.")
                 : "Copy something and it will show up here, encrypted.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.09)))
            Text(label)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
}
