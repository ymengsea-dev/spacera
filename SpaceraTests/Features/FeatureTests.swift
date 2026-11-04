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

@MainActor
struct OnboardingTests {
    func store(_ world: World, access: Bool) async -> ScanStore {
        var services = world.store.services
        services.access = FakeAccess(granted: access)
        let store = ScanStore(services: services)
        await store.loadLastSnapshot()
        return store
    }

    @Test func promptsWhenAccessWasRevokedAfterAFullScan() async throws {
        let world = try await World(access: true)
        let model = OnboardingViewModel(store: await store(world, access: false))
        model.presentIfNeeded()
        #expect(model.isPresented)
    }

    @Test func doesNotNagAfterTheUserChoseALimitedScan() async throws {
        let world = try await World(access: false)
        let model = OnboardingViewModel(store: await store(world, access: false))
        model.presentIfNeeded()
        #expect(!model.isPresented)
    }

    @Test func staysHiddenWithAccess() async throws {
        let world = try await World(access: true)
        let model = OnboardingViewModel(store: await store(world, access: true))
        model.presentIfNeeded()
        #expect(!model.isPresented)
    }
}

@MainActor
struct DiskMapViewModelTests {
    @Test func listMatchesThePlanAndThePlanIsReused() async throws {
        let world = try await World()
        let model = DiskMapViewModel(store: world.store)
        let plan = try #require(model.plan)
        #expect(plan.folder === world.store.result?.root)
        #expect(model.children.map(\.id) == plan.children.map(\.id))
        #expect(model.plan?.children.map(\.id) == plan.children.map(\.id))
    }
}

struct TreemapLayoutTests {
    @Test func areasAreProportionalAndFillTheBounds() async throws {
        let tree = try TempTree()
        try tree.file("big/a.bin", bytes: 3_000_000)
        try tree.file("small/c.bin", bytes: 1_000_000)
        let root = try await DiskScanner().scanTree(root: tree.root).root
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

        let tiles = TreemapLayout.make(root: root, in: bounds)
        #expect(tiles.map(\.title) == ["big", "small"])
        #expect(tiles.map(\.colorIndex) == [0, 1])
        let areas = tiles.map { Double($0.rect.width * $0.rect.height) }
        #expect(abs(areas.reduce(0, +) - 400 * 300) < 1)
        #expect(abs(areas[0] / areas[1] - Double(tiles[0].size) / Double(tiles[1].size)) < 0.001)
        #expect(tiles.allSatisfy { bounds.insetBy(dx: -0.01, dy: -0.01).contains($0.rect) })
    }

    @Test func tilesDoNotOverlap() async throws {
        let tree = try TempTree()
        for i in 1...12 { try tree.file("f\(i).bin", bytes: 1_000_000 * i) }
        let root = try await DiskScanner().scanTree(root: tree.root).root

        let tiles = TreemapLayout.make(root: root, in: CGRect(x: 0, y: 0, width: 500, height: 320), minShare: 0)
        #expect(tiles.count == 12)
        for (i, a) in tiles.enumerated() {
            for b in tiles[(i + 1)...] {
                let overlap = a.rect.intersection(b.rect)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func tinyItemsAreMerged() async throws {
        let tree = try TempTree()
        try tree.file("huge.bin", bytes: 50_000_000)
        for i in 0..<5 { try tree.file("tiny\(i).bin", bytes: 300_000) }
        let root = try await DiskScanner().scanTree(root: tree.root).root

        let tiles = TreemapLayout.make(root: root, in: CGRect(x: 0, y: 0, width: 200, height: 200), minShare: 0.01)
        let merged = try #require(tiles.first { $0.node == nil })
        #expect(merged.mergedCount == 5)
        #expect(merged.colorIndex == -1)
        #expect(tiles.count == 2)
    }

    @Test func manySimilarItemsKeepTheirOwnBlocks() async throws {
        // 300 equal folders are each under 0.4% of the parent, but none is small next to the others.
        let tree = try TempTree()
        for i in 0..<300 { try tree.file("d\(i)/f.bin", bytes: 100_000) }
        let root = try await DiskScanner().scanTree(root: tree.root).root

        let plan = TreemapPlan(folder: root, maxTiles: 500)
        #expect(plan.shownCount == 300)
        #expect(plan.mergedSize == 0)
        #expect(TreemapLayout.tiles(for: plan, in: CGRect(x: 0, y: 0, width: 600, height: 400)).allSatisfy { $0.node != nil })
    }

    @Test func aSingleSmallItemIsNotMergedAlone() async throws {
        let tree = try TempTree()
        try tree.file("huge.bin", bytes: 50_000_000)
        try tree.file("tiny.bin", bytes: 300_000)
        let root = try await DiskScanner().scanTree(root: tree.root).root

        let plan = TreemapPlan(folder: root, minShare: 0.01)
        #expect(plan.shownCount == 2)
        #expect(plan.mergedCount == 0)
    }

    @Test func planMarksMergedChildrenForTheList() async throws {
        let tree = try TempTree()
        try tree.file("huge.bin", bytes: 50_000_000)
        for i in 0..<5 { try tree.file("tiny\(i).bin", bytes: 300_000) }
        let root = try await DiskScanner().scanTree(root: tree.root).root

        let plan = TreemapPlan(folder: root, minShare: 0.01)
        #expect(plan.mergedCount == 5)
        #expect(plan.children.map(\.name).first == "huge.bin")
        #expect(!plan.isMerged(plan.children[0]))
        #expect(plan.children.dropFirst().allSatisfy(plan.isMerged))
        #expect(plan.mergedSize == plan.children.dropFirst().reduce(0) { $0 + $1.size })
    }

    @Test func hitTestFindsTheBlockUnderThePoint() async throws {
        let tree = try TempTree()
        try tree.file("a.bin", bytes: 1_000_000)
        try tree.file("b.bin", bytes: 1_000_000)
        let root = try await DiskScanner().scanTree(root: tree.root).root
        let tiles = TreemapLayout.make(root: root, in: CGRect(x: 0, y: 0, width: 200, height: 100))

        // Two equal files in a wide box sit side by side.
        #expect(TreemapLayout.hitTest(tiles, point: CGPoint(x: 50, y: 50))?.rect.minX == 0)
        #expect(TreemapLayout.hitTest(tiles, point: CGPoint(x: 150, y: 50))?.rect.minX == 100)
        #expect(TreemapLayout.hitTest(tiles, point: CGPoint(x: 250, y: 50)) == nil)
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
    @Test func savedSnapshotAppsKeepIconsOnlyForInstalledApps() async throws {
        let world = try await World()
        let fresh = ScanStore(services: world.store.services)
        await fresh.loadLastSnapshot()
        let zeta = try #require(fresh.lastSnapshotApps.first)
        #expect(zeta.summary.name == "Zeta")
        #expect(zeta.iconPath == world.app.url.path)

        try FileManager.default.removeItem(at: world.app.url) // a temporary fixture, not user data
        let later = ScanStore(services: world.store.services)
        await later.loadLastSnapshot()
        #expect(later.lastSnapshotApps.first?.iconPath == nil)
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
