import Foundation

/// One ring segment of the sunburst. Angles are in radians, clockwise from 12 o'clock.
struct SunburstArc: Identifiable, Sendable {
    let id: Int
    /// `nil` for the "smaller items" segment that merges children too thin to draw.
    let node: FileNode?
    let mergedCount: Int
    let mergedSize: Int64
    let depth: Int
    let start: Double
    let end: Double
    /// Index of the top-level child this arc descends from. Used for colour.
    let colorIndex: Int

    var span: Double { end - start }
    var size: Int64 { node?.size ?? mergedSize }
    var title: String { node?.name ?? "\(mergedCount) smaller items" }
}

/// Lays out a folder tree as concentric rings: one ring per depth level, with each item's angle
/// proportional to its size. Pure computation, so it can be tested without drawing.
enum SunburstLayout {
    static func make(root: FileNode, maxDepth: Int = 5, minAngle: Double = 0.5 * .pi / 180) -> [SunburstArc] {
        var arcs: [SunburstArc] = []
        var nextID = 0
        guard root.size > 0 else { return [] }

        func layout(_ node: FileNode, depth: Int, start: Double, end: Double, colorIndex: Int?) {
            guard depth <= maxDepth, node.size > 0 else { return }
            let span = end - start
            var angle = start
            var mergedCount = 0
            var mergedSize: Int64 = 0
            for (index, child) in node.children.enumerated() where child.size > 0 {
                let childSpan = span * Double(child.size) / Double(node.size)
                if childSpan < minAngle {
                    mergedCount += 1
                    mergedSize += child.size
                    continue
                }
                let color = colorIndex ?? index
                arcs.append(SunburstArc(id: nextID, node: child, mergedCount: 0, mergedSize: 0, depth: depth,
                                        start: angle, end: angle + childSpan, colorIndex: color))
                nextID += 1
                if child.isDirectory {
                    layout(child, depth: depth + 1, start: angle, end: angle + childSpan, colorIndex: color)
                }
                angle += childSpan
            }
            if mergedCount > 0 {
                let mergedSpan = span * Double(mergedSize) / Double(node.size)
                if mergedSpan > 0 {
                    arcs.append(SunburstArc(id: nextID, node: nil, mergedCount: mergedCount, mergedSize: mergedSize, depth: depth,
                                            start: angle, end: angle + mergedSpan, colorIndex: -1))
                    nextID += 1
                }
            }
        }

        layout(root, depth: 1, start: 0, end: 2 * .pi, colorIndex: nil)
        return arcs
    }

    /// Finds the arc under a point, given the chart's geometry. Returns nil for the centre or empty space.
    static func hitTest(_ arcs: [SunburstArc], point: CGPoint, center: CGPoint, innerRadius: Double, ringWidth: Double) -> SunburstArc? {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let radius = (dx * dx + dy * dy).squareRoot()
        guard radius >= innerRadius else { return nil }
        let depth = Int((radius - innerRadius) / ringWidth) + 1
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        return arcs.first { $0.depth == depth && angle >= $0.start && angle < $0.end }
    }
}
