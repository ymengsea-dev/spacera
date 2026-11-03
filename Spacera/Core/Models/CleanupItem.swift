import Foundation

/// One thing the user could move to the Trash.
struct CleanupItem: Sendable, Hashable, Identifiable, Codable {
    var path: String
    var size: Int64
    /// The `CleanupRule.id` that found it, or "app:<bundleID>" when it was picked on an app's page.
    var ruleID: String
    var safety: SafetyLevel
    /// The bundle ID of the app this data belongs to, if known. Used to warn when that app is running.
    var ownerBundleID: String?
    /// Seconds since 1970 when scanned. Used to warn if the item changed since the scan.
    var modificationTime: TimeInterval?
    var note: String?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

extension CleanupItem {
    init(node: FileNode, ruleID: String, safety: SafetyLevel, ownerBundleID: String? = nil, note: String? = nil) {
        self.init(
            path: ScanResult.logicalPath(node.path),
            size: node.size,
            ruleID: ruleID,
            safety: safety,
            ownerBundleID: ownerBundleID,
            modificationTime: node.modificationTime == 0 ? nil : node.modificationTime,
            note: note
        )
    }

    init(entry: FootprintEntry, app: AppInfo?) {
        self.init(
            path: entry.path,
            size: entry.size,
            ruleID: app?.bundleID.map { "app:\($0)" } ?? "leftover",
            safety: entry.safety,
            ownerBundleID: app?.bundleID,
            modificationTime: nil,
            note: entry.note
        )
    }
}
