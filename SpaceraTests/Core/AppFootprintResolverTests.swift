import Foundation
import Testing
@testable import Spacera

/// Every test builds a fake home folder and a fake /Library inside a temporary tree.
struct AppFootprintResolverTests {
    struct Fixture {
        let tree: TempTree
        let resolver: AppFootprintResolver

        init(overrides: [AttributionOverride] = []) throws {
            tree = try TempTree()
            try tree.directory("home/Library")
            try tree.directory("sys/Library")
            resolver = AppFootprintResolver(
                locations: LibraryLocations(home: tree.url("home"), systemLibrary: tree.url("sys/Library")),
                overrides: overrides
            )
        }

        func apps() async -> [AppInfo] {
            await AppCatalog(roots: [.init(url: tree.url("Applications"))], useSpotlight: false).discoverApps()
        }

        func resolve(_ apps: [AppInfo], useScan: Bool = true) async throws -> AttributionResult {
            let scan = useScan ? try await DiskScanner().scanTree(root: tree.root) : nil
            return await resolver.resolve(apps: apps, scan: scan)
        }
    }

    @Test func attributesStandardLibraryLocationsByBundleIDAndName() async throws {
        let f = try Fixture()
        try f.tree.app("Applications/Zeta Editor.app", bundleID: "io.zeta.editor", name: "Zeta Editor", bytes: 1_000_000)
        try f.tree.file("home/Library/Containers/io.zeta.editor/Data/doc.bin", bytes: 2_000_000)
        try f.tree.file("home/Library/Caches/io.zeta.editor.ShipIt/update.bin", bytes: 700_000)   // helper ID prefix
        try f.tree.file("home/Library/Application Support/Zeta Editor/state.bin", bytes: 900_000) // by name
        try f.tree.file("home/Library/Saved Application State/io.zeta.editor.savedState/w.data", bytes: 5_000)
        try f.tree.file("home/Library/Preferences/io.zeta.editor.plist", bytes: 3_000)

        let result = try await f.resolve(await f.apps())
        let zeta = try #require(result.footprints.first)

        #expect(Set(zeta.entries.map(\.kind)) == [.bundle, .container, .cache, .applicationSupport, .savedState, .preferences])
        #expect(zeta.entries.first { $0.kind == .applicationSupport }?.confidence == .likely)
        #expect(zeta.entries.first { $0.kind == .container }?.confidence == .exact)
        #expect(zeta.entries.first { $0.kind == .cache }?.safety == .safe)
        #expect(zeta.bundleSize > 0)
        #expect(zeta.dataSize > 3_000_000)
        #expect(result.leftovers.isEmpty)
    }

    @Test func findsLeftoversFromUninstalledApps() async throws {
        let f = try Fixture()
        try f.tree.app("Applications/Kept.app", bundleID: "com.kept.app")
        try f.tree.file("home/Library/Containers/com.gone.CoolApp/Data/x.bin", bytes: 1_500_000)
        try f.tree.file("home/Library/Caches/com.gone.CoolApp/y.bin", bytes: 400_000)
        try f.tree.file("home/Library/Caches/com.apple.Something/z.bin", bytes: 400_000) // Apple: never a leftover
        try f.tree.file("home/Library/Caches/com.kept.updater/u.bin", bytes: 400_000)     // same vendor as an installed app
        try f.tree.file("home/Library/Caches/RandomFolder/r.bin", bytes: 400_000)          // not a bundle ID

        let result = try await f.resolve(await f.apps())

        #expect(result.leftovers.map(\.identifier) == ["com.gone.CoolApp"])
        let gone = try #require(result.leftovers.first)
        #expect(gone.displayName == "CoolApp")
        #expect(Set(gone.entries.map(\.kind)) == [.container, .cache])
        #expect(gone.entries.allSatisfy { $0.safety == .review })
    }

    @Test func attributesBackgroundItemsAndFlagsOrphans() async throws {
        let f = try Fixture()
        let app = try f.tree.app("Applications/Syncer.app", bundleID: "com.syncer.app")
        try f.tree.file("Applications/Syncer.app/Contents/Library/LoginItems/agent", bytes: 10_000)
        try f.tree.plist("home/Library/LaunchAgents/com.syncer.agent.plist", [
            "Label": "com.syncer.agent",
            "ProgramArguments": [app.appendingPathComponent("Contents/Library/LoginItems/agent").path, "--background"],
        ])
        try f.tree.plist("sys/Library/LaunchDaemons/com.oldvpn.helper.plist", [
            "Label": "com.oldvpn.helper",
            "Program": "/Library/PrivilegedHelperTools/com.oldvpn.helper-does-not-exist",
        ])
        try f.tree.plist("sys/Library/LaunchAgents/com.modern.agent.plist", [
            "Label": "com.modern.agent",
            "AssociatedBundleIdentifiers": ["com.syncer.app"],
            "BundleProgram": "Contents/MacOS/agent",
        ])

        let result = try await f.resolve(await f.apps())
        let syncer = try #require(result.footprints.first { $0.app.bundleID == "com.syncer.app" })

        #expect(syncer.backgroundItems.count == 2)
        #expect(syncer.backgroundItems.allSatisfy { $0.confidence == .exact })
        #expect(syncer.backgroundItems.contains { $0.note?.contains("LoginItems/agent") == true })

        let orphan = try #require(result.leftovers.first { $0.identifier == "com.oldvpn.helper" })
        #expect(orphan.entries.first?.kind == .backgroundItem)
        #expect(orphan.entries.first?.note?.contains("missing") == true)
    }

    @Test func matchesGroupContainersByEntitlementAndTeamID() async throws {
        let f = try Fixture()
        try f.tree.app("Applications/Office.app", bundleID: "com.office.word")
        try f.tree.file("home/Library/Group Containers/ABCDE12345.Office/shared.bin", bytes: 1_000_000)
        try f.tree.file("home/Library/Group Containers/group.com.office.word.shared/s.bin", bytes: 1_000_000)
        try f.tree.file("home/Library/Group Containers/group.exact.entitlement/e.bin", bytes: 1_000_000)

        var apps = await f.apps()
        apps[0].teamID = "ABCDE12345"
        apps[0].appGroups = ["group.exact.entitlement"]
        let result = try await f.resolve(apps)

        let groups = result.footprints[0].entries.filter { $0.kind == .groupContainer }
        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.confidence == .group })
    }

    @Test func overridesAddUnusualLocationsWithoutDoubleCounting() async throws {
        let override = AttributionOverride(bundleID: "com.example.ide", locations: [
            .init(path: "Library/Application Support/Example", kind: .applicationSupport, safety: .review),
            .init(path: "Library/Caches/Vendor", kind: .cache, safety: .safe, childPrefix: "IDE"),
            .init(path: ".example", kind: .applicationSupport, safety: .review),
        ])
        let f = try Fixture(overrides: [override])
        try f.tree.app("Applications/IDE.app", bundleID: "com.example.ide", name: "Example")
        try f.tree.file("home/Library/Application Support/Example/data.bin", bytes: 1_000_000)
        try f.tree.file("home/Library/Caches/Vendor/IDE2025.1/c.bin", bytes: 500_000)
        try f.tree.file("home/Library/Caches/Vendor/IDE2025.2/c.bin", bytes: 500_000)
        try f.tree.file("home/Library/Caches/Vendor/OtherProduct/c.bin", bytes: 500_000)
        try f.tree.file("home/.example/ext.bin", bytes: 300_000)

        let result = try await f.resolve(await f.apps())
        let ide = result.footprints[0]

        // "Example" also matches by name; the override claimed it first, so it's counted once.
        #expect(ide.entries.filter { $0.path.hasSuffix("Application Support/Example") }.count == 1)
        #expect(ide.entries.filter { $0.kind == .cache }.map { URL(fileURLWithPath: $0.path).lastPathComponent }.sorted() == ["IDE2025.1", "IDE2025.2"])
        #expect(ide.entries.contains { $0.path.hasSuffix("/.example") })
        let paths = ide.entries.map(\.path)
        #expect(Set(paths).count == paths.count)
    }

    @Test func overridesDoNothingWhenAppIsNotInstalled() async throws {
        let f = try Fixture(overrides: AttributionOverrides.builtIn)
        try f.tree.app("Applications/Plain.app", bundleID: "com.plain.app")
        try f.tree.file("home/Library/Developer/Xcode/DerivedData/Proj/x.bin", bytes: 500_000)

        let result = try await f.resolve(await f.apps())

        #expect(result.footprints.count == 1)
        #expect(!result.footprints[0].entries.contains { $0.kind == .developer })
    }

    @Test func worksWithoutAFullScanByScanningFoldersDirectly() async throws {
        let f = try Fixture()
        try f.tree.app("Applications/Zeta.app", bundleID: "io.zeta.editor", bytes: 800_000)
        try f.tree.file("home/Library/Containers/io.zeta.editor/Data/doc.bin", bytes: 2_000_000)

        let withScan = try await f.resolve(await f.apps(), useScan: true)
        let withoutScan = try await f.resolve(await f.apps(), useScan: false)

        #expect(withScan.footprints[0].totalSize == withoutScan.footprints[0].totalSize)
        #expect(withoutScan.footprints[0].entries.count == 2)
    }

    @Test func overridePrefersExactBundleIDOverPrefixShims() async throws {
        let override = AttributionOverride(bundleID: "com.browser.main", locations: [
            .init(path: "Library/Application Support/Browser/Profiles", kind: .applicationSupport, safety: .userData),
        ])
        let f = try Fixture(overrides: [override])
        try f.tree.app("Applications/Browser.app", bundleID: "com.browser.main")
        try f.tree.app("Applications/Web Shim.app", bundleID: "com.browser.main.app.abc123", name: "Web Shim")
        try f.tree.file("home/Library/Application Support/Browser/Profiles/p.bin", bytes: 2_000_000)

        let result = try await f.resolve(await f.apps())

        let browser = try #require(result.footprints.first { $0.app.bundleID == "com.browser.main" })
        let shim = try #require(result.footprints.first { $0.app.bundleID == "com.browser.main.app.abc123" })
        #expect(browser.entries.contains { $0.path.hasSuffix("Profiles") })
        #expect(!shim.entries.contains { $0.path.hasSuffix("Profiles") })
    }

    @Test func toolAndFrameworkIdentifiersAreNotLeftovers() async throws {
        let f = try Fixture()
        try f.tree.app("Applications/A.app", bundleID: "com.a.app")
        try f.tree.file("home/Library/Caches/org.swift.swiftpm/repositories/r.bin", bytes: 500_000)
        try f.tree.file("home/Library/Caches/com.Breakpad.crash_report_sender/c.bin", bytes: 500_000)
        try f.tree.file("sys/Library/PrivilegedHelperTools/com.gone.helper", bytes: 50_000)

        let result = try await f.resolve(await f.apps())

        #expect(result.leftovers.map(\.identifier) == ["com.gone.helper"])
        #expect(result.leftovers.first?.entries.first?.note?.contains("helper tool") == true)
    }

    @Test func identifierHelpers() {
        #expect(AppFootprintResolver.looksLikeBundleID("com.vendor.app"))
        #expect(AppFootprintResolver.looksLikeBundleID("io.zeta-editor.app_2"))
        #expect(!AppFootprintResolver.looksLikeBundleID("Google"))
        #expect(!AppFootprintResolver.looksLikeBundleID("com.vendor"))
        #expect(!AppFootprintResolver.looksLikeBundleID("my folder.v2.backup copy"))
        #expect(AppFootprintResolver.isAppleIdentifier("com.apple.Safari"))
        #expect(AppInfo.normalize("Visual Studio Code") == "visualstudiocode")
    }
}
