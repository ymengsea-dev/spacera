import Foundation
import Observation

@MainActor
@Observable
final class CleanupViewModel {
    private let store: ScanStore
    var selected: Set<String> = []
    var expanded: Set<String> = []
    var review: ReviewViewModel?
    private(set) var history: [TrashBatch] = []
    private var seededForScan: Date?

    init(store: ScanStore) {
        self.store = store
    }

    var hasResult: Bool { store.result != nil }
    var isLimitedScan: Bool { store.isLimitedScan }

    var findings: [RuleFinding] { store.findings }

    /// Findings grouped by category, in a fixed order.
    var sections: [(category: CleanupCategory, findings: [RuleFinding])] {
        CleanupCategory.allCases.compactMap { category in
            let list = store.findings.filter { $0.rule.category == category }.sorted { $0.totalSize > $1.totalSize }
            return list.isEmpty ? nil : (category, list)
        }
    }

    /// After every new scan, pre-select only the items marked safe.
    func syncSelection() {
        guard let date = store.result?.date, date != seededForScan else { return }
        seededForScan = date
        selected = Set(store.findings.filter { $0.rule.safety == .safe }.flatMap(\.items).map(\.path))
    }

    var selectedItems: [CleanupItem] {
        store.findings.flatMap(\.items).filter { selected.contains($0.path) && $0.safety != .infoOnly }
    }

    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func selectedSize(in finding: RuleFinding) -> Int64 {
        finding.items.filter { selected.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    enum SelectionState { case none, some, all }

    func selectionState(of finding: RuleFinding) -> SelectionState {
        let count = finding.items.filter { selected.contains($0.path) }.count
        return count == 0 ? .none : (count == finding.items.count ? .all : .some)
    }

    func toggle(_ item: CleanupItem) {
        if selected.contains(item.path) { selected.remove(item.path) } else { selected.insert(item.path) }
    }

    func toggleAll(in finding: RuleFinding) {
        let paths = finding.items.map(\.path)
        if selectionState(of: finding) == .all { selected.subtract(paths) } else { selected.formUnion(paths) }
    }

    func toggleExpanded(_ finding: RuleFinding) {
        if expanded.contains(finding.id) { expanded.remove(finding.id) } else { expanded.insert(finding.id) }
    }

    func startReview() {
        review = ReviewViewModel(items: selectedItems, store: store)
    }

    // MARK: History

    func loadHistory() async {
        history = await store.services.log.allBatches()
    }

    func putBack(_ outcome: TrashOutcome) async {
        _ = await store.services.trasher.putBack(outcome)
        await loadHistory()
    }
}
