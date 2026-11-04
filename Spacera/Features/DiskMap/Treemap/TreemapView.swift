import SwiftUI

/// The disk map: the current folder's children as blocks sized by how much space they use.
/// Click a folder to open it; right-click for more.
struct TreemapView<Menu: View>: View {
    var plan: TreemapPlan
    var hovered: FileNode?
    var iconPath: (FileNode) -> String?
    var onHover: (FileNode, Bool) -> Void
    var onOpen: (FileNode) -> Void
    @ViewBuilder var menu: (FileNode) -> Menu

    /// Space between neighbouring blocks, in points.
    private static var gap: CGFloat { 4 }

    var body: some View {
        GeometryReader { proxy in
            let tiles = TreemapLayout.tiles(for: plan, in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    TileView(tile: tile, state: state(of: tile), iconPath: tile.node.flatMap(iconPath))
                        .frame(width: max(0, tile.rect.width - Self.gap), height: max(0, tile.rect.height - Self.gap))
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                        .onHover { inside in if let node = tile.node { onHover(node, inside) } }
                        .onTapGesture { if let node = tile.node { onOpen(node) } }
                        .contextMenu { if let node = tile.node { menu(node) } }
                        .help("\(tile.title): \(tile.size.formattedBytes)")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(tile.title), \(tile.size.formattedBytes)")
                        .accessibilityAddTraits(tile.node?.isDirectory == true ? .isButton : [])
                }
            }
            .animation(.easeOut(duration: 0.12), value: hovered.map(ObjectIdentifier.init))
        }
        // Inset by half the gap so the outer blocks line up with the edges of the frame.
        .padding(-Self.gap / 2)
    }

    private func state(of tile: TreemapTile) -> TileView.State {
        guard let hovered else { return .normal }
        // A merged child hovered in the list lights up the "smaller items" block.
        let isHovered = tile.node.map { $0 === hovered } ?? plan.isMerged(hovered)
        return isHovered ? .hovered : .dimmed
    }
}

private struct TileView: View {
    enum State { case normal, hovered, dimmed }

    var tile: TreemapTile
    var state: State
    var iconPath: String?

    var body: some View {
        let width = tile.rect.width, height = tile.rect.height
        let radius = min(10, width / 4, height / 4)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            if width >= 80, height >= 48 {
                VStack(alignment: .leading, spacing: 4) {
                    if let iconPath, height >= 96 {
                        AppIconView(path: iconPath, size: 28)
                    }
                    Text(tile.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(height >= 110 ? 2 : 1)
                        .truncationMode(.middle)
                    Text(tile.size.formattedBytes)
                        .font(Theme.display(min(26, max(14, height * 0.14))))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.ink.opacity(state == .dimmed ? 0.5 : 1))
                .padding(10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// The child's colour, softened toward the paper so dark text reads on it. Hovering lifts one block and fades the rest.
    private var fill: Color {
        let base = tile.colorIndex >= 0 ? Theme.seriesColor(tile.colorIndex) : Theme.stone
        switch state {
        case .normal: return base.mix(with: Theme.paper, by: 0.32)
        case .hovered: return base.mix(with: Theme.paper, by: 0.22)
        case .dimmed: return base.mix(with: Theme.paper, by: 0.62)
        }
    }
}
