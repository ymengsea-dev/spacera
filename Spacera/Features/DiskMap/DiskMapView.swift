import SwiftUI

struct DiskMapView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var model = env.diskMap
        Group {
            if let plan = model.plan {
                VStack(spacing: 0) {
                    Hairline()
                    HStack(spacing: 0) {
                        TreemapView(
                            plan: plan,
                            hovered: model.hovered,
                            iconPath: { model.iconPath(for: $0) },
                            onHover: { model.setHover($0, $1) },
                            onOpen: { model.drill(into: $0) },
                            menu: { NodeMenu(node: $0, model: model) }
                        )
                        .padding(24)
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)

                        Rectangle().fill(Theme.rule).frame(width: 1)
                        ChildList(model: model, plan: plan)
                            .frame(width: 300)
                    }
                }
                .sheet(item: $model.review) { ReviewSheet(model: $0) }
            } else {
                NoScanView(message: "Scan your disk to see what fills it, folder by folder.")
            }
        }
        .paperBackground()
        .navigationTitle("Disk Map")
        .toolbar {
            if model.plan != nil {
                ToolbarItem(placement: .navigation) {
                    Breadcrumbs(model: model)
                }
                if let current = model.current {
                    ToolbarItem(placement: .primaryAction) {
                        SizeLabel(bytes: current.size, font: Theme.display(17)).foregroundStyle(Theme.ink)
                            .fixedSize()
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }
}

private struct Breadcrumbs: View {
    var model: DiskMapViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button { model.goUp() } label: { Image(systemName: "chevron.backward") }
                .disabled(model.breadcrumbs.count <= 1)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Up one level (⌘↑)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { index, node in
                        if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        let isLast = index == model.breadcrumbs.count - 1
                        Button(model.displayName(node)) { model.jump(to: node) }
                            .buttonStyle(.plain)
                            .foregroundStyle(isLast ? Theme.ink : Theme.inkSecondary)
                            .fontWeight(isLast ? .medium : .regular)
                    }
                }
            }
            // Deep trails start scrolled to the end, so the current folder is the crumb in view.
            // Short trails stay on the left, next to the back button.
            .defaultScrollAnchor(.trailing)
            .defaultScrollAnchor(.leading, for: .alignment)
            .frame(maxWidth: 460)
        }
        .padding(.horizontal, 8)
    }
}

private struct ChildList: View {
    var model: DiskMapViewModel
    var plan: TreemapPlan

    var body: some View {
        List(Array(model.children.enumerated()), id: \.element.id) { index, node in
            // Same colour as the node's block in the chart. Merged children share the "smaller items" block's stone.
            let color = index < plan.shownCount ? Theme.seriesColor(index) : Theme.stone
            let highlighted = model.hovered === node
            HStack(spacing: 10) {
                if model.iconPath(for: node) != nil {
                    AppIconView(path: model.iconPath(for: node), size: 22)
                } else {
                    Image(systemName: symbol(for: node)).frame(width: 22).foregroundStyle(Theme.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                    SegmentBar(segments: [.init(id: "v", value: model.fraction(of: node), color: color)], total: 1, height: 4)
                }
                SizeLabel(bytes: node.size, font: .callout).foregroundStyle(Theme.inkSecondary)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            .padding(.vertical, 3)
            .listRowBackground(highlighted ? color.opacity(0.16) : Color.clear)
            .contentShape(Rectangle())
            .onHover { model.setHover(node, $0) }
            .onTapGesture(count: 2) { model.drill(into: node) }
            .contextMenu { NodeMenu(node: node, model: model) }
            .accessibilityElement(children: .combine)
            .accessibilityHint(node.isDirectory ? "Double-click to open" : "")
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
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
