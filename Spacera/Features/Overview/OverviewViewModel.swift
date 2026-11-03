import Observation
import SwiftUI

@MainActor
@Observable
final class OverviewViewModel {
    struct Slice: Identifiable, Equatable {
        var id: String
        var title: String
        var bytes: Int64
        var color: Color
    }

    private let store: ScanStore

    init(store: ScanStore) {
        self.store = store
    }

    var hasResult: Bool { store.result != nil }
    var isLimitedScan: Bool { store.isLimitedScan }
    var volume: VolumeInfo? { store.result?.volume }
    var trashedSinceScan: Int64 { store.trashedSinceScan }

    /// The disk split into parts that don't overlap, so the bar adds up to the disk's capacity.
    var slices: [Slice] {
        guard let result = store.result, let attribution = store.attribution else { return [] }
        let volume = result.volume
        let footprints = attribution.footprints.filter { !$0.app.isSystemApp }
        let apps = footprints.reduce(0) { $0 + $1.bundleSize }
        let appData = attribution.footprints.reduce(0) { $0 + $1.dataSize }
            + attribution.leftovers.reduce(0) { $0 + $1.totalSize }

        // Your files: the home folder minus the app data inside it.
        let homePath = ScanResult.logicalPath(store.services.locations.home.path)
        let homeSize = result.node(atPath: homePath)?.size ?? 0
        let appDataInHome = (attribution.footprints.flatMap(\.entries) + attribution.leftovers.flatMap(\.entries))
            .filter { $0.kind != .bundle && $0.path.hasPrefix(homePath + "/") }
            .reduce(0) { $0 + $1.size }
        let appBundlesInHome = footprints.filter { $0.app.url.path.hasPrefix(homePath + "/") }.reduce(0) { $0 + $1.bundleSize }
        let yourFiles = max(0, homeSize - appDataInHome - appBundlesInHome)

        let system = max(0, volume.usedCapacity - apps - appData - yourFiles)
        return [
            Slice(id: "apps", title: "Apps", bytes: apps, color: .blue),
            Slice(id: "appData", title: "App Data", bytes: appData, color: .purple),
            Slice(id: "files", title: "Your Files", bytes: yourFiles, color: .orange),
            Slice(id: "system", title: "System & Other", bytes: system, color: .gray),
            Slice(id: "free", title: "Free", bytes: volume.availableCapacity, color: Color(nsColor: .quaternaryLabelColor)),
        ]
    }

    var topApps: [AppFootprint] {
        Array((store.attribution?.footprints ?? []).filter { $0.totalSize > 0 }.prefix(6))
    }

    var safeReclaimable: Int64 {
        store.findings.filter { $0.rule.safety == .safe }.reduce(0) { $0 + $1.totalSize }
    }

    var leftoverSize: Int64 { store.attribution?.leftovers.reduce(0) { $0 + $1.totalSize } ?? 0 }
    var leftoverCount: Int { store.attribution?.leftovers.count ?? 0 }
    var orphanedBackgroundItems: Int {
        store.attribution?.leftovers.flatMap(\.entries).filter { $0.kind == .backgroundItem }.count ?? 0
    }

    var topFindings: [RuleFinding] {
        Array(store.findings.filter { $0.rule.safety != .infoOnly }.sorted { $0.totalSize > $1.totalSize }.prefix(4))
    }

    var growth: GrowthReport? { store.growth }
    var lastSnapshot: ScanSnapshot? { store.lastSnapshot }

    var hasGrowthToShow: Bool {
        guard let growth else { return false }
        return !growth.apps.isEmpty || !growth.categories.isEmpty || abs(growth.usedDelta) >= GrowthReport.threshold
    }

    func startScan() { store.startScan() }
}
