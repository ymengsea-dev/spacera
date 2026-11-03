import AppKit
import Foundation
import Observation

/// The review step before anything is moved to the Trash. Every screen goes through this.
@MainActor
@Observable
final class ReviewViewModel: Identifiable {
    enum Stage {
        case review
        case working
        case done(TrashBatch)
    }

    let id = UUID()
    private let items: [CleanupItem]
    private let store: ScanStore
    private(set) var plan: CleanupPlan
    private(set) var stage: Stage = .review
    var confirmedUserData = false

    init(items: [CleanupItem], store: ScanStore) {
        self.items = items
        self.store = store
        self.plan = store.services.planner.plan(items)
    }

    var canConfirm: Bool {
        guard case .review = stage else { return false }
        return !plan.entries.isEmpty && (!plan.requiresUserDataConfirmation || confirmedUserData)
    }

    var groupedEntries: [(SafetyLevel, [CleanupPlan.Entry])] {
        let groups = Dictionary(grouping: plan.entries) { $0.item.safety }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    func appName(for bundleID: String) -> String {
        store.app(bundleID: bundleID)?.name ?? bundleID
    }

    /// Asks a running app to quit (like choosing Quit from its menu), then rebuilds the plan.
    func quit(bundleID: String) async {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.terminate()
        }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(150))
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { break }
        }
        plan = store.services.planner.plan(items)
    }

    func moveToTrash() async {
        guard canConfirm else { return }
        stage = .working
        let batch = await store.services.trasher.trash(plan.entries.map(\.item))
        store.didTrash(batch)
        stage = .done(batch)
    }
}
