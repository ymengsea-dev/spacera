import Foundation

/// Gives the resolver folder trees. It uses the main scan when the path is inside it, and otherwise
/// scans just that folder (for example, `/Library/LaunchDaemons` when only the home folder was scanned).
final class TreeSource {
    let scan: ScanResult?
    let scanner: DiskScanner
    private var cache: [String: FileNode?] = [:]

    init(scan: ScanResult?, scanner: DiskScanner) {
        self.scan = scan
        self.scanner = scanner
    }

    func node(atPath path: String) async -> FileNode? {
        if let scan {
            if let node = scan.node(atPath: path) { return node }
            let root = ScanResult.logicalPath(scan.root.name)
            let logical = ScanResult.logicalPath(path)
            // Inside the scanned area but not found means it doesn't exist (or wasn't readable).
            if logical == root || logical.hasPrefix(root.hasSuffix("/") ? root : root + "/") { return nil }
        }
        if let cached = cache[path] { return cached }
        // A file (not a folder) outside the scan: measure just that file.
        var info = stat()
        if lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFDIR {
            let node = FileNode(name: path, kind: .file, size: Int64(info.st_blocks) * 512, fileCount: 1,
                                modificationTime: TimeInterval(info.st_mtimespec.tv_sec))
            cache[path] = .some(node)
            return node
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            cache[path] = .some(nil)
            return nil
        }
        let node = try? await scanner.scanTree(root: URL(fileURLWithPath: path)).root
        cache[path] = .some(node)
        return node
    }
}
