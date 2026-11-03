import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, apps, diskMap, cleanup

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .apps: "Apps"
        case .diskMap: "Disk Map"
        case .cleanup: "Cleanup"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "internaldrive"
        case .apps: "square.grid.2x2"
        case .diskMap: "chart.pie"
        case .cleanup: "sparkles"
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        @Bindable var onboarding = env.onboarding
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .badge(badge(for: item))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) { SidebarDiskSummary() }
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView(onNavigate: { selection = $0 })
                case .apps: AppsView()
                case .diskMap: DiskMapView()
                case .cleanup: CleanupView()
                }
            }
            .toolbar { ScanToolbar() }
        }
        .sheet(isPresented: $onboarding.isPresented) {
            OnboardingView()
        }
        .onAppear { env.onboarding.presentIfNeeded() }
        .task { await env.store.loadLastSnapshot() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            env.onboarding.appDidBecomeActive()
        }
    }

    private func badge(for item: SidebarItem) -> Text? {
        guard item == .cleanup, env.store.phase == .done else { return nil }
        let safe = env.store.findings.filter { $0.rule.safety == .safe }.reduce(Int64(0)) { $0 + $1.totalSize }
        return safe > 0 ? Text(safe.formattedBytes) : nil
    }
}

/// Scan, Stop, and live progress in the toolbar.
struct ScanToolbar: ToolbarContent {
    @Environment(AppEnvironment.self) private var env

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            let phase = env.store.phase
            if phase.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(phase.title).font(.caption.weight(.medium))
                        if case .scanning(let progress) = phase {
                            Text("\(progress.bytes.formattedBytes) · \(progress.files.formatted()) files")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .frame(minWidth: 170, alignment: .leading)
                }
                Button("Stop", systemImage: "stop.fill") { env.store.cancelScan() }
                    .help("Stop scanning (⌘.)")
            } else {
                Button(env.store.result == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise") {
                    env.store.startScan()
                }
                .help("Scan the disk (⌘R)")
            }
        }
    }
}

/// A small capacity summary at the bottom of the sidebar.
private struct SidebarDiskSummary: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let volume = env.store.result?.volume, volume.totalCapacity > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text(volume.name).font(.caption.weight(.semibold))
                ProgressView(value: Double(volume.usedCapacity), total: Double(volume.totalCapacity))
                    .tint(Double(volume.availableCapacity) / Double(volume.totalCapacity) < 0.1 ? .red : .accentColor)
                Text("\(volume.availableCapacity.formattedBytes) free of \(volume.totalCapacity.formattedBytes)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }
}
