import Foundation
import Observation

/// One app's page, or one leftover group's page. Entries are read live from the store, so they
/// disappear as soon as they're moved to the Trash.
@MainActor
@Observable
final class AppDetailViewModel {
    let route: AppsViewModel.Route
    private let store: ScanStore
    var selected: Set<String> = []
    var review: ReviewViewModel?

    init(route: AppsViewModel.Route, store: ScanStore) {
        self.route = route
        self.store = store
        // Pre-select only what's safe. The app itself and your data are never pre-selected.
        selected = Set(entries.filter { $0.safety == .safe }.map(\.path))
    }

    var app: AppInfo? {
        if case .app(let id) = route { return store.footprint(id: id)?.app }
        return nil
    }

    var title: String {
        switch route {
        case .app(let id): store.footprint(id: id)?.app.name ?? "App"
        case .leftover(let id): store.leftover(id: id)?.displayName ?? "Leftover"
        }
    }

    var subtitle: String {
        switch route {
        case .app(let id):
            guard let app = store.footprint(id: id)?.app else { return "" }
            return [app.bundleID, app.version.map { "Version \($0)" }].compactMap { $0 }.joined(separator: " · ")
        case .leftover(let id):
            return "\(store.leftover(id: id)?.identifier ?? id) · no installed app uses this data"
        }
    }

    var iconPath: String? { app?.url.path }

    var entries: [FootprintEntry] {
        switch route {
        case .app(let id): store.footprint(id: id)?.entries ?? []
        case .leftover(let id): store.leftover(id: id)?.entries ?? []
        }
    }

    var total: Int64 { entries.reduce(0) { $0 + $1.size } }

    /// Entries grouped by kind, largest group first.
    var groups: [(kind: FootprintKind, entries: [FootprintEntry])] {
        Dictionary(grouping: entries, by: \.kind)
            .map { (kind: $0.key, entries: $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.entries.reduce(0) { $0 + $1.size } > $1.entries.reduce(0) { $0 + $1.size } }
    }

    func isSelectable(_ entry: FootprintEntry) -> Bool { entry.safety != .infoOnly }

    var selectedEntries: [FootprintEntry] { entries.filter { selected.contains($0.path) } }
    var selectedSize: Int64 { selectedEntries.reduce(0) { $0 + $1.size } }

    func toggle(_ entry: FootprintEntry) {
        if selected.contains(entry.path) { selected.remove(entry.path) } else { selected.insert(entry.path) }
    }

    /// Selects everything that can be removed: a full uninstall, including the app itself.
    func selectEverything() {
        selected = Set(entries.filter(isSelectable).map(\.path))
    }

    func startReview() {
        let items = selectedEntries.map { CleanupItem(entry: $0, app: app) }
        review = ReviewViewModel(items: items, store: store)
    }
}
