import SwiftUI

struct AppDetailView: View {
    @State var model: AppDetailViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.entries.isEmpty {
                ContentUnavailableView("Nothing Left", systemImage: "checkmark.circle", description: Text("Everything here has been moved to the Trash."))
            } else {
                List {
                    ForEach(model.groups, id: \.kind) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                EntryRow(entry: entry, isOn: model.selected.contains(entry.path),
                                         selectable: model.isSelectable(entry), toggle: { model.toggle(entry) })
                            }
                        } header: {
                            HStack {
                                Label(group.kind.title, systemImage: group.kind.symbol)
                                Spacer()
                                SizeLabel(bytes: group.entries.reduce(0) { $0 + $1.size }, font: .caption)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .navigationTitle(model.title)
        .sheet(item: $model.review) { review in ReviewSheet(model: review) }
    }

    private var header: some View {
        HStack(spacing: 16) {
            AppIconView(path: model.iconPath, symbol: "trash.slash", size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title).font(.title.weight(.semibold))
                Text(model.subtitle).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing) {
                SizeLabel(bytes: model.total, font: .system(size: 28, weight: .semibold, design: .rounded))
                Text("in \(model.entries.count) places").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if model.app?.isSystemApp == false {
                Button("Select Everything (Uninstall)") { model.selectEverything() }
                    .help("Select the app and all of its data")
            }
            Spacer()
            Text("Selected: \(model.selectedSize.formattedBytes)").monospacedDigit().foregroundStyle(.secondary)
            Button("Move to Trash…") { model.startReview() }
                .buttonStyle(.borderedProminent)
                .disabled(model.selected.isEmpty)
        }
        .padding(14)
    }
}

private struct EntryRow: View {
    var entry: FootprintEntry
    var isOn: Bool
    var selectable: Bool
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!selectable)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: entry.path).lastPathComponent).lineLimit(1)
                Text(entry.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let note = entry.note {
                    Text(note).font(.caption).foregroundStyle(entry.kind == .backgroundItem ? .orange : .secondary).lineLimit(2)
                }
            }
            Spacer()
            if entry.confidence == .likely {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help(entry.confidence.title)
            }
            SafetyBadge(level: entry.safety)
            SizeLabel(bytes: entry.size, font: .callout).frame(minWidth: 70, alignment: .trailing)
            Button { Finder.reveal(entry.path) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
        }
        .contextMenu {
            Button("Reveal in Finder") { Finder.reveal(entry.path) }
            Button("Copy Path") { Finder.copyPath(entry.path) }
        }
    }
}
