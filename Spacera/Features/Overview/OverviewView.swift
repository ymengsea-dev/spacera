import SwiftUI

struct OverviewView: View {
    @Environment(AppEnvironment.self) private var env
    var onNavigate: (SidebarItem) -> Void = { _ in }

    var body: some View {
        let model = env.overview
        Group {
            if model.hasResult {
                ScrollView {
                    OverviewDashboard(onNavigate: onNavigate)
                        .padding(.horizontal, 40).padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                }
            } else {
                EmptyScanView(onNavigate: onNavigate)
            }
        }
        .paperBackground()
        .navigationTitle("Overview")
    }
}

/// The dashboard, without the scroll view (so it can also be rendered for previews and snapshots).
struct OverviewDashboard: View {
    @Environment(AppEnvironment.self) private var env
    var onNavigate: (SidebarItem) -> Void

    var body: some View {
        let model = env.overview
        VStack(alignment: .leading, spacing: 40) {
            if model.isLimitedScan { LimitedScanBanner() }
            CapacitySection(model: model)
            HStack(alignment: .top, spacing: 56) {
                TopAppsSection(model: model, onSeeAll: { onNavigate(.apps) })
                VStack(alignment: .leading, spacing: 36) {
                    ReclaimSection(model: model, onReview: { onNavigate(.cleanup) })
                    if model.leftoverCount > 0 {
                        LeftoversSection(model: model, onReview: { env.apps.filter = .leftovers; onNavigate(.apps) })
                    }
                    if model.hasGrowthToShow, let growth = model.growth {
                        GrowthSection(growth: growth, changes: model.topChanges)
                    }
                }
                .frame(width: 280)
            }
        }
        .frame(maxWidth: 1040, alignment: .leading)
    }
}

private struct EmptyScanView: View {
    @Environment(AppEnvironment.self) private var env
    var onNavigate: (SidebarItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(40)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 24) {
            if env.store.phase.isWorking {
                ScanProgressView()
            } else {
                Text("See what's using your Mac's storage")
                    .font(Theme.display(34)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Button {
                    env.store.startScan()
                } label: {
                    Text("Scan Disk").padding(.horizontal, 14).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                if case .failed(let message) = env.store.phase {
                    Text(message).foregroundStyle(Theme.rust.readable).font(.callout)
                }
                if !env.store.hasFullDiskAccess {
                    Button("Without Full Disk Access, only your home folder is scanned. Grant access…") {
                        env.onboarding.isPresented = true
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
                if let last = env.overview.lastSnapshot {
                    LastScanSummary(snapshot: last, apps: env.overview.lastSnapshotApps, onSeeAll: { onNavigate(.apps) })
                        .padding(.top, 12)
                }
            }
        }
    }
}

/// Shown on the start screen: the results of the last scan, saved on disk.
private struct LastScanSummary: View {
    var snapshot: ScanSnapshot
    /// Largest first.
    var apps: [SnapshotApp]
    var onSeeAll: () -> Void

    private static let shownApps = 5

    var body: some View {
        let maxSize = Double(apps.first?.summary.total ?? 1)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last scan").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(snapshot.date, format: .lastScan).foregroundStyle(Theme.ink)
                    Text(snapshot.date, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            }
            HStack(spacing: 28) {
                Metric(title: "Used", value: snapshot.volume.usedCapacity.formattedBytes)
                Metric(title: "Free", value: snapshot.volume.availableCapacity.formattedBytes)
                Metric(title: "Safe to clean", value: snapshot.safeReclaimable.formattedBytes)
            }
            if !apps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(apps.prefix(Self.shownApps)) { app in
                        Hairline()
                        SnapshotAppRow(app: app, maxSize: maxSize, iconSize: 28)
                    }
                    Hairline()
                }
                if apps.count > Self.shownApps {
                    Button("See All \(apps.count) Apps", action: onSeeAll).buttonStyle(.link)
                }
            }
        }
        .frame(width: 460)
        .card()
    }

    private struct Metric: View {
        var title: String
        var value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(Theme.display(22)).foregroundStyle(Theme.ink).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

private struct ScanProgressView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 12) {
            if case .scanning(let progress) = env.store.phase {
                Text(progress.bytes.formattedBytes)
                    .font(Theme.display(56, weight: .light)).foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(progress.files.formatted()) files so far")
                    .font(Theme.display(24)).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                Text(ScanResult.logicalPath(progress.currentPath))
                    .font(.callout).foregroundStyle(Theme.inkSecondary.opacity(0.75))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 520)
            } else {
                ProgressView().controlSize(.large)
                Text(env.store.phase.title).font(Theme.display(24)).foregroundStyle(Theme.ink)
            }
            Button("Stop Scan") { env.store.cancelScan() }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)
            .padding(.top, 14)
        }
    }
}

struct LimitedScanBanner: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(Theme.mustard)
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited scan").font(.headline).foregroundStyle(Theme.ink)
                Text("Without Full Disk Access, Spacera scanned only your home folder, and some app data is hidden.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            Button("Grant Access…") { env.onboarding.isPresented = true }
        }
        .card()
    }
}

private struct CapacitySection: View {
    var model: OverviewViewModel

    var body: some View {
        if let volume = model.volume {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(volume.name).font(.callout).foregroundStyle(Theme.inkSecondary)
                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text(volume.usedCapacity.formattedBytes)
                                .font(Theme.display(54, weight: .light)).foregroundStyle(Theme.ink)
                            Text("used of \(volume.totalCapacity.formattedBytes)")
                                .font(.title3).foregroundStyle(Theme.inkSecondary)
                        }
                        .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(volume.availableCapacity.formattedBytes)
                            .font(Theme.display(26)).foregroundStyle(Theme.ink).monospacedDigit()
                        Text("free").font(.callout).foregroundStyle(Theme.inkSecondary)
                    }
                }
                let slices = model.slices
                SegmentBar(
                    segments: slices.map { .init(id: $0.id, value: Double($0.bytes), color: $0.color) },
                    total: Double(volume.totalCapacity),
                    height: 16
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 20, alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(slices) { slice in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 10, height: 10)
                            Text(slice.title).foregroundStyle(Theme.ink)
                            SizeLabel(bytes: slice.bytes).foregroundStyle(Theme.inkSecondary)
                        }
                        .font(.callout)
                        .lineLimit(1)
                        .accessibilityElement(children: .combine)
                    }
                }
                if volume.purgeableCapacity > 0 || model.trashedSinceScan > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        if volume.purgeableCapacity > 0 {
                            Text("macOS can free another \(volume.purgeableCapacity.formattedBytes) of purgeable space on its own.")
                        }
                        if model.trashedSinceScan > 0 {
                            Text("\(model.trashedSinceScan.formattedBytes) moved to the Trash since this scan.")
                        }
                    }
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }
}

private struct TopAppsSection: View {
    var model: OverviewViewModel
    var onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Largest apps").sectionHeading()
                Spacer()
                Button("See All", action: onSeeAll).buttonStyle(.link)
            }
            .padding(.bottom, 12)
            let apps = model.topApps
            let maxSize = Double(apps.first?.totalSize ?? 1)
            ForEach(apps) { footprint in
                Hairline()
                HStack(spacing: 14) {
                    AppIconView(path: footprint.app.url.path, size: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(footprint.app.name).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            SizeLabel(bytes: footprint.totalSize).foregroundStyle(Theme.ink)
                        }
                        SegmentBar(segments: [
                            .init(id: "bundle", value: Double(footprint.bundleSize), color: Theme.slate),
                            .init(id: "data", value: Double(footprint.dataSize), color: Theme.mauve),
                        ], total: maxSize, height: 5)
                    }
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
            Hairline()
            AppDataLegend().padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Explains the two colours in app bars.
struct AppDataLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            Label { Text("App") } icon: { RoundedRectangle(cornerRadius: 2).fill(Theme.slate).frame(width: 8, height: 8) }
            Label { Text("Its data") } icon: { RoundedRectangle(cornerRadius: 2).fill(Theme.mauve).frame(width: 8, height: 8) }
        }
        .font(.caption).foregroundStyle(Theme.inkSecondary)
    }
}

private struct ReclaimSection: View {
    var model: OverviewViewModel
    var onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Safe to clean").sectionHeading()
            Text(model.safeReclaimable.formattedBytes)
                .font(Theme.display(40, weight: .light)).foregroundStyle(Theme.sage.readable).monospacedDigit()
            VStack(spacing: 0) {
                ForEach(model.topFindings) { finding in
                    Hairline()
                    HStack {
                        Text(finding.rule.title).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer()
                        SizeLabel(bytes: finding.totalSize, font: .callout).foregroundStyle(Theme.inkSecondary)
                    }
                    .font(.callout)
                    .padding(.vertical, 8)
                }
                Hairline()
            }
            Button("Review Cleanup", action: onReview)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
    }
}

/// What grew or shrank since the previous scan.
private struct GrowthSection: View {
    var growth: GrowthReport
    var changes: [(change: GrowthReport.Change, isApp: Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Since last scan").sectionHeading()
            HStack(alignment: .firstTextBaseline) {
                Text(growth.previousDate, format: .relative(presentation: .named)).foregroundStyle(Theme.inkSecondary)
                Spacer()
                DeltaLabel(delta: growth.usedDelta, suffix: " used")
            }
            .font(.callout)
            if growth.comparesDifferentScopes {
                Text("The previous scan covered a different area (Full Disk Access changed), so app sizes may not be comparable.")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            VStack(spacing: 0) {
                ForEach(changes, id: \.change.id) { item in
                    Hairline()
                    HStack(spacing: 8) {
                        // Apps from this scan are installed; an app that's gone has no icon path.
                        AppIconView(path: item.change.iconPath, symbol: item.isApp ? "app.dashed" : "folder", size: 20)
                        Text(item.change.title).foregroundStyle(Theme.ink).lineLimit(1)
                        if item.change.isNew {
                            Text("new").font(.caption2).foregroundStyle(Theme.inkSecondary)
                                .padding(.horizontal, 5).background(Theme.rule, in: Capsule())
                        }
                        Spacer()
                        DeltaLabel(delta: item.change.delta)
                    }
                    .font(.callout)
                    .padding(.vertical, 7)
                }
                if !changes.isEmpty { Hairline() }
            }
        }
    }
}

private struct DeltaLabel: View {
    var delta: Int64
    var suffix: String = ""

    var body: some View {
        let grew = delta > 0
        Text((grew ? "+" : "−") + abs(delta).formattedBytes + suffix)
            .font(.callout.weight(.medium)).monospacedDigit()
            .foregroundStyle(grew ? Theme.rust.readable : Theme.sage.readable)
            .accessibilityLabel((grew ? "Grew by " : "Shrank by ") + abs(delta).formattedBytes)
    }
}

private struct LeftoversSection: View {
    var model: OverviewViewModel
    var onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Left behind").sectionHeading()
            Text("^[\(model.leftoverCount) deleted app](inflect: true) left \(model.leftoverSize.formattedBytes) behind.")
                .foregroundStyle(Theme.inkSecondary)
            if model.orphanedBackgroundItems > 0 {
                Label("^[\(model.orphanedBackgroundItems) background item](inflect: true) still installed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.mustard.readable).font(.callout)
            }
            Button("Show Leftovers", action: onReview).padding(.top, 4)
        }
    }
}
