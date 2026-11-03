import Foundation
import Testing
@testable import Spacera

// MARK: - Fakes

struct FakeScanner: DiskScanning {
    var result: ScanResult
    func scan(root: URL, options: ScanOptions) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.progress(ScanProgress(bytes: 1, files: 1, directories: 1, currentPath: root.path)))
            continuation.yield(.finished(result))
            continuation.finish()
        }
    }
}

struct FakeCatalog: AppCataloging {
    var apps: [AppInfo]
    func discoverApps() async -> [AppInfo] { apps }
}

struct FakeAccess: FullDiskAccessChecking {
    var granted: Bool
    func hasFullDiskAccess() -> Bool { granted }
}

/// A small but real world: a fake home with one app, its data, a cache, and a leftover.
@MainActor
struct World {
    let tree: TempTree
    let store: ScanStore
    let app: AppInfo

    init(access: Bool = true) async throws {
        tree = try TempTree()
        let appURL = try tree.app("Applications/Zeta.app", bundleID: "io.zeta.editor", name: "Zeta", bytes: 2_000_000)
        try tree.file("home/Library/Containers/io.zeta.editor/Data/doc.bin", bytes: 3_000_000)
        try tree.file("home/Library/Caches/io.zeta.editor/cache.bin", bytes: 1_000_000)
        try tree.file("home/Library/Caches/com.gone.app/old.bin", bytes: 500_000)
        try tree.file("home/Documents/report.pdf", bytes: 4_000_000)
        try tree.file("home/Library/Developer/Xcode/DerivedData/Proj/x.o", bytes: 800_000)

        let scanned = try await DiskScanner().scanTree(root: tree.root)
        let volume = VolumeInfo(name: "Test HD", totalCapacity: 100_000_000, availableCapacity: 40_000_000, availableForImportantUsage: 45_000_000)
        let result = ScanResult(root: scanned.root, volume: volume, date: Date(), duration: 0, unreadablePaths: [])
        app = AppCatalog.readApp(at: appURL, isSystem: false)!

        let locations = LibraryLocations(home: tree.url("home"), systemLibrary: tree.url("sys/Library"))
        let log = ActionLog(fileURL: tree.url("log/actions.json"))
        let guardrail = SafetyGuardTests.testGuard(tree)
        let services = Services(
            locations: locations,
            scanner: FakeScanner(result: result),
            catalog: FakeCatalog(apps: [app]),
            resolver: AppFootprintResolver(locations: locations, overrides: []),
            commands: FakeCommands(),
            planner: CleanupPlanner(guardrail: guardrail, runningApps: FakeRunningApps(ids: [])),
            trasher: Trasher(guardrail: guardrail, log: log),
            log: log,
            snapshots: ScanSnapshotStore(fileURL: tree.url("log/snapshots.json")),
            access: FakeAccess(granted: access)
        )
        store = ScanStore(services: services)
        store.startScan()
        await store.waitForScan()
    }
}

// MARK: - Tests

@MainActor
struct ScanStoreTests {
    @Test func scanRunsAllThreeStages() async throws {
        let world = try await World()
        #expect(world.store.phase == .done)
        #expect(world.store.result != nil)
        #expect(world.store.attribution?.footprints.first?.app.bundleID == "io.zeta.editor")
        #expect(world.store.attribution?.leftovers.map(\.identifier) == ["com.gone.app"])
        #expect(world.store.findings.contains { $0.rule.id == "xcode.derivedData" })
        #expect(world.store.isLimitedScan == false)
    }

    @Test func limitedScanWithoutFullDiskAccess() async throws {
        let world = try await World(access: false)
        #expect(world.store.isLimitedScan)
    }

    @Test func didTrashRemovesItemsEverywhere() async throws {
        let world = try await World()
        let cachePath = world.tree.url("home/Library/Caches/io.zeta.editor").path
        let item = CleanupItem(path: cachePath, size: 1_000_000, ruleID: "t", safety: .safe)
        let batch = TrashBatch(id: UUID(), date: Date(), outcomes: [TrashOutcome(item: item, status: .trashed, trashPath: "/x/.Trash/y")])

        world.store.didTrash(batch)

        #expect(!(world.store.footprint(id: world.app.id)?.entries.contains { $0.path == cachePath } ?? true))
        #expect(!world.store.findings.flatMap(\.items).contains { $0.path == cachePath })
        #expect(world.store.trashedSinceScan == 1_000_000)
    }
}

@MainActor
struct OverviewViewModelTests {
    @Test func slicesDoNotOverlapAndAddUpToCapacity() async throws {
        let world = try await World()
        let model = OverviewViewModel(store: world.store)
        let slices = model.slices
        let byID = Dictionary(uniqueKeysWithValues: slices.map { ($0.id, $0.bytes) })

        #expect(slices.map(\.id) == ["apps", "appData", "files", "system", "free"])
        #expect(byID["apps"]! > 0)
        #expect(byID["appData"]! > 3_000_000)
        #expect(byID["files"]! >= 4_000_000) // Documents/report.pdf, not counted as app data
        #expect(slices.reduce(0) { $0 + $1.bytes } == 100_000_000)
        #expect(model.topApps.first?.app.name == "Zeta")
        #expect(model.safeReclaimable > 0)
    }
}

@MainActor
struct CleanupViewModelTests {
    @Test func preselectsOnlySafeItemsAndReviewsSelection() async throws {
        let world = try await World()
        let model = CleanupViewModel(store: world.store)
        model.syncSelection()

        let selectedRules = Set(world.store.findings.filter { f in f.items.contains { model.selected.contains($0.path) } }.map(\.rule.safety))
        #expect(selectedRules == [.safe])
        // A deleted app's *cache* is still just a cache: reported (and pre-selected) as App Caches.
        // Its other data stays under Leftovers, which is never pre-selected.
        #expect(world.store.findings.first { $0.rule.id == "system.userCaches" }?.items.contains { $0.name == "com.gone.app" } == true)
        #expect(world.store.findings.first { $0.rule.id == "leftovers" }.map { $0.items.allSatisfy { !model.selected.contains($0.path) } } ?? true)

        let derived = try #require(world.store.findings.first { $0.rule.id == "xcode.derivedData" })
        model.toggleAll(in: derived)
        #expect(model.selectionState(of: derived) == .none)
        model.toggleAll(in: derived)
        #expect(model.selectionState(of: derived) == .all)

        model.startReview()
        #expect(model.review?.plan.entries.count == model.selectedItems.count)
    }

    @Test func reviewMovesToTrashAndUpdatesStore() async throws {
        let world = try await World()
        let path = world.tree.url("home/Library/Developer/Xcode/DerivedData/Proj").path
        let review = ReviewViewModel(items: [CleanupItem(path: path, size: 800_000, ruleID: "xcode.derivedData", safety: .safe)], store: world.store)
        #expect(review.canConfirm)

        await review.moveToTrash()

        guard case .done(let batch) = review.stage else { Issue.record("expected done"); return }
        #expect(batch.outcomes.first?.status == .trashed)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(!world.store.findings.contains { $0.rule.id == "xcode.derivedData" })
        if let trashPath = batch.outcomes.first?.trashPath { try? FileManager.default.removeItem(atPath: trashPath) }
    }

    @Test func userDataNeedsConfirmation() async throws {
        let world = try await World()
        let item = CleanupItem(path: world.tree.url("home/Documents/report.pdf").path, size: 4_000_000, ruleID: "user.largeFiles", safety: .userData)
        let review = ReviewViewModel(items: [item], store: world.store)
        #expect(!review.canConfirm)
        review.confirmedUserData = true
        #expect(review.canConfirm)
    }
}

@MainActor
struct AppDetailViewModelTests {
    @Test func preselectsSafeEntriesButNeverTheAppOrItsData() async throws {
        let world = try await World()
        let model = AppDetailViewModel(route: .app(id: world.app.id), store: world.store)

        let selectedKinds = Set(model.selectedEntries.map(\.kind))
        #expect(selectedKinds == [.cache])
        model.selectEverything()
        #expect(Set(model.selectedEntries.map(\.kind)) == [.bundle, .container, .cache])
        #expect(model.title == "Zeta")
    }
}

struct SunburstLayoutTests {
    @Test func anglesAreProportionalAndNested() async throws {
        let tree = try TempTree()
        try tree.file("big/a.bin", bytes: 3_000_000)
        try tree.file("big/b.bin", bytes: 1_000_000)
        try tree.file("small/c.bin", bytes: 1_000_000)
        let root = try await DiskScanner().scanTree(root: tree.root).root

        let arcs = SunburstLayout.make(root: root)
        let ring1 = arcs.filter { $0.depth == 1 }
        #expect(ring1.map(\.title) == ["big", "small"])
        #expect(abs(ring1.reduce(0) { $0 + $1.span } - 2 * .pi) < 0.0001)

        let big = ring1[0]
        let ring2 = arcs.filter { $0.depth == 2 && $0.start >= big.start - 1e-9 && $0.end <= big.end + 1e-9 }
        #expect(ring2.map(\.title) == ["a.bin", "b.bin"])
        #expect(ring2.allSatisfy { $0.colorIndex == big.colorIndex })
    }

    @Test func tinyItemsAreMerged() async throws {
        let tree = try TempTree()
        try tree.file("huge.bin", bytes: 50_000_000)
        for i in 0..<5 { try tree.file("tiny\(i).bin", bytes: 300_000) }
        let root = try await DiskScanner().scanTree(root: tree.root).root

        let arcs = SunburstLayout.make(root: root, minAngle: 2 * .pi / 100) // anything under 1% is merged
        let merged = try #require(arcs.first { $0.node == nil })
        #expect(merged.mergedCount == 5)
        #expect(arcs.filter { $0.depth == 1 }.count == 2)
    }

    @Test func hitTestFindsTheRightRing() async throws {
        let tree = try TempTree()
        try tree.file("only/one.bin", bytes: 1_000_000)
        let root = try await DiskScanner().scanTree(root: tree.root).root
        let arcs = SunburstLayout.make(root: root)
        let center = CGPoint(x: 100, y: 100)

        // Straight up from the centre, in the first ring (radius 20 to 30).
        let hit = SunburstLayout.hitTest(arcs, point: CGPoint(x: 100, y: 75), center: center, innerRadius: 20, ringWidth: 10)
        #expect(hit?.title == "only")
        let second = SunburstLayout.hitTest(arcs, point: CGPoint(x: 100, y: 65), center: center, innerRadius: 20, ringWidth: 10)
        #expect(second?.title == "one.bin")
        #expect(SunburstLayout.hitTest(arcs, point: center, center: center, innerRadius: 20, ringWidth: 10) == nil)
    }
}

struct SnapshotTests {
    func snapshot(date: Date, used: Int64, apps: [(String, Int64)], categories: [(String, Int64)] = [], limited: Bool = false) -> ScanSnapshot {
        ScanSnapshot(
            id: UUID(), date: date,
            volume: VolumeInfo(name: "HD", totalCapacity: 1_000_000_000_000, availableCapacity: 1_000_000_000_000 - used, availableForImportantUsage: 1_000_000_000_000 - used),
            isLimitedScan: limited,
            apps: apps.map { .init(key: $0.0, name: $0.0, path: "/Applications/\($0.0).app", bundleSize: 0, dataSize: $0.1) },
            categories: categories.map { .init(ruleID: $0.0, title: $0.0, bytes: $0.1) },
            leftoverBytes: 0, safeReclaimable: 0
        )
    }

    @Test func growthReportsChangesAboveThreshold() {
        let old = snapshot(date: Date(timeIntervalSince1970: 0), used: 500_000_000_000,
                           apps: [("grows", 1_000_000_000), ("same", 2_000_000_000), ("shrinks", 3_000_000_000), ("removed", 900_000_000)],
                           categories: [("xcode.derivedData", 10_000_000_000)])
        let new = snapshot(date: Date(timeIntervalSince1970: 100), used: 505_000_000_000,
                           apps: [("grows", 4_000_000_000), ("same", 2_010_000_000), ("shrinks", 1_000_000_000), ("added", 700_000_000)],
                           categories: [("xcode.derivedData", 15_000_000_000)])

        let report = GrowthReport.compare(previous: old, current: new)

        #expect(report.usedDelta == 5_000_000_000)
        #expect(report.apps.map(\.id) == ["grows", "added", "removed", "shrinks"])
        #expect(report.apps.first { $0.id == "added" }?.isNew == true)
        #expect(report.apps.first { $0.id == "removed" }?.delta == -900_000_000)
        #expect(report.categories.map(\.delta) == [5_000_000_000])
        #expect(!report.comparesDifferentScopes)
    }

    @Test func storeKeepsNewestAndPersists() async throws {
        let tree = try TempTree()
        let url = tree.url("snapshots.json")
        let store = ScanSnapshotStore(fileURL: url)
        for i in 0..<(ScanSnapshotStore.maxSnapshots + 5) {
            await store.append(snapshot(date: Date(timeIntervalSince1970: Double(i)), used: 1, apps: []))
        }
        let reloaded = ScanSnapshotStore(fileURL: url)
        #expect(await reloaded.all().count == ScanSnapshotStore.maxSnapshots)
        #expect(await reloaded.latest()?.date == Date(timeIntervalSince1970: Double(ScanSnapshotStore.maxSnapshots + 4)))
    }

    @MainActor
    @Test func secondScanProducesGrowthReport() async throws {
        let world = try await World()
        #expect(world.store.growth == nil) // first scan: nothing to compare with
        #expect(world.store.lastSnapshot?.apps.first?.name == "Zeta")

        world.store.startScan()
        await world.store.waitForScan()
        let growth = try #require(world.store.growth)
        #expect(growth.apps.isEmpty) // nothing changed

        let fresh = ScanStore(services: world.store.services)
        await fresh.loadLastSnapshot()
        #expect(fresh.lastSnapshot != nil) // available at the next launch
    }
}
