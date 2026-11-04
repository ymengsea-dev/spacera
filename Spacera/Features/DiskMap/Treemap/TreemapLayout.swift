import Foundation

/// One block of the disk map. `rect` is in the chart's own coordinates.
struct TreemapTile: Identifiable, Sendable {
    let id: Int
    /// `nil` for the "smaller items" block that merges children too small to draw.
    let node: FileNode?
    let mergedCount: Int
    let mergedSize: Int64
    let rect: CGRect
    /// Index of the child among the folder's non-empty children, so it matches the list. -1 for merged items.
    let colorIndex: Int

    var size: Int64 { node?.size ?? mergedSize }
    var title: String { node?.name ?? "\(mergedCount) smaller items" }
}

/// Which of a folder's children get their own block. Sorting and merging is the slow part of the layout
/// (a folder can hold tens of thousands of items), so it's worked out once per folder, then placed at any size.
struct TreemapPlan: Sendable {
    let folder: FileNode
    /// The folder's size when the plan was made.
    let folderSize: Int64
    /// Non-empty children, largest first. The list beside the chart shows them in this order.
    let children: [FileNode]
    /// The first `shownCount` children get their own block. The rest share one "smaller items" block.
    let shownCount: Int
    let mergedSize: Int64
    private let mergedIDs: Set<ObjectIdentifier>

    /// A child keeps its own block if it's at least `minShare` of the folder, or at least `minOfLargest` of the
    /// largest child, so a folder of many similar items isn't merged into one block. At most `maxTiles` blocks.
    init(folder: FileNode, minShare: Double = 0.004, minOfLargest: Double = 0.25, maxTiles: Int = 200) {
        let children = folder.children.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let total = Double(children.reduce(Int64(0)) { $0 + $1.size })
        let largest = Double(children.first?.size ?? 0)
        // Children are sorted, so the ones that keep a block are always a prefix.
        var shown = children.prefix(maxTiles).prefix { child in
            Double(child.size) >= total * minShare || Double(child.size) >= largest * minOfLargest
        }.count
        if children.count - shown == 1 { shown += 1 } // one item needs no "1 smaller item" block
        let merged = children[shown...]

        self.folder = folder
        self.folderSize = folder.size
        self.children = children
        self.shownCount = shown
        self.mergedSize = merged.reduce(0) { $0 + $1.size }
        self.mergedIDs = Set(merged.map(\.id))
    }

    var mergedCount: Int { children.count - shownCount }

    /// True if the child is drawn as part of the "smaller items" block.
    func isMerged(_ node: FileNode) -> Bool { mergedIDs.contains(node.id) }
}

/// Lays out a folder's children as blocks whose area is proportional to their size ("squarified" treemap,
/// which keeps blocks close to square so they're easy to compare). Pure computation, so it can be tested without drawing.
enum TreemapLayout {
    static func make(root: FileNode, in bounds: CGRect, minShare: Double = 0.004, maxTiles: Int = 200) -> [TreemapTile] {
        tiles(for: TreemapPlan(folder: root, minShare: minShare, maxTiles: maxTiles), in: bounds)
    }

    static func tiles(for plan: TreemapPlan, in bounds: CGRect) -> [TreemapTile] {
        let shown = plan.children.prefix(plan.shownCount)
        let total = shown.reduce(plan.mergedSize) { $0 + $1.size }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }

        var values = shown.map { Double($0.size) }
        if plan.mergedSize > 0 { values.append(Double(plan.mergedSize)) }
        let scale = Double(bounds.width * bounds.height) / Double(total)
        let rects = squarify(values.map { $0 * scale }, in: bounds)

        var tiles = zip(shown, rects).enumerated().map { index, pair in
            TreemapTile(id: index, node: pair.0, mergedCount: 0, mergedSize: 0, rect: pair.1, colorIndex: index)
        }
        if plan.mergedSize > 0, let rect = rects.last {
            tiles.append(TreemapTile(id: tiles.count, node: nil, mergedCount: plan.mergedCount, mergedSize: plan.mergedSize, rect: rect, colorIndex: -1))
        }
        return tiles
    }

    static func hitTest(_ tiles: [TreemapTile], point: CGPoint) -> TreemapTile? {
        tiles.first { $0.rect.contains(point) }
    }

    /// Places areas (largest first) in rows along the shorter side, adding to a row while that keeps its blocks squarer.
    private static func squarify(_ areas: [Double], in bounds: CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        var remaining = bounds
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            while end < areas.count, worst(areas[start...end], side: side) <= worst(areas[start..<end], side: side) {
                end += 1
            }
            let row = areas[start..<end]
            let rowArea = row.reduce(0, +)
            if remaining.width >= remaining.height {
                // A column on the left.
                let width = rowArea / Double(remaining.height)
                var y = Double(remaining.minY)
                for area in row {
                    let height = area / width
                    rects.append(CGRect(x: Double(remaining.minX), y: y, width: width, height: height))
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: max(0, remaining.width - width), height: remaining.height)
            } else {
                // A row along the top.
                let height = rowArea / Double(remaining.width)
                var x = Double(remaining.minX)
                for area in row {
                    let width = area / height
                    rects.append(CGRect(x: x, y: Double(remaining.minY), width: width, height: height))
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: max(0, remaining.height - height))
            }
            start = end
        }
        return rects
    }

    /// The worst aspect ratio in a row laid along a side of the given length.
    private static func worst(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard let largest = row.max(), let smallest = row.min(), sum > 0, smallest > 0, side > 0 else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * largest / sumSquared, sumSquared / (sideSquared * smallest))
    }
}
