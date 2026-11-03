import Foundation
import Testing
@testable import Spacera

struct FakeCommands: CommandRunning {
    var outputs: [String: String] = [:]
    func run(_ executable: String, _ arguments: [String]) -> String? {
        outputs[([executable] + arguments).joined(separator: " ")]
    }
}

struct FakeRunningApps: RunningAppsProviding {
    var ids: Set<String>
    func runningBundleIDs() -> Set<String> { ids }
}

struct CleanupRuleTests {
    func context(_ tree: TempTree, now: Date = Date(), commands: FakeCommands = FakeCommands(),
                 attribution: AttributionResult? = nil) async throws -> RuleContext {
        let scan = try await DiskScanner().scanTree(root: tree.root)
        return RuleContext(
            locations: LibraryLocations(home: tree.url("home"), systemLibrary: tree.url("sys/Library")),
            scan: scan, attribution: attribution, now: now, commands: commands
        )
    }

    func run(_ rules: [CleanupRule], _ ctx: RuleContext) async -> [String: [CleanupItem]] {
        let findings = await CleanupRuleEngine(rules: rules).run(ctx)
        return Dictionary(uniqueKeysWithValues: findings.map { ($0.rule.id, $0.items) })
    }

    @Test func developerRulesFindXcodeAndPackageCaches() async throws {
        let tree = try TempTree()
        try tree.file("home/Library/Developer/Xcode/DerivedData/App-abc/Build/x.o", bytes: 900_000)
        try tree.file("home/Library/Developer/Xcode/DerivedData/Lib-def/Build/y.o", bytes: 400_000)
        try tree.file("home/Library/Developer/Xcode/iOS DeviceSupport/18.0 (22A)/sym.bin", bytes: 600_000)
        try tree.file("home/Library/Developer/Xcode/Archives/2025-10-01/App 1.xcarchive/a.bin", bytes: 300_000)
        try tree.file("home/Library/Caches/Homebrew/downloads/pkg.tar", bytes: 700_000)
        try tree.file("home/.npm/_cacache/content/blob", bytes: 500_000)

        let found = await run(BuiltinRules.all, try await context(tree))

        #expect(found["xcode.derivedData"]?.map(\.name) == ["App-abc", "Lib-def"])
        #expect(found["xcode.derivedData"]?.allSatisfy { $0.safety == .safe && $0.ownerBundleID == "com.apple.dt.Xcode" } == true)
        #expect(found["xcode.deviceSupport"]?.map(\.name) == ["18.0 (22A)"])
        #expect(found["xcode.archives"]?.map(\.name) == ["App 1.xcarchive"])
        #expect(Set(found["dev.packageCaches"]?.compactMap(\.note) ?? []) == ["Homebrew", "npm"])
        // Homebrew's cache is inside ~/Library/Caches, but it's reported once, as a package cache.
        #expect(found["system.userCaches"]?.contains { $0.name == "Homebrew" } != true)
    }

    @Test func nodeModulesOnlyOutermostAndNotInLibrary() async throws {
        let tree = try TempTree()
        try tree.file("home/code/web/node_modules/react/index.js", bytes: 400_000)
        try tree.file("home/code/web/node_modules/react/node_modules/dep/i.js", bytes: 400_000)
        try tree.file("home/Library/Application Support/SomeApp/node_modules/x.js", bytes: 400_000)

        let found = await run([BuiltinRules.nodeModules], try await context(tree))

        let items = try #require(found["dev.nodeModules"])
        #expect(items.count == 1)
        #expect(items[0].path.hasSuffix("code/web/node_modules"))
        #expect(items[0].note == "web")
    }

    @Test func cachesAndLogsGetOwnersFromBundleIDNames() async throws {
        let tree = try TempTree()
        try tree.file("home/Library/Caches/com.vendor.app/c.bin", bytes: 400_000)
        try tree.file("home/Library/Caches/SomeFolder/c.bin", bytes: 400_000)
        try tree.file("home/Library/Logs/com.vendor.app/log.txt", bytes: 400_000)

        let found = await run(BuiltinRules.all, try await context(tree))

        let caches = try #require(found["system.userCaches"])
        #expect(caches.first { $0.name == "com.vendor.app" }?.ownerBundleID == "com.vendor.app")
        #expect(caches.first { $0.name == "SomeFolder" }?.ownerBundleID == nil)
        #expect(found["system.userLogs"]?.count == 1)
    }

    @Test func oldDownloadsUseModificationDate() async throws {
        let tree = try TempTree()
        let old = try tree.file("home/Downloads/installer.dmg", bytes: 400_000)
        try tree.file("home/Downloads/recent.pdf", bytes: 400_000)
        let longAgo = Date().addingTimeInterval(-200 * 24 * 3600)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: old.path)

        let found = await run([BuiltinRules.oldDownloads], try await context(tree))

        #expect(found["user.oldDownloads"]?.map(\.name) == ["installer.dmg"])
    }

    @Test func largeFilesInHomeOnlyAndNotInsideApps() async throws {
        let tree = try TempTree()
        try tree.file("home/Movies/video.mov", bytes: 3_000_000)
        try tree.file("home/Applications/Big.app/Contents/Resources/huge.pak", bytes: 3_000_000)
        try tree.file("home/small.txt", bytes: 1_000)
        try tree.file("elsewhere/big.bin", bytes: 3_000_000)
        try tree.file("home/Library/Application Support/CrossOver/Bottles/Steam/game.rpf", bytes: 3_000_000)

        let found = await run([BuiltinRules.largeFiles(threshold: 2_000_000)], try await context(tree))

        #expect(found["user.largeFiles"]?.map(\.name) == ["video.mov"])
        #expect(found["user.largeFiles"]?.first?.safety == .userData)
    }

    @Test func unavailableSimulatorsComeFromSimctl() async throws {
        let tree = try TempTree()
        try tree.file("home/Library/Developer/CoreSimulator/Devices/AAA-111/data/d.img", bytes: 800_000)
        try tree.file("home/Library/Developer/CoreSimulator/Devices/BBB-222/data/d.img", bytes: 800_000)
        let json = """
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-16-0": [{"udid": "AAA-111", "isAvailable": false, "name": "iPhone 14"}],
          "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [{"udid": "BBB-222", "isAvailable": true, "name": "iPhone 16"}]
        }}
        """
        let commands = FakeCommands(outputs: ["/usr/bin/xcrun simctl list devices --json": json])

        let found = await run([BuiltinRules.unavailableSimulators], try await context(tree, commands: commands))

        #expect(found["xcode.unavailableSimulators"]?.map(\.name) == ["AAA-111"])
    }

    @Test func informationOnlyRules() async throws {
        let tree = try TempTree()
        try tree.file("home/.Trash/old.zip", bytes: 500_000)
        try tree.file("home/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", bytes: 2_000_000)
        let commands = FakeCommands(outputs: ["/usr/bin/tmutil listlocalsnapshots /": """
        Snapshots for disk /:
        com.apple.TimeMachine.2025-11-03-101500.local
        com.apple.TimeMachine.2025-11-03-111500.local
        """])

        let found = await run(BuiltinRules.all, try await context(tree, commands: commands))

        #expect(found["info.trash"]?.first?.safety == .infoOnly)
        #expect(found["info.dockerDiskImage"]?.first?.name == "Docker.raw")
        #expect(found["info.timeMachineSnapshots"]?.count == 2)
        // Docker.raw is in its own info-only rule, never in Large Files.
        #expect(found["user.largeFiles"] == nil)
    }

    @Test func leftoversComeFromAttribution() async throws {
        let tree = try TempTree()
        let entry = FootprintEntry(path: "/x/Containers/com.gone.app", size: 1_000, kind: .container, confidence: .likely, safety: .review)
        let attribution = AttributionResult(footprints: [], leftovers: [
            LeftoverGroup(identifier: "com.gone.app", displayName: "app", entries: [entry]),
        ])

        let found = await run([BuiltinRules.leftovers], try await context(tree, attribution: attribution))

        #expect(found["leftovers"]?.first?.path == "/x/Containers/com.gone.app")
        #expect(found["leftovers"]?.first?.safety == .review)
    }

    @Test func everyBuiltInRuleHasAnExplanationAndUniqueID() {
        let rules = BuiltinRules.all
        #expect(Set(rules.map(\.id)).count == rules.count)
        #expect(rules.allSatisfy { !$0.explanation.isEmpty && !$0.title.isEmpty && !$0.symbol.isEmpty })
    }
}

struct CleanupPlannerTests {
    @Test func planWarnsAboutRunningAppsAndChangesAndRejectsBlocked() async throws {
        let tree = try TempTree()
        let cache = try tree.file("home/Library/Caches/com.running.app/c.bin", bytes: 1_000)
        let changed = try tree.file("home/Library/Caches/other/c.bin", bytes: 1_000)
        let guardrail = SafetyGuardTests.testGuard(tree)
        let planner = CleanupPlanner(guardrail: guardrail, runningApps: FakeRunningApps(ids: ["com.running.app"]))

        let items = [
            CleanupItem(path: cache.deletingLastPathComponent().path, size: 1_000, ruleID: "t", safety: .safe, ownerBundleID: "com.running.app"),
            CleanupItem(path: changed.deletingLastPathComponent().path, size: 1_000, ruleID: "t", safety: .safe, modificationTime: 1_000),
            CleanupItem(path: tree.url("home/Library/Caches/gone").path, size: 1, ruleID: "t", safety: .safe),
            CleanupItem(path: "/System/Library", size: 1, ruleID: "t", safety: .safe),
            CleanupItem(path: tree.url("home/.Trash").path, size: 1, ruleID: "info.trash", safety: .infoOnly),
            CleanupItem(path: tree.url("home/Movies/m.mov").path, size: 5, ruleID: "t", safety: .userData),
        ]
        let plan = planner.plan(items)

        #expect(plan.entries.count == 4)
        #expect(plan.rejected.count == 2)
        #expect(plan.runningOwners == ["com.running.app"])
        #expect(plan.entries.first { $0.item.path.hasSuffix("other") }?.warnings == [.changedSinceScan])
        #expect(plan.entries.first { $0.item.path.hasSuffix("gone") }?.warnings == [.missing])
        #expect(plan.requiresUserDataConfirmation)
        #expect(plan.entries.last?.item.safety == .userData) // safest first
    }
}

struct TrasherTests {
    @Test func movesToTrashLogsAndPutsBack() async throws {
        let tree = try TempTree()
        let file = try tree.file("home/Library/Caches/com.test.spacera-\(UUID().uuidString)/blob.bin", bytes: 50_000)
        let folder = file.deletingLastPathComponent()
        let log = ActionLog(fileURL: tree.url("log/actions.json"))
        let trasher = Trasher(guardrail: SafetyGuardTests.testGuard(tree), log: log)
        let item = CleanupItem(path: folder.path, size: 50_000, ruleID: "t", safety: .safe)

        let batch = await trasher.trash([item])
        let outcome = try #require(batch.outcomes.first)
        #expect(outcome.status == .trashed)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        let trashPath = try #require(outcome.trashPath)
        #expect(FileManager.default.fileExists(atPath: trashPath))
        #expect(await log.allBatches().first?.outcomes.first?.status == .trashed)

        let restored = await trasher.putBack(outcome)
        #expect(restored.status == .restored)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(await log.allBatches().first?.outcomes.first?.status == .restored)

        // Reloading from disk gives the same history.
        #expect(await ActionLog(fileURL: tree.url("log/actions.json")).allBatches().count == 1)
    }

    @Test func refusesBlockedInfoOnlyAndMissingItems() async throws {
        let tree = try TempTree()
        let precious = try tree.file("home/Documents/precious.txt", bytes: 100)
        let trasher = Trasher(guardrail: SafetyGuardTests.testGuard(tree, extraProtected: [tree.url("home/Documents").path]))

        let batch = await trasher.trash([
            CleanupItem(path: precious.path, size: 100, ruleID: "t", safety: .safe),
            CleanupItem(path: tree.url("home/.Trash").path, size: 1, ruleID: "info.trash", safety: .infoOnly),
            CleanupItem(path: tree.url("home/Library/Caches/missing").path, size: 1, ruleID: "t", safety: .safe),
            CleanupItem(path: "/System/Library/CoreServices", size: 1, ruleID: "t", safety: .safe),
        ])

        #expect(batch.outcomes.map(\.status) == [.blocked, .blocked, .missing, .blocked])
        #expect(FileManager.default.fileExists(atPath: precious.path))
        #expect(batch.trashedSize == 0)
    }

    @Test func putBackRefusesWhenOriginalLocationIsTaken() async throws {
        let tree = try TempTree()
        let original = try tree.file("home/Library/Caches/com.test.taken-\(UUID().uuidString)", bytes: 1_000)
        let trasher = Trasher(guardrail: SafetyGuardTests.testGuard(tree))
        let outcome = try #require(await trasher.trash([CleanupItem(path: original.path, size: 1_000, ruleID: "t", safety: .safe)]).outcomes.first)
        try tree.file("home/Library/Caches/\(original.lastPathComponent)", bytes: 10) // something new took its place

        let result = await trasher.putBack(outcome)

        #expect(result.status == .trashed)
        #expect(result.message?.contains("already exists") == true)
        if let trashPath = outcome.trashPath { try? FileManager.default.removeItem(atPath: trashPath) } // tidy up our own test file
    }
}
