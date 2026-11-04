import AppKit
import SwiftUI
import Testing
@testable import Spacera

/// Renders screens to PNG for a visual check. Runs only when SPACERA_SNAPSHOT_DIR is set.
@MainActor
struct SnapshotRender {
    @Test func renderScreens() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SPACERA_SNAPSHOT_DIR"] else { return }
        let tree = try TempTree()
        for a in 0..<6 { for b in 0..<(a + 2) { for c in 0..<3 {
            try tree.file("Folder \(a)/Sub \(b)/Item \(c).bin", bytes: 300_000 * (a + 1) * (c + 1))
        } } }
        let scan = try await DiskScanner().scanTree(root: tree.root)
        let treemap = TreemapView(plan: TreemapPlan(folder: scan.root), hovered: scan.root.children.first, iconPath: { _ in nil },
                                  onHover: { _, _ in }, onOpen: { _ in }, menu: { _ in EmptyView() })
            .padding(24).frame(width: 640, height: 460).background(Theme.paper)
        try save(treemap, to: dir + "/treemap.png")
        try save(treemap.environment(\.colorScheme, .dark), to: dir + "/treemap-dark.png")

        let world = try await World()
        let env = AppEnvironment(services: world.store.services)
        env.store.startScan(); await env.store.waitForScan()
        let overview = OverviewDashboard(onNavigate: { _ in }).environment(env).padding(.horizontal, 40).padding(.vertical, 32)
            .frame(width: 980).background(Theme.paper).tint(Theme.accent)
        try save(overview, to: dir + "/overview.png")
        try save(overview.environment(\.colorScheme, .dark), to: dir + "/overview-dark.png")

        // The start screen, showing the summary saved by the scan above.
        let fresh = AppEnvironment(services: world.store.services)
        await fresh.store.loadLastSnapshot()
        let start = OverviewView().environment(fresh).frame(width: 980, height: 760).tint(Theme.accent)
        try save(start, to: dir + "/start.png")
    }

    private func save(_ view: some View, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
