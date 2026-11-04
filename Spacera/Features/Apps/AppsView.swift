import SwiftUI

struct AppsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var model = env.apps
        NavigationStack(path: $model.path) {
            Group {
                if !model.hasResult, let snapshot = model.lastSnapshot {
                    SnapshotAppList(model: model, snapshot: snapshot)
                } else if !model.hasResult {
                    NoScanView(message: "Scan your disk to see how much space each app uses.")
                } else if model.filter == .leftovers {
                    LeftoverList(model: model)
                } else {
                    AppList(model: model)
                }
            }
            .paperBackground()
            .navigationTitle("Apps")
            .toolbar {
                if model.hasResult {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("Show", selection: $model.filter) {
                            ForEach(AppsViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
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
        .scrollContentBackground(.hidden)
        .overlay {
            if list.isEmpty {
                ContentUnavailableView("No Apps", systemImage: "square.grid.2x2",
                                       description: Text(model.filter == .background ? "No apps have background items." : "No apps were found."))
            }
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
                    Text(footprint.app.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                    if footprint.app.isSystemApp {
                        Text("macOS").font(.caption2).foregroundStyle(Theme.inkSecondary)
                            .padding(.horizontal, 5).background(Theme.rule, in: Capsule())
                    }
                    if !footprint.backgroundItems.isEmpty {
                        Image(systemName: "gearshape.2").font(.caption).foregroundStyle(Theme.inkSecondary)
                            .help("\(footprint.backgroundItems.count) background items")
                    }
                    Spacer()
                    SizeLabel(bytes: footprint.totalSize, font: Theme.display(17)).foregroundStyle(Theme.ink)
                }
                SegmentBar(segments: [
                    .init(id: "bundle", value: Double(footprint.bundleSize), color: Theme.slate),
                    .init(id: "data", value: Double(footprint.dataSize), color: Theme.mauve),
                ], total: maxSize, height: 5)
                HStack(spacing: 12) {
                    Text("App \(footprint.bundleSize.formattedBytes)")
                    Text("Data \(footprint.dataSize.formattedBytes)")
                }
                .font(.caption).foregroundStyle(Theme.inkSecondary).monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// The apps from the last saved scan. Sizes only: opening an app's files needs a new scan.
private struct SnapshotAppList: View {
    var model: AppsViewModel
    var snapshot: ScanSnapshot

    var body: some View {
        let list = model.snapshotApps
        let maxSize = Double(list.first?.summary.total ?? 1)
        List {
            Section {
                ForEach(list) { app in
                    SnapshotAppRow(app: app, maxSize: maxSize)
                }
            } header: {
                HStack(spacing: 12) {
                    Text("Sizes from your last scan, \(snapshot.date.formatted(.lastScan)). Scan again to see each app's files.")
                        .font(.callout).foregroundStyle(Theme.inkSecondary).textCase(nil)
                    Spacer()
                    if model.isScanning {
                        // A second Scan Disk here would restart the running scan from zero.
                        ProgressView().controlSize(.small)
                        Text(model.scanTitle).font(.callout).foregroundStyle(Theme.inkSecondary).textCase(nil)
                        Button("Stop") { model.cancelScan() }
                    } else {
                        Button("Scan Disk") { model.startScan() }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// One app from a saved scan summary: icon, name, size, and the app/data bar.
struct SnapshotAppRow: View {
    var app: SnapshotApp
    var maxSize: Double
    var iconSize: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(path: app.iconPath, size: iconSize)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.summary.name).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    SizeLabel(bytes: app.summary.total).foregroundStyle(Theme.ink)
                }
                SegmentBar(segments: [
                    .init(id: "bundle", value: Double(app.summary.bundleSize), color: Theme.slate),
                    .init(id: "data", value: Double(app.summary.dataSize), color: Theme.mauve),
                ], total: maxSize, height: 5)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// "Wed, Nov 4, 9:12 PM": the weekday, date, and time of a scan.
    static var lastScan: Date.FormatStyle { .dateTime.weekday(.abbreviated).month().day().hour().minute() }
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
                                Text(group.displayName).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                                Text(group.identifier).font(.caption).foregroundStyle(Theme.inkSecondary)
                                if let note = group.entries.compactMap(\.note).first {
                                    Label(note, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(Theme.mustard.readable).lineLimit(2)
                                }
                            }
                            Spacer()
                            SizeLabel(bytes: group.totalSize, font: Theme.display(17)).foregroundStyle(Theme.ink)
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                Text("Data left behind by apps that are no longer installed. Check each one: some belong to apps you installed elsewhere, or to command-line tools.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary).textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if list.isEmpty {
                ContentUnavailableView("No Leftovers", systemImage: "checkmark.seal", description: Text("No data from deleted apps was found."))
            }
        }
    }
}
