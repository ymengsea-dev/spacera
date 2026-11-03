import AppKit
import Foundation

protocol RunningAppsProviding: Sendable {
    func runningBundleIDs() -> Set<String>
}

struct WorkspaceRunningApps: RunningAppsProviding {
    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }
}

/// What the review sheet shows before anything is moved to the Trash.
struct CleanupPlan: Sendable {
    enum Warning: Sendable, Equatable {
        /// The app that owns this data is open. Quit it first, or it may misbehave or recreate the files.
        case ownerRunning(bundleID: String)
        /// The item changed after the scan, so the size shown may be out of date.
        case changedSinceScan
        /// The item no longer exists.
        case missing
    }

    struct Entry: Sendable, Identifiable {
        var item: CleanupItem
        var warnings: [Warning]
        var id: String { item.id }
    }

    /// Items that will be moved to the Trash, safest first.
    var entries: [Entry]
    /// Items SafetyGuard refused, or that are information-only, with the reason. These are never touched.
    var rejected: [(item: CleanupItem, reason: String)]

    var totalSize: Int64 { entries.reduce(0) { $0 + $1.item.size } }
    /// True if any item is the user's own data. The UI must then ask for an extra confirmation.
    var requiresUserDataConfirmation: Bool { entries.contains { $0.item.safety == .userData } }
    var runningOwners: Set<String> {
        Set(entries.flatMap(\.warnings).compactMap { if case .ownerRunning(let id) = $0 { id } else { nil } })
    }
}

struct CleanupPlanner: Sendable {
    var guardrail: SafetyGuard = .standard()
    var runningApps: RunningAppsProviding = WorkspaceRunningApps()

    func plan(_ items: [CleanupItem]) -> CleanupPlan {
        let running = runningApps.runningBundleIDs()
        var entries: [CleanupPlan.Entry] = []
        var rejected: [(CleanupItem, String)] = []
        var seen = Set<String>()

        for item in items where seen.insert(item.path).inserted {
            if item.safety == .infoOnly {
                rejected.append((item, "Shown for information only"))
                continue
            }
            if case .blocked(let reason) = guardrail.check(item.path) {
                rejected.append((item, reason))
                continue
            }
            var warnings: [CleanupPlan.Warning] = []
            var info = stat()
            if lstat(item.path, &info) != 0 {
                warnings.append(.missing)
            } else if let scanned = item.modificationTime, abs(TimeInterval(info.st_mtimespec.tv_sec) - scanned.rounded(.down)) > 1 {
                warnings.append(.changedSinceScan)
            }
            if let owner = item.ownerBundleID?.lowercased(), running.contains(owner) {
                warnings.append(.ownerRunning(bundleID: owner))
            }
            entries.append(.init(item: item, warnings: warnings))
        }
        entries.sort { ($0.item.safety, -$0.item.size) < ($1.item.safety, -$1.item.size) }
        return CleanupPlan(entries: entries, rejected: rejected)
    }
}
