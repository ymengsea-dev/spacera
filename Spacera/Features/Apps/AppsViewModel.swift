import Foundation
import Observation

@MainActor
@Observable
final class AppsViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All Apps"
        case leftovers = "Leftovers"
        case background = "Background Items"
        var id: Self { self }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case total = "Total Size"
        case data = "Data Size"
        case name = "Name"
        var id: Self { self }
    }

    enum Route: Hashable {
        case app(id: String)
        case leftover(id: String)
    }

    var search = ""
    var filter: Filter = .all
    var sort: Sort = .total
    var showSystemApps = false
    var path: [Route] = []

    private let store: ScanStore

    init(store: ScanStore) {
        self.store = store
    }

    var hasResult: Bool { store.attribution != nil }

    var footprints: [AppFootprint] {
        var list = store.attribution?.footprints ?? []
        if !showSystemApps { list.removeAll { $0.app.isSystemApp && $0.dataSize == 0 } }
        if filter == .background { list.removeAll { $0.backgroundItems.isEmpty } }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter { $0.app.name.localizedCaseInsensitiveContains(query) || ($0.app.bundleID ?? "").localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .total: list.sort { $0.totalSize > $1.totalSize }
        case .data: list.sort { $0.dataSize > $1.dataSize }
        case .name: list.sort { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
        }
        return list
    }

    var leftovers: [LeftoverGroup] {
        var list = store.attribution?.leftovers ?? []
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter { $0.displayName.localizedCaseInsensitiveContains(query) || $0.identifier.localizedCaseInsensitiveContains(query) }
        }
        if sort == .name { list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }
        return list
    }

    var largestTotal: Int64 { footprints.map(\.totalSize).max() ?? 1 }

    func detailModel(for route: Route) -> AppDetailViewModel {
        AppDetailViewModel(route: route, store: store)
    }
}
