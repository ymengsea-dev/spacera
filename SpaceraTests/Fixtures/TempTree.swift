import Foundation

/// Builds a throwaway directory tree under the system temporary folder. Tests use only these trees,
/// never the real ~/Library or /Applications.
final class TempTree {
    let root: URL
    private let fileManager = FileManager.default

    init(function: String = #function) throws {
        let safeName = function.filter { $0.isLetter || $0.isNumber }
        root = fileManager.temporaryDirectory
            .appendingPathComponent("SpaceraTests-\(safeName)-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        // Restore permissions first, so tests that lock folders can still be cleaned up.
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                chmod(url.path, 0o755)
            }
        }
        try? fileManager.removeItem(at: root)
    }

    @discardableResult
    func directory(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a file of `bytes` non-zero bytes. Non-zero, so APFS can't store it sparsely.
    @discardableResult
    func file(_ relativePath: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        return url
    }

    func hardLink(from existing: String, to newPath: String) throws {
        let destination = root.appendingPathComponent(newPath)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.linkItem(at: root.appendingPathComponent(existing), to: destination)
    }

    func symlink(_ relativePath: String, pointingTo destination: URL) throws {
        try fileManager.createSymbolicLink(at: root.appendingPathComponent(relativePath), withDestinationURL: destination)
    }

    func url(_ relativePath: String) -> URL { root.appendingPathComponent(relativePath) }

    /// The reference answer: allocated size as Foundation reports it, counting each hard link once
    /// and not following symbolic links.
    func expectedAllocatedSize(of relativePath: String = "") throws -> Int64 {
        let start = relativePath.isEmpty ? root : url(relativePath)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .fileResourceIdentifierKey, .linkCountKey]
        var total: Int64 = 0
        var seen = Set<Int>()
        guard let enumerator = fileManager.enumerator(at: start, includingPropertiesForKeys: keys) else { return 0 }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true || values.isSymbolicLink == true else { continue }
            var info = stat()
            lstat(url.path, &info)
            if info.st_nlink > 1, !seen.insert(Int(info.st_ino)).inserted { continue }
            total += Int64(info.st_blocks) * 512
        }
        return total
    }
}
