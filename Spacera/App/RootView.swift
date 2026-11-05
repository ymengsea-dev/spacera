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
        case .cleanup: "trash"
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
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarScanStatus()
                    SidebarDiskSummary()
                }
            }
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView(onNavigate: { selection = $0 })
                case .apps: AppsView()
                case .diskMap: DiskMapView()
                case .cleanup: CleanupView()
                }
            }
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .sheet(isPresented: $onboarding.isPresented) {
            OnboardingView()
        }
        .task {
            await env.store.loadLastSnapshot()
            env.onboarding.presentIfNeeded()
        }
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

/// The scan's state at the bottom of the sidebar, so Rescan and Stop are reachable from every screen.
private struct SidebarScanStatus: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let store = env.store
        VStack(alignment: .leading, spacing: 8) {
            if store.phase.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.phase.title).font(.caption.weight(.semibold)).lineLimit(1)
                }
                if case .scanning(let progress) = store.phase {
                    Text("\(progress.bytes.formattedBytes) · \(progress.files.formatted()) files")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Button("Stop Scan") { store.cancelScan() }
                    .controlSize(.small)
            } else {
                if case .failed(let message) = store.phase {
                    Text(message).font(.caption2).foregroundStyle(Theme.rust.readable).lineLimit(3)
                } else if let date = store.lastSnapshot?.date {
                    Text("Scanned \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button(store.result == nil ? "Scan Disk" : "Rescan") { store.startScan() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

/// A small capacity summary at the bottom of the sidebar.
private struct SidebarDiskSummary: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let volume = env.store.result?.volume, volume.totalCapacity > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text(volume.name).font(.caption.weight(.semibold))
                let isLow = Double(volume.availableCapacity) / Double(volume.totalCapacity) < 0.1
                SegmentBar(segments: [.init(id: "used", value: Double(volume.usedCapacity), color: isLow ? Theme.rust : Theme.accent)],
                           total: Double(volume.totalCapacity), height: 5)
                Text("\(volume.availableCapacity.formattedBytes) free of \(volume.totalCapacity.formattedBytes)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding([.horizontal, .bottom], 12)
        }
    }
}
