import AppKit
import SwiftUI

/// Icons from the system, cached in memory. `NSWorkspace.icon(forFile:)` reads the icon from the app itself.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

struct AppIconView: View {
    var path: String?
    var symbol: String = "app.dashed"
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let path {
                Image(nsImage: IconCache.shared.icon(for: path))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
