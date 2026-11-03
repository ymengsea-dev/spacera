import Foundation

/// A compact summary of one scan, saved to disk so the app can show the last results at launch
/// and report what grew. It holds only names, paths, and sizes, never file contents.
struct ScanSnapshot: Codable, Sendable, Identifiable, Equatable {
    struct AppSummary: Codable, Sendable, Equatable {
        /// Bundle ID when available, otherwise the bundle path. Used to match apps across scans.
        var key: String
        var name: String
        var path: String
        var bundleSize: Int64
        var dataSize: Int64
        var total: Int64 { bundleSize + dataSize }
    }

    struct CategorySummary: Codable, Sendable, Equatable {
        var ruleID: String
        var title: String
        var bytes: Int64
    }

    var id: UUID
    var date: Date
    var volume: VolumeInfo
    var isLimitedScan: Bool
    var apps: [AppSummary]
    var categories: [CategorySummary]
    var leftoverBytes: Int64
    var safeReclaimable: Int64

    static func make(result: ScanResult, attribution: AttributionResult, findings: [RuleFinding], isLimitedScan: Bool) -> ScanSnapshot {
        ScanSnapshot(
            id: UUID(),
            date: result.date,
            volume: result.volume,
            isLimitedScan: isLimitedScan,
            apps: attribution.footprints.filter { $0.totalSize > 0 }.map {
                AppSummary(key: $0.app.bundleID ?? $0.app.url.path, name: $0.app.name, path: $0.app.url.path,
                           bundleSize: $0.bundleSize, dataSize: $0.dataSize)
            },
            categories: findings.map { CategorySummary(ruleID: $0.rule.id, title: $0.rule.title, bytes: $0.totalSize) },
            leftoverBytes: attribution.leftovers.reduce(0) { $0 + $1.totalSize },
            safeReclaimable: findings.filter { $0.rule.safety == .safe }.reduce(0) { $0 + $1.totalSize }
        )
    }
}

/// What changed between two scans.
struct GrowthReport: Sendable, Equatable {
    struct Change: Sendable, Equatable, Identifiable {
        var id: String
        var title: String
        /// Bundle path, for showing the app's icon. `nil` for categories.
        var iconPath: String?
        var delta: Int64
        var isNew: Bool
    }

    var previousDate: Date
    var usedDelta: Int64
    /// Largest increases first, then decreases. Only changes of at least `threshold` bytes.
    var apps: [Change]
    var categories: [Change]
    /// The two scans covered different areas (one had Full Disk Access, one didn't), so app sizes aren't comparable.
    var comparesDifferentScopes: Bool

    static let threshold: Int64 = 50_000_000

    static func compare(previous: ScanSnapshot, current: ScanSnapshot, threshold: Int64 = GrowthReport.threshold) -> GrowthReport {
        let before = Dictionary(previous.apps.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var apps: [Change] = []
        for app in current.apps {
            let old = before[app.key]?.total ?? 0
            let delta = app.total - old
            if abs(delta) >= threshold {
                apps.append(Change(id: app.key, title: app.name, iconPath: app.path, delta: delta, isNew: before[app.key] == nil))
            }
        }
        let currentKeys = Set(current.apps.map(\.key))
        for old in previous.apps where !currentKeys.contains(old.key) && old.total >= threshold {
            apps.append(Change(id: old.key, title: old.name, iconPath: nil, delta: -old.total, isNew: false))
        }

        let oldCategories = Dictionary(previous.categories.map { ($0.ruleID, $0.bytes) }, uniquingKeysWith: { a, _ in a })
        var categories: [Change] = []
        for category in current.categories {
            let delta = category.bytes - (oldCategories[category.ruleID] ?? 0)
            if abs(delta) >= threshold {
                categories.append(Change(id: category.ruleID, title: category.title, iconPath: nil, delta: delta, isNew: oldCategories[category.ruleID] == nil))
            }
        }

        func order(_ list: [Change]) -> [Change] { list.sorted { $0.delta > $1.delta } }
        return GrowthReport(
            previousDate: previous.date,
            usedDelta: current.volume.usedCapacity - previous.volume.usedCapacity,
            apps: order(apps),
            categories: order(categories),
            comparesDifferentScopes: previous.isLimitedScan != current.isLimitedScan
        )
    }
}
