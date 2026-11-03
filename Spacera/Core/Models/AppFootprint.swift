import Foundation

/// What kind of data a footprint entry is. Used for grouping and labels in the UI.
enum FootprintKind: String, Sendable, Codable, CaseIterable {
    case bundle, container, groupContainer, applicationSupport, cache, httpStorage, webKit,
         logs, savedState, preferences, cookies, backgroundItem, developer, other

    var title: String {
        switch self {
        case .bundle: "App"
        case .container: "Container"
        case .groupContainer: "Shared Container"
        case .applicationSupport: "Application Support"
        case .cache: "Caches"
        case .httpStorage: "Web Storage"
        case .webKit: "WebKit Data"
        case .logs: "Logs"
        case .savedState: "Saved Window State"
        case .preferences: "Preferences"
        case .cookies: "Cookies"
        case .backgroundItem: "Background Item"
        case .developer: "Developer Data"
        case .other: "Other"
        }
    }
}

/// How sure Spacera is that a piece of data belongs to an app.
enum MatchConfidence: Int, Sendable, Codable, Comparable {
    /// Matched by the app's name. Usually right, but worth checking.
    case likely
    /// Matched through an app group in the app's signed entitlements, or its team ID.
    case group
    /// Matched by bundle ID, by a signed reference, or by the bundle itself.
    case exact

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct FootprintEntry: Sendable, Identifiable, Hashable {
    var path: String
    var size: Int64
    var kind: FootprintKind
    var confidence: MatchConfidence
    var safety: SafetyLevel
    /// Extra information shown to the user, for example "Runs: /Applications/Foo.app/…/helper".
    var note: String?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

/// One app and everything Spacera attributed to it.
struct AppFootprint: Sendable, Identifiable {
    var app: AppInfo
    /// Largest first. Includes the `.bundle` entry when the bundle's size is known.
    var entries: [FootprintEntry]

    var id: String { app.id }
    var totalSize: Int64 { entries.reduce(0) { $0 + $1.size } }
    var bundleSize: Int64 { entries.filter { $0.kind == .bundle }.reduce(0) { $0 + $1.size } }
    var dataSize: Int64 { totalSize - bundleSize }
    var backgroundItems: [FootprintEntry] { entries.filter { $0.kind == .backgroundItem } }
}

/// Data that no installed app claims: usually left behind by an app that was deleted.
struct LeftoverGroup: Sendable, Identifiable {
    /// The bundle ID or launchd label the data is named after.
    var identifier: String
    /// A best guess at a readable name, for example "com.vendor.CoolApp" becomes "CoolApp".
    var displayName: String
    var entries: [FootprintEntry]

    var id: String { identifier }
    var totalSize: Int64 { entries.reduce(0) { $0 + $1.size } }
}

struct AttributionResult: Sendable {
    /// Largest first.
    var footprints: [AppFootprint]
    /// Largest first.
    var leftovers: [LeftoverGroup]
}
