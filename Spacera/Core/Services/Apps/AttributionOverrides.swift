import Foundation

/// Extra locations for apps that keep data in unusual places.
///
/// This is **not** a list of supported apps. Every app is matched by the general rules in
/// `AppFootprintResolver`, using the bundle ID and name read from the app itself. An override only
/// adds paths those rules can't infer, and only applies when a matching app is installed.
struct AttributionOverride: Sendable {
    struct Location: Sendable {
        /// Relative to the home folder, or an absolute path if it starts with "/".
        var path: String
        var kind: FootprintKind
        var safety: SafetyLevel
        /// If set, `path` is a folder, and each child whose name starts with this prefix is matched.
        /// For example, JetBrains folders named "WebStorm2025.2" and "WebStorm2025.3".
        var childPrefix: String? = nil
        var note: String? = nil
    }

    /// Matches an installed app whose bundle ID equals this or starts with "<this>.". Case-insensitive.
    var bundleID: String
    var locations: [Location]

    func applies(to app: AppInfo) -> Bool {
        guard let id = app.bundleID?.lowercased() else { return false }
        let key = bundleID.lowercased()
        return id == key || id.hasPrefix(key + ".")
    }
}

enum AttributionOverrides {
    static let builtIn: [AttributionOverride] = [
        AttributionOverride(bundleID: "com.apple.dt.Xcode", locations: [
            .init(path: "Library/Developer/Xcode/DerivedData", kind: .developer, safety: .safe, note: "Build products; Xcode rebuilds them"),
            .init(path: "Library/Developer/Xcode/Archives", kind: .developer, safety: .review, note: "App archives you built"),
            .init(path: "Library/Developer/Xcode/iOS DeviceSupport", kind: .developer, safety: .safe),
            .init(path: "Library/Developer/Xcode/watchOS DeviceSupport", kind: .developer, safety: .safe),
            .init(path: "Library/Developer/Xcode/tvOS DeviceSupport", kind: .developer, safety: .safe),
            .init(path: "Library/Developer/Xcode/visionOS DeviceSupport", kind: .developer, safety: .safe),
            .init(path: "Library/Developer/CoreSimulator", kind: .developer, safety: .review, note: "Simulators and their data"),
            .init(path: "Library/Caches/com.apple.dt.Xcode", kind: .cache, safety: .safe),
        ]),
        AttributionOverride(bundleID: "com.microsoft.VSCode", locations: [
            .init(path: "Library/Application Support/Code", kind: .applicationSupport, safety: .review),
            .init(path: ".vscode", kind: .applicationSupport, safety: .review, note: "Extensions"),
        ]),
        AttributionOverride(bundleID: "com.google.Chrome", locations: [
            .init(path: "Library/Application Support/Google/Chrome", kind: .applicationSupport, safety: .userData, note: "Profiles, history, and extensions"),
            .init(path: "Library/Caches/Google/Chrome", kind: .cache, safety: .safe),
        ]),
        AttributionOverride(bundleID: "com.valvesoftware.steam", locations: [
            .init(path: "Library/Application Support/Steam", kind: .applicationSupport, safety: .userData, note: "Installed games"),
        ]),
        AttributionOverride(bundleID: "com.electron.ollama", locations: [
            .init(path: ".ollama", kind: .applicationSupport, safety: .userData, note: "Downloaded models"),
        ]),
        AttributionOverride(bundleID: "com.docker.docker", locations: [
            .init(path: ".docker", kind: .applicationSupport, safety: .review),
        ]),
        AttributionOverride(bundleID: "com.unity3d.unityhub", locations: [
            .init(path: "Library/Unity", kind: .applicationSupport, safety: .review),
            .init(path: "Library/Application Support/UnityHub", kind: .applicationSupport, safety: .review),
        ]),
        jetBrains(bundleID: "com.jetbrains.WebStorm", product: "WebStorm"),
        jetBrains(bundleID: "com.jetbrains.datagrip", product: "DataGrip"),
        jetBrains(bundleID: "com.jetbrains.intellij", product: "IntelliJIdea"),
        jetBrains(bundleID: "com.jetbrains.pycharm", product: "PyCharm"),
        jetBrains(bundleID: "com.jetbrains.goland", product: "GoLand"),
        jetBrains(bundleID: "com.google.android.studio", product: "Google/AndroidStudio"),
    ]

    /// Identifiers that look like bundle IDs but belong to command-line tools or to frameworks that
    /// many apps embed. They're never reported as "leftovers from an uninstalled app".
    /// (Tool caches such as SwiftPM's are handled by the developer cleanup rules instead.)
    static let nonAppIdentifierPrefixes: [String] = [
        "org.swift.", "com.breakpad.", "org.sparkle-project.", "io.sentry", "com.crashlytics",
        "com.google.keystone", "com.microsoft.autoupdate", "org.python.", "org.nodejs.", "com.github.",
        "homebrew.", "org.homebrew.", "com.docker.", "com.electron.",
    ]

    static func isNonAppIdentifier(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        return nonAppIdentifierPrefixes.contains { lower.hasPrefix($0.lowercased()) }
    }

    private static func jetBrains(bundleID: String, product: String) -> AttributionOverride {
        let vendor = product.contains("/") ? "" : "JetBrains/"
        let parts = (vendor + product).split(separator: "/")
        let folder = parts.dropLast().joined(separator: "/")
        let prefix = String(parts.last ?? "")
        return AttributionOverride(bundleID: bundleID, locations: [
            .init(path: "Library/Caches/\(folder)", kind: .cache, safety: .safe, childPrefix: prefix),
            .init(path: "Library/Logs/\(folder)", kind: .logs, safety: .safe, childPrefix: prefix),
            .init(path: "Library/Application Support/\(folder)", kind: .applicationSupport, safety: .review, childPrefix: prefix),
        ])
    }
}
