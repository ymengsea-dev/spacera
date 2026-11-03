import Foundation
import Testing
@testable import Spacera

struct AppCatalogTests {
    @Test func discoversAppsWithoutAnyHardCodedList() async throws {
        let tree = try TempTree()
        try tree.app("Applications/Zeta Editor.app", bundleID: "io.zeta.editor", name: "Zeta Editor", version: "3.2")
        try tree.app("Applications/Suite 2025/Suite Photo.app", bundleID: "com.suite.photo")
        try tree.app("Applications/NoID.app", bundleID: nil)

        let catalog = AppCatalog(roots: [.init(url: tree.url("Applications"))], useSpotlight: false)
        let apps = await catalog.discoverApps()

        #expect(apps.map(\.name) == ["NoID", "Suite Photo", "Zeta Editor"])
        let zeta = try #require(apps.first { $0.bundleID == "io.zeta.editor" })
        #expect(zeta.version == "3.2")
        #expect(zeta.isSystemApp == false)
    }

    @Test func doesNotListHelperAppsInsideBundles() async throws {
        let tree = try TempTree()
        try tree.app("Applications/Host.app", bundleID: "com.host.app")
        try tree.app("Applications/Host.app/Contents/Helpers/Host Helper.app", bundleID: "com.host.app.helper")

        let apps = await AppCatalog(roots: [.init(url: tree.url("Applications"))], useSpotlight: false).discoverApps()

        #expect(apps.map(\.bundleID) == ["com.host.app"])
    }

    @Test func respectsSearchDepth() async throws {
        let tree = try TempTree()
        try tree.app("Applications/a/b/c/TooDeep.app", bundleID: "com.deep.app")
        try tree.app("Applications/a/b/JustRight.app", bundleID: "com.ok.app")

        let apps = await AppCatalog(roots: [.init(url: tree.url("Applications"))], searchDepth: 3, useSpotlight: false).discoverApps()

        #expect(apps.map(\.bundleID) == ["com.ok.app"])
    }

    @Test func spotlightResultsAreFiltered() {
        #expect(AppCatalog.isUserFacingLocation(URL(fileURLWithPath: "/Users/me/Tools/Thing.app")))
        #expect(!AppCatalog.isUserFacingLocation(URL(fileURLWithPath: "/Applications/Host.app/Contents/Helper.app")))
        #expect(!AppCatalog.isUserFacingLocation(URL(fileURLWithPath: "/Users/me/.Trash/Old.app")))
        #expect(!AppCatalog.isUserFacingLocation(URL(fileURLWithPath: "/Users/me/Library/Developer/Xcode/DerivedData/X/Build/Products/Debug/X.app")))
        #expect(!AppCatalog.isUserFacingLocation(URL(fileURLWithPath: "/Users/me/Library/Application Support/Steam/steamapps/common/Game/Game.app")))
        #expect(!AppCatalog.isUserFacingLocation(URL(fileURLWithPath: "/Volumes/USB/Installer.app")))
        #expect(!AppCatalog.isUserFacingLocation(URL(fileURLWithPath: "/Users/me/code/app/src-tauri/target/release/bundle/macos/App.app")))
        #expect(!AppCatalog.isUserFacingLocation(URL(fileURLWithPath: "/Users/me/code/game/builds/v0.1.0/Game.app")))
    }

    @Test func appsInsideSourceRepositoriesAreNotInstalledApps() throws {
        let tree = try TempTree()
        try tree.directory("project/.git")
        let built = try tree.app("project/packaging/Thing.app", bundleID: "com.thing.app")
        let installed = try tree.app("Apps/Other.app", bundleID: "com.other.app")
        #expect(AppCatalog.isInsideSourceRepository(built))
        #expect(!AppCatalog.isInsideSourceRepository(installed))
    }

    @Test func readsTeamIDFromRealSignedApp() throws {
        // Read-only check against an app that ships with every Mac.
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        try #require(FileManager.default.fileExists(atPath: calculator.path))
        let app = try #require(AppCatalog.readApp(at: calculator, isSystem: true))
        #expect(app.bundleID == "com.apple.calculator")
        #expect(app.isSystemApp)
    }
}
