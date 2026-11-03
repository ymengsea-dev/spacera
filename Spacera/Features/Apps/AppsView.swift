import SwiftUI

struct AppsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var model = env.apps
        NavigationStack(path: $model.path) {
            Group {
                if !model.hasResult {
                    ContentUnavailableView("No Scan Yet", systemImage: "square.grid.2x2",
                                           description: Text("Scan your disk to see how much space each app uses."))
                } else if model.filter == .leftovers {
                    LeftoverList(model: model)
                } else {
                    AppList(model: model)
                }
            }
            .navigationTitle("Apps")
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search apps")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Picker("Show", selection: $model.filter) {
                        ForEach(AppsViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem {
                    Menu {
                        Picker("Sort By", selection: $model.sort) {
                            ForEach(AppsViewModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("Show Apple Apps Without Data", isOn: $model.showSystemApps)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .navigationDestination(for: AppsViewModel.Route.self) { route in
                AppDetailView(model: model.detailModel(for: route))
            }
        }
    }
}

private struct AppList: View {
    var model: AppsViewModel

    var body: some View {
        let list = model.footprints
        let maxSize = Double(model.largestTotal)
        List(list) { footprint in
            NavigationLink(value: AppsViewModel.Route.app(id: footprint.id)) {
                AppRow(footprint: footprint, maxSize: maxSize)
            }
            .contextMenu {
                Button("Reveal App in Finder") { Finder.reveal(footprint.app.url.path) }
                if let id = footprint.app.bundleID { Button("Copy Bundle ID") { Finder.copyPath(id) } }
            }
        }
        .overlay {
            if list.isEmpty { ContentUnavailableView.search(text: model.search) }
        }
    }
}

struct AppRow: View {
    var footprint: AppFootprint
    var maxSize: Double

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(path: footprint.app.url.path, size: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(footprint.app.name).font(.headline).lineLimit(1)
                    if footprint.app.isSystemApp {
                        Text("macOS").font(.caption2).padding(.horizontal, 4).background(.quaternary, in: Capsule())
                    }
                    if !footprint.backgroundItems.isEmpty {
                        Image(systemName: "gearshape.2").font(.caption).foregroundStyle(.secondary)
                            .help("\(footprint.backgroundItems.count) background items")
                    }
                    Spacer()
                    SizeLabel(bytes: footprint.totalSize, font: .headline)
                }
                SegmentBar(segments: [
                    .init(id: "bundle", value: Double(footprint.bundleSize), color: .blue),
                    .init(id: "data", value: Double(footprint.dataSize), color: .purple),
                ], total: maxSize)
                HStack(spacing: 12) {
                    Text("App \(footprint.bundleSize.formattedBytes)")
                    Text("Data \(footprint.dataSize.formattedBytes)")
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct LeftoverList: View {
    var model: AppsViewModel

    var body: some View {
        let list = model.leftovers
        List {
            Section {
                ForEach(list) { group in
                    NavigationLink(value: AppsViewModel.Route.leftover(id: group.id)) {
                        HStack(spacing: 12) {
                            AppIconView(path: nil, symbol: group.entries.contains { $0.kind == .backgroundItem } ? "gearshape.2" : "trash.slash", size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.displayName).font(.headline)
                                Text(group.identifier).font(.caption).foregroundStyle(.secondary)
                                if let note = group.entries.compactMap(\.note).first {
                                    Label(note, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                                }
                            }
                            Spacer()
                            SizeLabel(bytes: group.totalSize, font: .headline)
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                Text("Data left behind by apps that are no longer installed. Check each one: some belong to apps you installed elsewhere, or to command-line tools.")
                    .font(.callout).foregroundStyle(.secondary).textCase(nil)
            }
        }
        .overlay {
            if list.isEmpty {
                ContentUnavailableView("No Leftovers", systemImage: "checkmark.seal", description: Text("No data from deleted apps was found."))
            }
        }
    }
}
