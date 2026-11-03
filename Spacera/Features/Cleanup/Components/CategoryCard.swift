import SwiftUI

struct CategoryCard: View {
    var finding: RuleFinding
    var model: CleanupViewModel

    private var isExpanded: Bool { model.expanded.contains(finding.id) }
    private var isInfoOnly: Bool { finding.rule.safety == .infoOnly }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if !isInfoOnly {
                    Toggle("", isOn: Binding(get: { model.selectionState(of: finding) == .all },
                                             set: { _ in model.toggleAll(in: finding) }))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel("Select all \(finding.rule.title)")
                }
                Image(systemName: finding.rule.symbol)
                    .font(.title2)
                    .foregroundStyle(finding.rule.safety.color)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(finding.rule.title).font(.headline)
                        SafetyBadge(level: finding.rule.safety)
                    }
                    Text(finding.rule.explanation).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    SizeLabel(bytes: finding.totalSize, font: .title3.weight(.semibold))
                    Text(isInfoOnly ? "\(finding.items.count) items" : "\(model.selectedSize(in: finding).formattedBytes) selected")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Button { model.toggleExpanded(finding) } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide items" : "Show items")
            }
            .contentShape(Rectangle())
            .onTapGesture { model.toggleExpanded(finding) }

            if isExpanded {
                Divider().padding(.vertical, 10)
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(finding.items.prefix(500)) { item in
                        ItemRow(item: item, selectable: !isInfoOnly, isOn: model.selected.contains(item.path)) {
                            model.toggle(item)
                        }
                    }
                    if finding.items.count > 500 {
                        Text("and \(finding.items.count - 500) more…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
    }
}

private struct ItemRow: View {
    var item: CleanupItem
    var selectable: Bool
    var isOn: Bool
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if selectable {
                Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                    .toggleStyle(.checkbox).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.note.map { "\(item.name) · \($0)" } ?? item.name).lineLimit(1).truncationMode(.middle)
                Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            SizeLabel(bytes: item.size, font: .callout)
            if !item.path.hasPrefix("snapshot:") {
                Button { Finder.reveal(item.path) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
            }
        }
        .padding(.leading, 42)
        .contextMenu {
            if !item.path.hasPrefix("snapshot:") {
                Button("Reveal in Finder") { Finder.reveal(item.path) }
                Button("Copy Path") { Finder.copyPath(item.path) }
            }
        }
    }
}
