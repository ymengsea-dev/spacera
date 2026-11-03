import SwiftUI

/// Draws the sunburst with `Canvas` (which stays fast with thousands of segments) and handles hover and clicks.
struct SunburstView: View {
    var arcs: [SunburstArc]
    var maxDepth: Int
    var centerTitle: String
    var centerSize: Int64
    var hovered: SunburstArc?
    var iconPath: (FileNode) -> String?
    var onHover: (SunburstArc?) -> Void
    var onSelect: (SunburstArc) -> Void
    var onCenter: () -> Void

    static let palette: [Color] = [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .cyan, .indigo, .mint, .red, .brown]

    struct Geometry {
        var center: CGPoint
        var inner: Double
        var ring: Double

        init(size: CGSize, maxDepth: Int) {
            let radius = Double(min(size.width, size.height)) / 2 - 6
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            inner = radius * 0.26
            ring = (radius - inner) / Double(max(1, maxDepth))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = Geometry(size: proxy.size, maxDepth: maxDepth)
            ZStack {
                Canvas { context, _ in
                    for arc in arcs {
                        let path = Self.sector(arc, geometry)
                        context.fill(path, with: .color(color(for: arc)))
                        context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 0.6)
                    }
                    if let hovered {
                        context.stroke(Self.sector(hovered, geometry), with: .color(.primary), lineWidth: 2)
                    }
                    // App icons on large enough app segments.
                    for arc in arcs where arc.node?.name.hasSuffix(".app") == true {
                        let midRadius = geometry.inner + geometry.ring * (Double(arc.depth) - 0.5)
                        let iconSize = min(geometry.ring * 0.7, arc.span * midRadius * 0.7, 40)
                        guard iconSize >= 16, let node = arc.node, let path = iconPath(node) else { continue }
                        let mid = arc.start + arc.span / 2 - .pi / 2
                        let point = CGPoint(x: geometry.center.x + midRadius * cos(mid), y: geometry.center.y + midRadius * sin(mid))
                        let image = Image(nsImage: IconCache.shared.icon(for: path))
                        context.draw(image, in: CGRect(x: point.x - iconSize / 2, y: point.y - iconSize / 2, width: iconSize, height: iconSize))
                    }
                }
                CenterLabel(title: hovered?.title ?? centerTitle, size: hovered?.size ?? centerSize,
                            showsUp: hovered == nil, diameter: geometry.inner * 2)
                    .position(geometry.center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    onHover(SunburstLayout.hitTest(arcs, point: point, center: geometry.center, innerRadius: geometry.inner, ringWidth: geometry.ring))
                case .ended:
                    onHover(nil)
                }
            }
            .onTapGesture { point in
                let dx = point.x - geometry.center.x, dy = point.y - geometry.center.y
                if (dx * dx + dy * dy).squareRoot() < geometry.inner {
                    onCenter()
                } else if let arc = SunburstLayout.hitTest(arcs, point: point, center: geometry.center, innerRadius: geometry.inner, ringWidth: geometry.ring) {
                    onSelect(arc)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk map of \(centerTitle), \(centerSize.formattedBytes). The list beside the chart has the same items.")
    }

    private func color(for arc: SunburstArc) -> Color {
        guard arc.colorIndex >= 0 else { return Color(nsColor: .tertiaryLabelColor).opacity(0.35) }
        let base = Self.palette[arc.colorIndex % Self.palette.count]
        let fade = 1.0 - Double(arc.depth - 1) * 0.14
        let isHovered = hovered?.id == arc.id
        return base.opacity(isHovered ? 1 : max(0.35, fade * 0.92))
    }

    static func sector(_ arc: SunburstArc, _ geometry: Geometry) -> Path {
        let inner = geometry.inner + geometry.ring * Double(arc.depth - 1)
        let outer = inner + geometry.ring
        let start = Angle.radians(arc.start - .pi / 2)
        let end = Angle.radians(arc.end - .pi / 2)
        var path = Path()
        path.addArc(center: geometry.center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: geometry.center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct CenterLabel: View {
    var title: String
    var size: Int64
    var showsUp: Bool
    var diameter: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            SizeLabel(bytes: size, font: .title3.weight(.semibold))
            if showsUp {
                Text("Click to go up").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter * 0.82)
    }
}
