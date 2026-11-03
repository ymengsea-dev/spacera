import Foundation

/// The finished result of a disk scan.
struct ScanResult: Sendable {
    /// The scanned tree. `root.name` is the full path that was scanned.
    let root: FileNode
    let volume: VolumeInfo
    let date: Date
    let duration: TimeInterval
    /// Directories the scanner couldn't read, usually because it didn't have permission. Capped in length.
    let unreadablePaths: [String]

    /// Used space that the scan didn't account for: the operating system, other APFS volumes,
    /// local snapshots, and folders the scanner couldn't read. Shown as "System & Other".
    var unaccountedBytes: Int64 { max(0, volume.usedCapacity - root.size) }

    /// Finds the node for a path. It accepts both the path users see (`/Users/me/Library`) and the
    /// firmlinked Data-volume path (`/System/Volumes/Data/Users/me/Library`).
    func node(atPath path: String) -> FileNode? {
        let target = Self.logicalPath(path)
        let rootPath = Self.logicalPath(root.name)
        if target == rootPath { return root }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard target.hasPrefix(prefix) else { return nil }
        return root.descendant(at: target.dropFirst(prefix.count).split(separator: "/").map(String.init))
    }

    /// The path a user would recognise. Removes the `/System/Volumes/Data` firmlink prefix.
    static func logicalPath(_ path: String) -> String {
        let dataPrefix = "/System/Volumes/Data"
        if path == dataPrefix { return "/" }
        if path.hasPrefix(dataPrefix + "/") { return String(path.dropFirst(dataPrefix.count)) }
        return path
    }
}
