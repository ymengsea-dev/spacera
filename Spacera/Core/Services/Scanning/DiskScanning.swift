import Foundation

struct ScanOptions: Sendable {
    /// Files smaller than this are merged into one "N small files" node per directory, to save memory.
    /// Their bytes still count toward every total.
    var smallFileThreshold: Int64 = 256 * 1024
    /// Inside `…/Library/<name>` folders with these names, files are never merged, because app
    /// attribution needs their individual names (preference files, background-item plists, helper tools).
    var individualFileFolders: Set<String> = [
        "Preferences", "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools", "Cookies", "HTTPStorages",
    ]
    /// Directories this deep or shallower are scanned in parallel; deeper ones are scanned on the same task.
    var parallelDepth: Int = 3
    /// Don't cross into other mounted volumes.
    var staysOnVolume: Bool = true
    /// How often `.progress` events are sent.
    var progressInterval: Duration = .milliseconds(100)
    var maxRecordedUnreadablePaths: Int = 1_000

    /// The root to use for a whole-disk scan. Scanning the Data volume avoids counting firmlinked folders twice.
    static let fullDiskRoot = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
}

struct ScanProgress: Sendable, Equatable {
    var bytes: Int64
    var files: Int
    var directories: Int
    var currentPath: String
}

enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case finished(ScanResult)
}

enum ScanError: Error, Equatable {
    case cannotOpenRoot(path: String, errno: Int32)
}

/// Protocol so ViewModels can be tested with a fake scanner.
protocol DiskScanning: Sendable {
    func scan(root: URL, options: ScanOptions) -> AsyncThrowingStream<ScanEvent, Error>
}
