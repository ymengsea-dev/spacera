import Foundation

protocol AppFootprintResolving: Sendable {
    func resolve(apps: [AppInfo], scan: ScanResult?) async -> AttributionResult
}

/// Where the Library folders are. Tests point this at a temporary tree.
struct LibraryLocations: Sendable {
    var home: URL
    var systemLibrary: URL

    var userLibrary: URL { home.appendingPathComponent("Library", isDirectory: true) }

    static let current = LibraryLocations(
        home: FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL(fileURLWithPath: "/Library", isDirectory: true)
    )
}

/// Matches data on disk to installed apps, using only what each app says about itself:
/// its bundle ID, name, team ID, app groups, and the programs its background items run.
/// See docs/04-app-attribution.md.
struct AppFootprintResolver: AppFootprintResolving {
    var locations: LibraryLocations = .current
    var overrides: [AttributionOverride] = AttributionOverrides.builtIn
    var scanner = DiskScanner()

    // MARK: Location rules

    enum MatchStyle: Sendable {
        /// The folder or file name is the bundle ID (with `suffix` removed).
        case bundleID
        /// Bundle ID first, then the app's name ("Visual Studio Code" or "Code").
        case bundleIDOrName
        /// An app-group identifier from the app's entitlements, or "<TeamID>.something".
        case groupContainer
        /// A launchd plist. Matched by the program it runs, or by `AssociatedBundleIdentifiers`.
        case launchdPlist
        /// A privileged helper tool named after a bundle ID.
        case helperTool
    }

    struct LocationRule: Sendable {
        var folder: URL
        var kind: FootprintKind
        var style: MatchStyle
        var safety: SafetyLevel
        var suffix: String? = nil
    }

    var rules: [LocationRule] {
        let user = locations.userLibrary
        let system = locations.systemLibrary
        func u(_ path: String) -> URL { user.appendingPathComponent(path, isDirectory: true) }
        func s(_ path: String) -> URL { system.appendingPathComponent(path, isDirectory: true) }
        return [
            LocationRule(folder: u("Containers"), kind: .container, style: .bundleID, safety: .userData),
            LocationRule(folder: u("Group Containers"), kind: .groupContainer, style: .groupContainer, safety: .userData),
            LocationRule(folder: u("Application Support"), kind: .applicationSupport, style: .bundleIDOrName, safety: .review),
            LocationRule(folder: u("Caches"), kind: .cache, style: .bundleIDOrName, safety: .safe),
            LocationRule(folder: u("HTTPStorages"), kind: .httpStorage, style: .bundleID, safety: .safe, suffix: ".binarycookies"),
            LocationRule(folder: u("WebKit"), kind: .webKit, style: .bundleID, safety: .safe),
            LocationRule(folder: u("Logs"), kind: .logs, style: .bundleIDOrName, safety: .safe),
            LocationRule(folder: u("Saved Application State"), kind: .savedState, style: .bundleID, safety: .safe, suffix: ".savedState"),
            LocationRule(folder: u("Preferences"), kind: .preferences, style: .bundleID, safety: .review, suffix: ".plist"),
            LocationRule(folder: u("Cookies"), kind: .cookies, style: .bundleID, safety: .review, suffix: ".binarycookies"),
            LocationRule(folder: u("LaunchAgents"), kind: .backgroundItem, style: .launchdPlist, safety: .review),
            LocationRule(folder: s("Application Support"), kind: .applicationSupport, style: .bundleIDOrName, safety: .review),
            LocationRule(folder: s("Caches"), kind: .cache, style: .bundleID, safety: .safe),
            LocationRule(folder: s("LaunchAgents"), kind: .backgroundItem, style: .launchdPlist, safety: .review),
            LocationRule(folder: s("LaunchDaemons"), kind: .backgroundItem, style: .launchdPlist, safety: .review),
            LocationRule(folder: s("PrivilegedHelperTools"), kind: .backgroundItem, style: .helperTool, safety: .review),
        ]
    }

    // MARK: Resolve

    func resolve(apps: [AppInfo], scan: ScanResult?) async -> AttributionResult {
        let trees = TreeSource(scan: scan, scanner: scanner)
        let index = AppIndex(apps: apps)
        var claimed = Set<ObjectIdentifier>()
        var entriesByApp: [String: [FootprintEntry]] = [:]
        var leftovers: [String: LeftoverGroup] = [:]

        func isClaimed(_ node: FileNode) -> Bool {
            var current: FileNode? = node
            while let n = current {
                if claimed.contains(n.id) { return true }
                current = n.parent
            }
            return false
        }

        func claim(_ node: FileNode, for app: AppInfo, kind: FootprintKind, confidence: MatchConfidence,
                   safety: SafetyLevel, note: String? = nil) {
            guard !isClaimed(node) else { return }
            claimed.insert(node.id)
            let entry = FootprintEntry(path: ScanResult.logicalPath(node.path), size: node.size, kind: kind,
                                       confidence: confidence, safety: safety, note: note)
            entriesByApp[app.id, default: []].append(entry)
        }

        func addLeftover(_ node: FileNode, identifier: String, kind: FootprintKind, note: String? = nil) {
            guard !isClaimed(node) else { return }
            claimed.insert(node.id)
            let entry = FootprintEntry(path: ScanResult.logicalPath(node.path), size: node.size, kind: kind,
                                       confidence: .likely, safety: .review, note: note)
            leftovers[identifier.lowercased(), default: LeftoverGroup(
                identifier: identifier, displayName: Self.displayName(forIdentifier: identifier), entries: []
            )].entries.append(entry)
        }

        // 1. App bundles.
        for app in apps {
            if let node = await trees.node(atPath: app.url.path) {
                claim(node, for: app, kind: .bundle, confidence: .exact, safety: app.isSystemApp ? .infoOnly : .userData)
            }
        }

        // 2. Overrides: specific known paths for installed apps.
        for override in overrides {
            // Prefer the app whose bundle ID matches exactly. Prefix matches (such as Chrome web-app
            // shims named "com.google.Chrome.app.<id>") apply only when no app matches exactly.
            let exact = apps.filter { $0.bundleID?.lowercased() == override.bundleID.lowercased() }
            let targets = exact.isEmpty ? apps.filter(override.applies(to:)) : exact
            for app in targets {
                for location in override.locations {
                    let path = location.path.hasPrefix("/") ? location.path : locations.home.appendingPathComponent(location.path).path
                    guard let node = await trees.node(atPath: path) else { continue }
                    if let prefix = location.childPrefix {
                        for child in node.children where child.name.hasPrefix(prefix) {
                            claim(child, for: app, kind: location.kind, confidence: .exact, safety: location.safety, note: location.note)
                        }
                    } else {
                        claim(node, for: app, kind: location.kind, confidence: .exact, safety: location.safety, note: location.note)
                    }
                }
            }
        }

        // 3. The general rules for the standard Library locations.
        for rule in rules {
            guard let folder = await trees.node(atPath: rule.folder.path) else { continue }
            for child in folder.children {
                if case .smallFiles = child.kind { continue }
                if child.name.hasPrefix(".") { continue }
                let identifier = Self.strip(child.name, suffix: rule.suffix)

                switch rule.style {
                case .launchdPlist:
                    let plistPath = ScanResult.logicalPath(child.path)
                    let match = Self.matchLaunchd(plistAt: plistPath, index: index)
                    switch match {
                    case .app(let app, let note):
                        claim(child, for: app, kind: rule.kind, confidence: .exact, safety: rule.safety, note: note)
                    case .orphan(let label, let note):
                        addLeftover(child, identifier: label, kind: rule.kind, note: note)
                    case .unknown:
                        if let (app, confidence) = index.match(identifier: identifier, allowName: false) {
                            claim(child, for: app, kind: rule.kind, confidence: confidence, safety: rule.safety)
                        }
                    }
                    continue

                case .groupContainer:
                    if let (app, confidence) = index.matchGroup(identifier) {
                        claim(child, for: app, kind: rule.kind, confidence: confidence, safety: rule.safety)
                        continue
                    }

                case .bundleID, .helperTool, .bundleIDOrName:
                    if let (app, confidence) = index.match(identifier: identifier, allowName: rule.style == .bundleIDOrName) {
                        claim(child, for: app, kind: rule.kind, confidence: confidence, safety: rule.safety)
                        continue
                    }
                }

                // Nothing installed matches. If it looks like a bundle ID, isn't Apple's, and no
                // installed app comes from the same vendor, it's likely left over from a deleted app.
                if Self.looksLikeBundleID(identifier), !Self.isAppleIdentifier(identifier),
                   !AttributionOverrides.isNonAppIdentifier(identifier), !index.hasVendor(of: identifier) {
                    let note: String? = rule.style == .helperTool
                        ? "Privileged helper tool that runs with admin rights. No installed app matches it."
                        : nil
                    addLeftover(child, identifier: identifier, kind: rule.kind, note: note)
                }
            }
        }

        // Assemble the result.
        var footprints: [AppFootprint] = apps.map { app in
            let entries = (entriesByApp[app.id] ?? []).sorted { $0.size > $1.size }
            return AppFootprint(app: app, entries: entries)
        }
        footprints.sort { $0.totalSize > $1.totalSize }
        let leftoverList = leftovers.values
            .map { group in var g = group; g.entries.sort { $0.size > $1.size }; return g }
            .sorted { $0.totalSize > $1.totalSize }
        return AttributionResult(footprints: footprints, leftovers: leftoverList)
    }

    // MARK: - launchd plists

    enum LaunchdMatch {
        case app(AppInfo, note: String)
        case orphan(label: String, note: String)
        case unknown
    }

    static func matchLaunchd(plistAt path: String, index: AppIndex) -> LaunchdMatch {
        guard let plist = NSDictionary(contentsOfFile: path) as? [String: Any] else { return .unknown }
        let label = plist["Label"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let bundleProgram = plist["BundleProgram"] as? String

        // Signed reference: the program lives inside an installed app's bundle.
        if let program, let app = index.app(containingPath: program) {
            return .app(app, note: "Runs \(program)")
        }
        // Modern agents (SMAppService) name their app explicitly.
        var associated: [String] = []
        if let one = plist["AssociatedBundleIdentifiers"] as? String { associated = [one] }
        if let many = plist["AssociatedBundleIdentifiers"] as? [String] { associated = many }
        for id in associated {
            if let app = index.app(bundleID: id) {
                return .app(app, note: "Background item for \(app.name)" + (program.map { " · runs \($0)" } ?? ""))
            }
        }
        // The program it should run no longer exists. Usually the app was deleted without its background items.
        if let program, program.hasPrefix("/"), !FileManager.default.fileExists(atPath: program) {
            return .orphan(label: label, note: "Program is missing: \(program)")
        }
        if bundleProgram != nil, !associated.isEmpty {
            return .orphan(label: label, note: "Its app (\(associated.joined(separator: ", "))) is not installed")
        }
        return .unknown
    }

    // MARK: - Helpers

    static func strip(_ name: String, suffix: String?) -> String {
        guard let suffix, name.hasSuffix(suffix) else { return name }
        return String(name.dropLast(suffix.count))
    }

    /// Reverse-DNS with at least three parts, like "com.vendor.app".
    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return parts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }
    }

    static func isAppleIdentifier(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.")
    }

    /// "com.vendor.CoolApp.agent" becomes "CoolApp".
    static func displayName(forIdentifier identifier: String) -> String {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 3 else { return identifier }
        return String(parts[2])
    }
}

// MARK: - App index

/// Lookup tables for matching names on disk to installed apps.
struct AppIndex: Sendable {
    private let byBundleID: [String: AppInfo]
    /// Longest first, so a more specific bundle ID wins over a shorter one.
    private let bundleIDsByLength: [String]
    private let byName: [String: [AppInfo]]
    private let byGroup: [String: AppInfo]
    private let byTeam: [String: [AppInfo]]
    private let vendors: Set<String>
    /// Bundle paths followed by "/", longest first.
    private let bundlePaths: [(String, AppInfo)]

    init(apps: [AppInfo]) {
        var byBundleID: [String: AppInfo] = [:]
        var byName: [String: [AppInfo]] = [:]
        var byGroup: [String: AppInfo] = [:]
        var byTeam: [String: [AppInfo]] = [:]
        var vendors = Set<String>()
        for app in apps {
            if let id = app.bundleID?.lowercased() {
                byBundleID[id] = byBundleID[id] ?? app
                if let vendor = Self.vendor(of: id) { vendors.insert(vendor) }
            }
            for name in app.candidateNames { byName[name, default: []].append(app) }
            for group in app.appGroups { byGroup[group.lowercased()] = app }
            if let team = app.teamID { byTeam[team.lowercased(), default: []].append(app) }
        }
        self.byBundleID = byBundleID
        self.bundleIDsByLength = byBundleID.keys.sorted { $0.count > $1.count }
        self.byName = byName
        self.byGroup = byGroup
        self.byTeam = byTeam
        self.vendors = vendors
        self.bundlePaths = apps.map { ($0.url.standardizedFileURL.path + "/", $0) }.sorted { $0.0.count > $1.0.count }
    }

    func app(bundleID: String) -> AppInfo? { byBundleID[bundleID.lowercased()] }

    func app(containingPath path: String) -> AppInfo? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return bundlePaths.first { standardized.hasPrefix($0.0) }?.1
    }

    /// Matches by exact bundle ID, then by a bundle-ID prefix (for example, "com.vendor.app.helper"
    /// belongs to "com.vendor.app"), then optionally by the app's name.
    func match(identifier: String, allowName: Bool) -> (AppInfo, MatchConfidence)? {
        let lower = identifier.lowercased()
        if let app = byBundleID[lower] { return (app, .exact) }
        if let id = bundleIDsByLength.first(where: { lower.hasPrefix($0 + ".") }), let app = byBundleID[id] {
            return (app, .exact)
        }
        if allowName {
            let normalized = AppInfo.normalize(identifier)
            if let candidates = byName[normalized], let app = candidates.first, candidates.count == 1 || candidates.allSatisfy({ $0.bundleID == app.bundleID }) {
                return (app, .likely)
            }
        }
        return nil
    }

    func matchGroup(_ identifier: String) -> (AppInfo, MatchConfidence)? {
        let lower = identifier.lowercased()
        if let app = byGroup[lower] { return (app, .group) }
        // "group.com.vendor.app" usually belongs to "com.vendor.app".
        if lower.hasPrefix("group."), let (app, _) = match(identifier: String(identifier.dropFirst(6)), allowName: false) {
            return (app, .group)
        }
        // "<TeamID>.something": only certain if exactly one installed app has that team ID.
        if let team = lower.split(separator: ".").first, let apps = byTeam[String(team)], apps.count == 1 {
            return (apps[0], .group)
        }
        return nil
    }

    /// True if an installed app comes from the same vendor ("com.google" for "com.google.Keystone").
    func hasVendor(of identifier: String) -> Bool {
        guard let vendor = Self.vendor(of: identifier.lowercased()) else { return false }
        return vendors.contains(vendor)
    }

    static func vendor(of bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts[0] + "." + parts[1]
    }
}

// MARK: - Tree source

/// Gives the resolver folder trees. It uses the main scan when the path is inside it, and otherwise
/// scans just that folder (for example, `/Library/LaunchDaemons` when only the home folder was scanned).
private final class TreeSource {
    let scan: ScanResult?
    let scanner: DiskScanner
    private var cache: [String: FileNode?] = [:]

    init(scan: ScanResult?, scanner: DiskScanner) {
        self.scan = scan
        self.scanner = scanner
    }

    func node(atPath path: String) async -> FileNode? {
        if let scan {
            if let node = scan.node(atPath: path) { return node }
            let root = ScanResult.logicalPath(scan.root.name)
            let logical = ScanResult.logicalPath(path)
            // Inside the scanned area but not found means it doesn't exist (or wasn't readable).
            if logical == root || logical.hasPrefix(root.hasSuffix("/") ? root : root + "/") { return nil }
        }
        if let cached = cache[path] { return cached }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            cache[path] = .some(nil)
            return nil
        }
        let node = try? await scanner.scanTree(root: URL(fileURLWithPath: path)).root
        cache[path] = .some(node)
        return node
    }
}
