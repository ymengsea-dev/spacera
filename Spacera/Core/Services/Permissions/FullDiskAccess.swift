import Foundation

protocol FullDiskAccessChecking: Sendable {
    func hasFullDiskAccess() -> Bool
}

/// Checks whether the user has given Spacera Full Disk Access in System Settings.
/// There's no API for this, so it tries to read files that only an app with Full Disk Access can read.
/// It only opens them to see if that's allowed; it never reads their contents.
struct FullDiskAccess: FullDiskAccessChecking {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    func hasFullDiskAccess() -> Bool {
        let probes = [
            "Library/Application Support/com.apple.TCC/TCC.db",
            "Library/Safari/CloudTabs.db",
            "Library/Safari/Bookmarks.plist",
        ].map { home.appendingPathComponent($0).path }

        for path in probes where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            if errno == EPERM || errno == EACCES { return false }
        }
        // Fallback: list a protected folder.
        return (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Safari").path)) != nil
    }
}
