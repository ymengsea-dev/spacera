import SwiftUI

struct OverviewView: View {
    @Environment(AppEnvironment.self) private var env
    var onNavigate: (SidebarItem) -> Void = { _ in }

    var body: some View {
        let model = env.overview
        Group {
            if model.hasResult {
                ScrollView {
                    OverviewDashboard(onNavigate: onNavigate).padding(24)
                }
            } else {
                EmptyScanView()
            }
        }
        .navigationTitle("Overview")
    }
}

/// The dashboard cards, without the scroll view (so it can also be rendered for previews and snapshots).
struct OverviewDashboard: View {
    @Environment(AppEnvironment.self) private var env
    var onNavigate: (SidebarItem) -> Void

    var body: some View {
        let model = env.overview
        VStack(alignment: .leading, spacing: 20) {
            if model.isLimitedScan { LimitedScanBanner() }
            CapacityCard(model: model)
            if model.hasGrowthToShow, let growth = model.growth { GrowthCard(growth: growth) }
            HStack(alignment: .top, spacing: 20) {
                TopAppsCard(model: model, onSeeAll: { onNavigate(.apps) })
                VStack(spacing: 20) {
                    ReclaimCard(model: model, onReview: { onNavigate(.cleanup) })
                    if model.leftoverCount > 0 {
                        LeftoversCard(model: model, onReview: { env.apps.filter = .leftovers; onNavigate(.apps) })
                    }
                }
                .frame(width: 300)
            }
        }
    }
}

private struct EmptyScanView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "internaldrive")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.tint)
            Text("See what's using your Mac's storage").font(.title.weight(.semibold))
            Text("Spacera scans your disk, matches everything to the app it belongs to, and finds what's safe to clean up. Nothing leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            if env.store.phase.isWorking {
                ScanProgressView()
            } else {
                if let last = env.overview.lastSnapshot { LastScanSummary(snapshot: last) }
                Button {
                    env.store.startScan()
                } label: {
                    Label("Scan Disk", systemImage: "magnifyingglass").padding(.horizontal, 12).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if case .failed(let message) = env.store.phase {
                    Text(message).foregroundStyle(.red).font(.callout)
                }
                if !env.store.hasFullDiskAccess {
                    Button("Without Full Disk Access, only your home folder is scanned. Grant access…") {
                        env.onboarding.isPresented = true
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown on the start screen: the results of the last scan, saved on disk.
private struct LastScanSummary: View {
    var snapshot: ScanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last scan").font(.headline)
                Spacer()
                Text(snapshot.date, format: .relative(presentation: .named)).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                Metric(title: "Used", value: snapshot.volume.usedCapacity.formattedBytes)
                Metric(title: "Free", value: snapshot.volume.availableCapacity.formattedBytes)
                Metric(title: "Safe to clean", value: snapshot.safeReclaimable.formattedBytes)
            }
            HStack(spacing: 8) {
                ForEach(snapshot.apps.sorted { $0.total > $1.total }.prefix(6), id: \.key) { app in
                    AppIconView(path: FileManager.default.fileExists(atPath: app.path) ? app.path : nil, size: 30)
                        .help("\(app.name): \(app.total.formattedBytes)")
                }
            }
        }
        .frame(width: 420)
        .card()
    }

    private struct Metric: View {
        var title: String
        var value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            }
        }
    }
}

private struct GrowthCard: View {
    var growth: GrowthReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Changes Since Last Scan", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
                Text(growth.previousDate, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                Spacer()
                DeltaLabel(delta: growth.usedDelta, suffix: " used")
            }
            if growth.comparesDifferentScopes {
                Text("The previous scan covered a different area (Full Disk Access changed), so app sizes may not be comparable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            let changes = Array((growth.apps + growth.categories).sorted { abs($0.delta) > abs($1.delta) }.prefix(6))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(changes) { change in
                    HStack(spacing: 8) {
                        if let path = change.iconPath, FileManager.default.fileExists(atPath: path) {
                            AppIconView(path: path, size: 22)
                        } else {
                            Image(systemName: change.iconPath == nil ? "folder" : "app.dashed")
                                .frame(width: 22).foregroundStyle(.secondary)
                        }
                        Text(change.title).lineLimit(1)
                        if change.isNew { Text("new").font(.caption2).padding(.horizontal, 4).background(.quaternary, in: Capsule()) }
                        Spacer()
                        DeltaLabel(delta: change.delta)
                    }
                    .font(.callout)
                }
            }
        }
        .card()
    }
}

private struct DeltaLabel: View {
    var delta: Int64
    var suffix: String = ""

    var body: some View {
        let grew = delta > 0
        Label((grew ? "+" : "−") + abs(delta).formattedBytes + suffix, systemImage: grew ? "arrow.up" : "arrow.down")
            .font(.callout.weight(.medium)).monospacedDigit()
            .foregroundStyle(grew ? .orange : .green)
            .accessibilityLabel((grew ? "Grew by " : "Shrank by ") + abs(delta).formattedBytes)
    }
}

private struct ScanProgressView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.large)
            Text(env.store.phase.title).font(.headline)
            if case .scanning(let progress) = env.store.phase {
                Text("\(progress.bytes.formattedBytes) in \(progress.files.formatted()) files")
                    .monospacedDigit().foregroundStyle(.secondary)
                Text(ScanResult.logicalPath(progress.currentPath))
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 420)
            }
            Button("Stop") { env.store.cancelScan() }.padding(.top, 6)
        }
    }
}

struct LimitedScanBanner: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited scan").font(.headline)
                Text("Without Full Disk Access, Spacera scanned only your home folder, and some app data is hidden.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant Access…") { env.onboarding.isPresented = true }
        }
        .card()
    }
}

private struct CapacityCard: View {
    var model: OverviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let volume = model.volume {
                HStack(alignment: .firstTextBaseline) {
                    Text(volume.name).font(.title2.weight(.semibold))
                    Spacer()
                    Text("\(volume.usedCapacity.formattedBytes) used of \(volume.totalCapacity.formattedBytes)")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                let slices = model.slices
                SegmentBar(
                    segments: slices.map { .init(id: $0.id, value: Double($0.bytes), color: $0.color) },
                    total: Double(volume.totalCapacity),
                    height: 18
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(slices) { slice in
                        HStack(spacing: 6) {
                            Circle().fill(slice.color).frame(width: 9, height: 9)
                            Text(slice.title)
                            SizeLabel(bytes: slice.bytes).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .accessibilityElement(children: .combine)
                    }
                }
                if volume.purgeableCapacity > 0 || model.trashedSinceScan > 0 {
                    HStack(spacing: 16) {
                        if volume.purgeableCapacity > 0 {
                            Label("macOS can free another \(volume.purgeableCapacity.formattedBytes) of purgeable space on its own", systemImage: "info.circle")
                        }
                        if model.trashedSinceScan > 0 {
                            Label("\(model.trashedSinceScan.formattedBytes) moved to the Trash since this scan", systemImage: "trash")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }
}

private struct TopAppsCard: View {
    var model: OverviewViewModel
    var onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps Using the Most Space").font(.headline)
                Spacer()
                Button("See All", action: onSeeAll).buttonStyle(.link)
            }
            let apps = model.topApps
            let maxSize = Double(apps.first?.totalSize ?? 1)
            ForEach(apps) { footprint in
                HStack(spacing: 12) {
                    AppIconView(path: footprint.app.url.path, size: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(footprint.app.name).lineLimit(1)
                            Spacer()
                            SizeLabel(bytes: footprint.totalSize).foregroundStyle(.secondary)
                        }
                        SegmentBar(segments: [
                            .init(id: "bundle", value: Double(footprint.bundleSize), color: .blue),
                            .init(id: "data", value: Double(footprint.dataSize), color: .purple),
                        ], total: maxSize)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 14) {
                Label { Text("App") } icon: { Circle().fill(.blue).frame(width: 7, height: 7) }
                Label { Text("Its data") } icon: { Circle().fill(.purple).frame(width: 7, height: 7) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct ReclaimCard: View {
    var model: OverviewViewModel
    var onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Safe to Clean", systemImage: "sparkles").font(.headline)
            SizeLabel(bytes: model.safeReclaimable, font: .system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
            ForEach(model.topFindings) { finding in
                HStack {
                    Image(systemName: finding.rule.symbol).frame(width: 18).foregroundStyle(.secondary)
                    Text(finding.rule.title).lineLimit(1)
                    Spacer()
                    SizeLabel(bytes: finding.totalSize, font: .callout).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Button("Review Cleanup", action: onReview)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .card()
    }
}

private struct LeftoversCard: View {
    var model: OverviewViewModel
    var onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Leftovers from Deleted Apps", systemImage: "trash.slash").font(.headline)
            Text("^[\(model.leftoverCount) deleted app](inflect: true) left \(model.leftoverSize.formattedBytes) behind.")
                .foregroundStyle(.secondary)
            if model.orphanedBackgroundItems > 0 {
                Label("^[\(model.orphanedBackgroundItems) background item](inflect: true) still installed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            Button("Show Leftovers", action: onReview).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .card()
    }
}
