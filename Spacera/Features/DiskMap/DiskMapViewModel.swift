import Foundation
import Observation

@MainActor
@Observable
final class DiskMapViewModel {
    private let store: ScanStore
    /// Folders drilled into, from the root's child downwards.
    private(set) var trail: [FileNode] = []
    private var trailRootID: ObjectIdentifier?
    var hovered: FileNode?
    var review: ReviewViewModel?
    @ObservationIgnored private var cachedPlan: TreemapPlan?

    init(store: ScanStore) {
        self.store = store
    }

    var root: FileNode? { store.result?.root }

    var current: FileNode? {
        guard let root else { return nil }
        if trailRootID != root.id { return root } // a new scan replaced the tree
        return trail.last ?? root
    }

    /// Breadcrumb: the root, then each folder drilled into.
    var breadcrumbs: [FileNode] {
        guard let root else { return [] }
        return trailRootID == root.id ? [root] + trail : [root]
    }

    func displayName(_ node: FileNode) -> String {
        if node === root {
            let path = ScanResult.logicalPath(node.name)
            return path == "/" ? (store.result?.volume.name ?? "Disk") : URL(fileURLWithPath: path).lastPathComponent
        }
        return node.name
    }

    /// The current folder's blocks. Made once per folder, so hovering doesn't sort the children again.
    var plan: TreemapPlan? {
        guard let current else { return nil }
        if let cachedPlan, cachedPlan.folder === current, cachedPlan.folderSize == current.size { return cachedPlan }
        let plan = TreemapPlan(folder: current)
        cachedPlan = plan
        return plan
    }

    /// Children of the current folder, largest first, for the list beside the chart.
    var children: [FileNode] { plan?.children ?? [] }

    func drill(into node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty, let root else { return }
        if trailRootID != root.id {
            trail = []
            trailRootID = root.id
        }
        // Build the trail from the root down to this node, so drilling from a deep ring works too.
        var chain: [FileNode] = []
        var cursor: FileNode? = node
        while let n = cursor, n !== root {
            chain.append(n)
            cursor = n.parent
        }
        trail = chain.reversed()
        hovered = nil
    }

    /// Hover from the chart or the list. Leaving a block only clears the hover if it's still the hovered one,
    /// because moving between blocks can report the new block before the old one.
    func setHover(_ node: FileNode, _ inside: Bool) {
        if inside { hovered = node } else if hovered === node { hovered = nil }
    }

    func goUp() {
        if !trail.isEmpty { trail.removeLast() }
        hovered = nil
    }

    func jump(to node: FileNode) {
        if node === root { trail = [] } else if let index = trail.firstIndex(where: { $0 === node }) {
            trail = Array(trail.prefix(through: index))
        }
        hovered = nil
    }

    /// App bundles in the map show their icon.
    func iconPath(for node: FileNode) -> String? {
        node.name.hasSuffix(".app") ? ScanResult.logicalPath(node.path) : nil
    }

    func fraction(of node: FileNode) -> Double {
        guard let current, current.size > 0 else { return 0 }
        return Double(node.size) / Double(current.size)
    }

    func path(of node: FileNode) -> String { ScanResult.logicalPath(node.path) }

    func startReview(for node: FileNode) {
        let item = CleanupItem(node: node, ruleID: "diskMap", safety: .review)
        review = ReviewViewModel(items: [item], store: store)
    }
}
