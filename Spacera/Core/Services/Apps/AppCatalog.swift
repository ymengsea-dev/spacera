import CoreServices
import Foundation
import Security

protocol AppCataloging: Sendable {
    func discoverApps() async -> [AppInfo]
}

/// Finds the apps installed on **this** Mac at runtime. Nothing is hard-coded: each app's details
/// are read from its own `Info.plist` and code signature.
///
/// It uses two sources and merges them:
/// 1. A folder search of the standard app locations, up to `searchDepth` levels deep (this covers
///    suite folders like `Adobe Photoshop 2022/`).
/// 2. Spotlight, which finds apps installed anywhere else, if Spotlight indexing is turned on.
struct AppCatalog: AppCataloging {
    struct SearchRoot: Sendable {
        var url: URL
        var isSystem: Bool = false
    }

    var roots: [SearchRoot]
    var searchDepth = 3
    var useSpotlight = true

    static func standardRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SearchRoot] {
        [
            SearchRoot(url: URL(fileURLWithPath: "/Applications")),
            SearchRoot(url: home.appendingPathComponent("Applications")),
            SearchRoot(url: URL(fileURLWithPath: "/System/Applications"), isSystem: true),
        ]
    }

    init(roots: [SearchRoot] = AppCatalog.standardRoots(), searchDepth: Int = 3, useSpotlight: Bool = true) {
        self.roots = roots
        self.searchDepth = searchDepth
        self.useSpotlight = useSpotlight
    }

    func discoverApps() async -> [AppInfo] {
        var bundles: [(URL, Bool)] = []
        var seen = Set<String>()
        func add(_ url: URL, system: Bool) {
            let key = url.resolvingSymlinksInPath().standardizedFileURL.path
            if seen.insert(key).inserted { bundles.append((URL(fileURLWithPath: key), system)) }
        }

        for root in roots {
            for url in Self.findBundles(in: root.url, depth: searchDepth) { add(url, system: root.isSystem) }
        }
        if useSpotlight {
            for url in Self.spotlightApplications() where Self.isUserFacingLocation(url) {
                add(url, system: url.path.hasPrefix("/System/"))
            }
        }

        // Reading code signatures takes a few milliseconds per app, so read them in parallel.
        return await withTaskGroup(of: AppInfo?.self) { group in
            for (url, system) in bundles {
                group.addTask { Self.readApp(at: url, isSystem: system) }
            }
            var apps: [AppInfo] = []
            for await app in group { if let app { apps.append(app) } }
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: - Folder search

    /// Finds `.app` bundles under `root`, without looking inside a bundle (that would pick up helper apps).
    static func findBundles(in root: URL, depth: Int) -> [URL] {
        guard depth > 0,
              let children = try? FileManager.default.contentsOfDirectory(
                  at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        else { return [] }
        var result: [URL] = []
        for child in children {
            if child.pathExtension == "app" {
                result.append(child)
            } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
                result += findBundles(in: child, depth: depth - 1)
            }
        }
        return result
    }

    // MARK: - Spotlight

    /// Asks Spotlight for every application bundle. Returns an empty list if Spotlight is off or unavailable.
    static func spotlightApplications() -> [URL] {
        let queryString = "kMDItemContentType == 'com.apple.application-bundle'" as CFString
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString, nil, nil) else { return [] }
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var urls: [URL] = []
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        return urls
    }

    /// Removes Spotlight hits that aren't apps a person installed: helper apps inside other bundles,
    /// apps in the Trash, Xcode build products, apps on other volumes, and macOS internals.
    /// Anything under a `Library` folder is skipped too (for example, Steam games): that data is already
    /// counted as part of the app that owns the folder, so listing it separately would count it twice.
    static func isUserFacingLocation(_ url: URL) -> Bool {
        let path = url.path
        let components = url.pathComponents.dropLast()
        if components.contains(where: { $0.hasSuffix(".app") || $0.hasSuffix(".framework") || $0.hasSuffix(".bundle") }) { return false }
        let excluded = ["/.Trash/", "/DerivedData/", "/Build/Products/", "/Library/Developer/", "/System/Library/",
                        "/Library/", "/private/", "/Volumes/", "/usr/", "/opt/"]
        if excluded.contains(where: path.contains) { return false }
        // Build output from people's own projects (Cargo, Tauri, Xcode, npm, and so on) is not an installed app.
        let buildFolders: Set<String> = ["target", "build", "builds", "dist", ".build", "out", "node_modules", "debug", "release"]
        if components.contains(where: { buildFolders.contains($0.lowercased()) }) { return false }
        if isInsideSourceRepository(url) { return false }
        return true
    }

    /// True if any folder above the app contains a `.git` folder, meaning it's inside someone's source code.
    static func isInsideSourceRepository(_ url: URL) -> Bool {
        var folder = url.deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        while folder.path.count > 1, folder.standardizedFileURL.path != home {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) { return true }
            folder = folder.deletingLastPathComponent()
        }
        return false
    }

    // MARK: - Reading an app

    static func readApp(at url: URL, isSystem: Bool) -> AppInfo? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any] ?? [:]
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? fileName
        var app = AppInfo(
            url: url,
            bundleID: info["CFBundleIdentifier"] as? String,
            name: name,
            version: info["CFBundleShortVersionString"] as? String,
            isSystemApp: isSystem
        )
        let signing = readSigning(of: url)
        app.teamID = signing.teamID
        app.appGroups = signing.appGroups
        return app
    }

    /// Reads the team ID and app-group entitlements from the code signature. Doesn't validate the signature.
    static func readSigning(of url: URL) -> (teamID: String?, appGroups: [String]) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return (nil, [])
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else { return (nil, []) }
        let teamID = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        return (teamID, groups)
    }
}
