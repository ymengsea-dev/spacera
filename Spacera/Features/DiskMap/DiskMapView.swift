import SwiftUI

struct DiskMapView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var model = env.diskMap
        Group {
            if let current = model.current {
                VStack(spacing: 0) {
                    Breadcrumbs(model: model)
                    Divider()
                    HSplitView {
                        SunburstView(
                            arcs: model.arcs,
                            maxDepth: model.maxDepth,
                            centerTitle: model.displayName(current),
                            centerSize: current.size,
                            hovered: model.hovered,
                            iconPath: { model.iconPath(for: $0) },
                            onHover: { model.hovered = $0 },
                            onSelect: { model.select($0) },
                            onCenter: { model.goUp() }
                        )
                        .padding(20)
                        .frame(minWidth: 380, minHeight: 380)
                        .contextMenu {
                            if let node = model.hovered?.node { NodeMenu(node: node, model: model) }
                        }

                        ChildList(model: model)
                            .frame(minWidth: 280, idealWidth: 340, maxWidth: 480)
                    }
                }
                .sheet(item: $model.review) { ReviewSheet(model: $0) }
            } else {
                ContentUnavailableView("No Scan Yet", systemImage: "chart.pie",
                                       description: Text("Scan your disk to explore it as an interactive map."))
            }
        }
        .navigationTitle("Disk Map")
    }
}

private struct Breadcrumbs: View {
    var model: DiskMapViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button { model.goUp() } label: { Image(systemName: "chevron.backward") }
                    .disabled(model.breadcrumbs.count <= 1)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("Up one level (⌘↑)")
                ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { index, node in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button(model.displayName(node)) { model.jump(to: node) }
                        .buttonStyle(.plain)
                        .fontWeight(index == model.breadcrumbs.count - 1 ? .semibold : .regular)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

private struct ChildList: View {
    var model: DiskMapViewModel

    var body: some View {
        List(model.children) { node in
            let highlighted = model.hovered?.node === node
            HStack(spacing: 10) {
                if model.iconPath(for: node) != nil {
                    AppIconView(path: model.iconPath(for: node), size: 22)
                } else {
                    Image(systemName: symbol(for: node)).frame(width: 22).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    SegmentBar(segments: [.init(id: "v", value: model.fraction(of: node), color: .accentColor)], total: 1, height: 4)
                }
                SizeLabel(bytes: node.size, font: .callout).frame(minWidth: 64, alignment: .trailing)
            }
            .padding(.vertical, 2)
            .listRowBackground(highlighted ? Color.accentColor.opacity(0.15) : nil)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.drill(into: node) }
            .contextMenu { NodeMenu(node: node, model: model) }
            .accessibilityElement(children: .combine)
            .accessibilityHint(node.isDirectory ? "Double-click to open" : "")
        }
        .listStyle(.inset)
    }

    private func symbol(for node: FileNode) -> String {
        switch node.kind {
        case .directory: "folder"
        case .file: "doc"
        case .symlink: "arrow.turn.up.right"
        case .smallFiles: "square.stack"
        }
    }
}

private struct NodeMenu: View {
    var node: FileNode
    var model: DiskMapViewModel

    var body: some View {
        if node.isDirectory, !node.children.isEmpty {
            Button("Open") { model.drill(into: node) }
        }
        if case .smallFiles = node.kind {} else {
            Button("Reveal in Finder") { Finder.reveal(model.path(of: node)) }
            Button("Copy Path") { Finder.copyPath(model.path(of: node)) }
            Divider()
            Button("Move to Trash…") { model.startReview(for: node) }
        }
    }
}
