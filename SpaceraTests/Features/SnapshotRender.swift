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
        let arcs = SunburstLayout.make(root: scan.root)
        let sunburst = SunburstView(arcs: arcs, maxDepth: 5, centerTitle: "Example", centerSize: scan.root.size, hovered: arcs.first { $0.depth == 2 },
                                    iconPath: { _ in nil }, onHover: { _ in }, onSelect: { _ in }, onCenter: {})
            .frame(width: 520, height: 520).background(Color.white)
        try save(sunburst, to: dir + "/sunburst.png")

        let world = try await World()
        let env = AppEnvironment(services: world.store.services)
        env.store.startScan(); await env.store.waitForScan()
        let overview = OverviewDashboard(onNavigate: { _ in }).environment(env).padding(24).frame(width: 980).background(Color(nsColor: .windowBackgroundColor))
        try save(overview, to: dir + "/overview.png")
    }

    private func save(_ view: some View, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
