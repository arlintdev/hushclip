import AppKit
import HushclipCore
import Combine

/// View state for the overlay: search, category filter, selection.
@MainActor
final class OverlayModel: ObservableObject {
    enum Filter: Hashable {
        case all, pinned
        case category(ClipCategory)
    }

    enum Action { case paste, copy }

    struct CategoryCount: Identifiable {
        let category: ClipCategory
        let count: Int
        var id: ClipCategory { category }
    }

    @Published var query = ""
    @Published var filter: Filter = .all
    @Published var selectedID: UUID?
    @Published var reveal = false
    /// The full-screen preview (Space / ⌘Y) is open.
    @Published var enlarged = false
    @Published var focusToken = 0
    @Published var accessibilityTrusted = Paster.isTrusted

    let store: ClipStore
    var perform: (ClipItem, Action) -> Void = { _, _ in }
    var runAction: (ClipItem, QuickAction) -> Void = { _, _ in }
    var showActionsMenu: () -> Void = {}
    var openSettings: () -> Void = {}
    private var cancellables: Set<AnyCancellable> = []
    private var actionCache: [UUID: [QuickAction]] = [:]

    init(store: ClipStore) {
        self.store = store
        // Re-render when the store changes.
        store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    var filtered: [ClipItem] {
        store.items.filter { item in
            switch filter {
            case .all: true
            case .pinned: item.pinned
            case .category(let c): item.category == c
            }
        }.filter { $0.matches(query) }
    }

    var selectedItem: ClipItem? {
        let items = filtered
        return items.first { $0.id == selectedID } ?? items.first
    }

    var categoryCounts: [CategoryCount] {
        var counts: [ClipCategory: Int] = [:]
        for item in store.items { counts[item.category, default: 0] += 1 }
        return ClipCategory.allCases.compactMap { c in counts[c].map { CategoryCount(category: c, count: $0) } }
    }

    var pinnedCount: Int { store.items.filter(\.pinned).count }

    func reset() {
        query = ""
        filter = .all
        selectedID = store.items.first?.id
        reveal = false
        enlarged = false
        accessibilityTrusted = Paster.isTrusted
        focusToken += 1
    }

    func moveSelection(_ delta: Int) {
        let items = filtered
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedItem?.id } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        selectedID = items[next].id
    }

    func cycleFilter(forward: Bool) {
        var options: [Filter] = [.all]
        if pinnedCount > 0 { options.append(.pinned) }
        options += categoryCounts.map { .category($0.category) }
        let index = options.firstIndex(of: filter) ?? 0
        filter = options[(index + (forward ? 1 : options.count - 1)) % options.count]
        selectedID = filtered.first?.id
    }

    func setFilter(_ newFilter: Filter) {
        filter = newFilter
        selectedID = filtered.first?.id
    }

    func activate(_ action: Action) {
        guard let item = selectedItem else { return }
        perform(item, action)
    }

    func activate(index: Int) {
        let items = filtered
        guard items.indices.contains(index) else { return }
        perform(items[index], .paste)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        let items = filtered
        let index = items.firstIndex { $0.id == item.id } ?? 0
        store.delete(item.id)
        let remaining = filtered
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    /// Quick actions for a clip (cached: a clip's content never changes, and some
    /// actions, like reformatting JSON, aren't free to compute on every redraw).
    func actions(for item: ClipItem) -> [QuickAction] {
        if let cached = actionCache[item.id] { return cached }
        if actionCache.count > 300 { actionCache.removeAll() }
        let actions = QuickActions.actions(for: item, home: Self.realHome)
        actionCache[item.id] = actions
        return actions
    }

    func primaryAction(for item: ClipItem) -> QuickAction? {
        actions(for: item).first(where: \.opens)
    }

    /// ⌘O: open the selected link, email, number, file…
    func openSelected() {
        guard let item = selectedItem, let action = primaryAction(for: item) else {
            NSSound.beep()
            return
        }
        runAction(item, action)
    }

    /// The user's home folder. Inside the App Sandbox `NSHomeDirectory()` is the app's container.
    static let realHome: String = {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }()

    /// Space / ⌘Y: open or close the full-screen preview of the selected clip.
    func toggleEnlarged() {
        if enlarged { enlarged = false; return }
        guard let item = selectedItem, canEnlarge(item) else { NSSound.beep(); return }
        enlarged = true
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        store.togglePin(item.id)
    }
}
