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

    enum Route: Hashable {
        case app(id: String)
        case leftover(id: String)
    }

    var filter: Filter = .all
    var path: [Route] = []

    private let store: ScanStore

    init(store: ScanStore) {
        self.store = store
    }

    var hasResult: Bool { store.attribution != nil }

    /// Apps, largest first. Apple apps that keep no data of their own are left out.
    var footprints: [AppFootprint] {
        var list = store.attribution?.footprints ?? []
        list.removeAll { $0.app.isSystemApp && $0.dataSize == 0 }
        if filter == .background { list.removeAll { $0.backgroundItems.isEmpty } }
        return list.sorted { $0.totalSize > $1.totalSize }
    }

    var leftovers: [LeftoverGroup] { store.attribution?.leftovers ?? [] }

    var largestTotal: Int64 { footprints.map(\.totalSize).max() ?? 1 }

    /// The saved summary of the last scan. Shown before a new scan has run in this session.
    var lastSnapshot: ScanSnapshot? { store.lastSnapshot }

    /// Apps from the last scan's summary, largest first.
    var snapshotApps: [SnapshotApp] { store.lastSnapshotApps }

    var isScanning: Bool { store.phase.isWorking }
    var scanTitle: String { store.phase.title }

    func startScan() { store.startScan() }
    func cancelScan() { store.cancelScan() }

    func detailModel(for route: Route) -> AppDetailViewModel {
        AppDetailViewModel(route: route, store: store)
    }
}
