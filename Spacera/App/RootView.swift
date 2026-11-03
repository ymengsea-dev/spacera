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
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .apps: AppsView()
            case .diskMap: DiskMapView()
            case .cleanup: CleanupView()
            }
        }
    }
}
