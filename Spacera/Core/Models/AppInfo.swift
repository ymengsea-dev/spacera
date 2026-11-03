import Foundation

/// An app discovered on this Mac. Everything here is read from the app itself at runtime.
struct AppInfo: Sendable, Hashable, Identifiable {
    var url: URL
    /// `CFBundleIdentifier`. `nil` for the rare bundle that doesn't have one.
    var bundleID: String?
    var name: String
    var version: String?
    /// From the code signature. `nil` for unsigned or ad-hoc-signed apps.
    var teamID: String?
    /// `com.apple.security.application-groups` from the code signature's entitlements.
    var appGroups: [String] = []
    /// Ships with macOS (in `/System/Applications`). Its data is shown, but the app can't be removed.
    var isSystemApp: Bool = false

    var id: String { url.path }

    /// The names a data folder might use for this app: display name, bundle name, and file name.
    var candidateNames: Set<String> {
        var names: Set<String> = [name, url.deletingPathExtension().lastPathComponent]
        names = Set(names.map(AppInfo.normalize).filter { $0.count >= 3 })
        return names
    }

    /// Lower-cases a name and drops everything except letters and digits: "Visual Studio Code" becomes "visualstudiocode".
    static func normalize(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
