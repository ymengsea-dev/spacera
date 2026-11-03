import Foundation

/// The last line of defence: decides whether a path may be moved to the Trash at all.
/// Every removal goes through `check(_:)`, whichever rule or screen asked for it. See docs/05-cleanup-safety.md.
struct SafetyGuard: Sendable {
    enum Verdict: Sendable, Equatable {
        case allowed
        case blocked(reason: String)

        var isAllowed: Bool { self == .allowed }
    }

    var home: String
    /// Items must be inside one of these.
    var allowedRoots: [String]
    /// Never allowed, at any depth.
    var protectedPrefixes: [String]
    /// Never allowed themselves; things *inside* them are fine.
    var protectedExactPaths: Set<String>
    /// Folders whose direct children are never allowed (for example, `~/Library/Caches` itself).
    var protectedChildrenOf: Set<String>

    static func standard(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        appBundle: String = Bundle.main.bundlePath,
        supportFolder: String? = nil
    ) -> SafetyGuard {
        let h = Self.normalize(home)
        let support = supportFolder ?? h + "/Library/Application Support/Spacera"
        return SafetyGuard(
            home: h,
            allowedRoots: [h, "/Library", "/Applications", "/Users/Shared"],
            protectedPrefixes: [
                "/System", "/usr", "/bin", "/sbin", "/private", "/etc", "/var", "/cores", "/opt", "/Volumes",
                "/Library/Apple", "/System/Applications",
                // Deleting these deletes data in the cloud, or the user's core personal data.
                h + "/Library/Mobile Documents", h + "/Library/CloudStorage", h + "/Library/Keychains",
                h + "/Library/Mail", h + "/Library/Messages", h + "/Library/Photos",
                h + "/Library/Accounts", h + "/Library/Calendars", h + "/Library/Safari",
                h + "/Pictures/Photos Library.photoslibrary",
                Self.normalize(appBundle), support,
            ],
            protectedExactPaths: [
                "/", "/Applications", "/Library", "/Users", "/Users/Shared",
                h, h + "/Library", h + "/Applications", h + "/Desktop", h + "/Documents", h + "/Downloads",
                h + "/Movies", h + "/Music", h + "/Pictures", h + "/Public", h + "/.Trash",
            ],
            protectedChildrenOf: [h + "/Library", "/Library"]
        )
    }

    func check(_ path: String) -> Verdict {
        // Check the raw input before normalizing, because normalizing would collapse "..".
        if path.split(separator: "/").contains("..") || path.split(separator: "/").contains(".") {
            return .blocked(reason: "Path contains “..” or “.”")
        }
        let literal = Self.normalize(path)
        guard literal.hasPrefix("/"), literal.count > 1 else { return .blocked(reason: "Not a valid path") }

        // Check the path as written, and again with every symlink in its parent folders resolved,
        // so a symlinked folder can't redirect a removal somewhere protected.
        // The last component isn't resolved: trashing a symlink moves only the link itself.
        let parent = URL(fileURLWithPath: literal).deletingLastPathComponent().resolvingSymlinksInPath().path
        let resolved = Self.normalize(parent + "/" + URL(fileURLWithPath: literal).lastPathComponent)

        for candidate in Set([literal, resolved]) {
            if let reason = blockReason(for: candidate) { return .blocked(reason: reason) }
        }
        if let reason = appleAppReason(literal) { return .blocked(reason: reason) }
        return .allowed
    }

    private func blockReason(for path: String) -> String? {
        if protectedExactPaths.contains(path) { return "“\(path)” is a protected folder" }
        for prefix in protectedPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return "“\(prefix)” is protected"
        }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if protectedChildrenOf.contains(parent) {
            return "“\(path)” is a top-level system folder; only items inside it can be removed"
        }
        if !allowedRoots.contains(where: { path.hasPrefix($0 + "/") }) {
            return "Outside the areas Spacera cleans"
        }
        return nil
    }

    /// Apps that ship with macOS are never removed, even if they live in /Applications.
    private func appleAppReason(_ path: String) -> String? {
        guard path.hasSuffix(".app") else { return nil }
        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
        if let id = info?["CFBundleIdentifier"] as? String, id.lowercased().hasPrefix("com.apple.") {
            return "Apple apps that come with macOS can’t be removed"
        }
        return nil
    }

    static func normalize(_ path: String) -> String {
        var result = (path as NSString).standardizingPath
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
