import Foundation
import Observation

/// The latest scan and everything derived from it. All features read from here.
/// A scan runs in three stages: scan the disk, match data to apps, then run the cleanup rules.
@MainActor
@Observable
final class ScanStore {
    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
        case matchingApps
        case findingCleanup
        case done
        case failed(String)

        var isWorking: Bool {
            switch self {
            case .scanning, .matchingApps, .findingCleanup: true
            default: false
            }
        }

        var title: String {
            switch self {
            case .idle: "Ready"
            case .scanning: "Scanning disk…"
            case .matchingApps: "Matching data to apps…"
            case .findingCleanup: "Looking for things to clean…"
            case .done: "Scan complete"
            case .failed(let message): "Scan failed: \(message)"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var result: ScanResult?
    private(set) var attribution: AttributionResult?
    private(set) var findings: [RuleFinding] = []
    private(set) var hasFullDiskAccess: Bool
    /// True when the last scan covered only the home folder, because Full Disk Access was missing.
    private(set) var isLimitedScan = false
    /// The most recent saved scan summary. Shown at launch, before a new scan has run.
    private(set) var lastSnapshot: ScanSnapshot?
    /// The apps in `lastSnapshot`, largest first, with icons for the ones still installed.
    private(set) var lastSnapshotApps: [SnapshotApp] = []
    /// What changed since the previous scan. `nil` for the first scan.
    private(set) var growth: GrowthReport?
    /// Bytes moved to the Trash since the last scan. The disk map is a snapshot and doesn't shrink until the next scan.
    private(set) var trashedSinceScan: Int64 = 0

    let services: Services
    private var task: Task<Void, Never>?

    init(services: Services) {
        self.services = services
        self.hasFullDiskAccess = services.access.hasFullDiskAccess()
    }

    /// Loads the last saved scan summary, so the app has something to show right away.
    func loadLastSnapshot() async {
        setLastSnapshot(await services.snapshots.latest())
    }

    private func setLastSnapshot(_ snapshot: ScanSnapshot?) {
        lastSnapshot = snapshot
        // Checked once here rather than on every redraw: an app may have been deleted since the scan.
        lastSnapshotApps = (snapshot?.apps ?? []).sorted { $0.total > $1.total }.map {
            SnapshotApp(summary: $0, iconPath: FileManager.default.fileExists(atPath: $0.path) ? $0.path : nil)
        }
    }

    func refreshAccess() {
        hasFullDiskAccess = services.access.hasFullDiskAccess()
    }

    func startScan() {
        task?.cancel()
        task = Task { await run() }
    }

    func cancelScan() {
        task?.cancel()
        task = nil
        phase = result == nil ? .idle : .done
    }

    /// Waits for the current scan to finish. Used by tests.
    func waitForScan() async { await task?.value }

    private func run() async {
        refreshAccess()
        let root = hasFullDiskAccess ? ScanOptions.fullDiskRoot : services.locations.home
        phase = .scanning(ScanProgress(bytes: 0, files: 0, directories: 0, currentPath: root.path))

        var scanned: ScanResult?
        do {
            for try await event in services.scanner.scan(root: root, options: ScanOptions()) {
                switch event {
                case .progress(let progress): phase = .scanning(progress)
                case .finished(let result): scanned = result
                }
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        guard let scanned, !Task.isCancelled else { return }

        phase = .matchingApps
        let apps = await services.catalog.discoverApps()
        let attribution = await services.resolver.resolve(apps: apps, scan: scanned)
        guard !Task.isCancelled else { return }

        phase = .findingCleanup
        let context = RuleContext(locations: services.locations, scan: scanned, attribution: attribution, commands: services.commands)
        let findings = await services.rules.run(context)
        guard !Task.isCancelled else { return }

        result = scanned
        self.attribution = attribution
        self.findings = findings
        isLimitedScan = !hasFullDiskAccess
        trashedSinceScan = 0

        let snapshot = ScanSnapshot.make(result: scanned, attribution: attribution, findings: findings, isLimitedScan: isLimitedScan)
        let previous = await services.snapshots.latest()
        growth = previous.map { GrowthReport.compare(previous: $0, current: snapshot) }
        await services.snapshots.append(snapshot)
        setLastSnapshot(snapshot)
        phase = .done
    }

    // MARK: After a cleanup

    /// Removes trashed items from the app footprints, leftovers, and findings, so every screen updates right away.
    func didTrash(_ batch: TrashBatch) {
        let removed = Set(batch.outcomes.filter { $0.status == .trashed }.map(\.item.path))
        guard !removed.isEmpty else { return }
        trashedSinceScan += batch.trashedSize

        func isRemoved(_ path: String) -> Bool {
            removed.contains(path) || removed.contains { path.hasPrefix($0 + "/") }
        }
        findings = findings.compactMap { finding in
            var f = finding
            f.items.removeAll { isRemoved($0.path) }
            return f.items.isEmpty ? nil : f
        }
        if var attribution {
            for i in attribution.footprints.indices {
                attribution.footprints[i].entries.removeAll { isRemoved($0.path) }
            }
            attribution.footprints.removeAll { $0.entries.isEmpty }
            for i in attribution.leftovers.indices {
                attribution.leftovers[i].entries.removeAll { isRemoved($0.path) }
            }
            attribution.leftovers.removeAll { $0.entries.isEmpty }
            self.attribution = attribution
        }
    }

    // MARK: Lookups

    func footprint(id: String) -> AppFootprint? { attribution?.footprints.first { $0.id == id } }
    func leftover(id: String) -> LeftoverGroup? { attribution?.leftovers.first { $0.id == id } }
    func app(bundleID: String) -> AppInfo? {
        attribution?.footprints.first { $0.app.bundleID?.lowercased() == bundleID.lowercased() }?.app
    }
}
