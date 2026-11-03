import Darwin
import Foundation
import Synchronization

/// A fast, parallel disk scanner built on `getattrlistbulk(2)`.
///
/// - Sizes are *allocated* bytes (`ATTR_FILE_ALLOCSIZE`), which matches what Finder and `du` report.
/// - A file with several hard links is counted only once.
/// - Symbolic links are never followed.
/// - When `staysOnVolume` is on, the scan doesn't cross into other mounted volumes.
struct DiskScanner: DiskScanning {
    func scan(root: URL, options: ScanOptions = ScanOptions()) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let state = ScanState()
            let task = Task {
                let reporter = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: options.progressInterval)
                        continuation.yield(.progress(state.snapshot()))
                    }
                }
                defer { reporter.cancel() }
                do {
                    let result = try await scanTree(root: root, options: options, state: state)
                    continuation.yield(.finished(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Scans the tree and returns the result directly. The stream API above is a wrapper around this.
    func scanTree(root: URL, options: ScanOptions = ScanOptions(), state: ScanState = ScanState()) async throws -> ScanResult {
        try Task.checkCancellation()
        let started = Date()
        let rootPath = root.standardizedFileURL.path

        var rootStat = stat()
        guard lstat(rootPath, &rootStat) == 0 else {
            throw ScanError.cannotOpenRoot(path: rootPath, errno: errno)
        }
        let rootNode = FileNode(name: rootPath, kind: .directory, modificationTime: Self.seconds(rootStat.st_mtimespec))
        let context = Context(options: options, device: rootStat.st_dev, state: state)

        try await scanDirectory(node: rootNode, path: rootPath, depth: 0, context: context)

        let volume = (try? VolumeInfo.read(for: root)) ?? VolumeInfo(name: "", totalCapacity: 0, availableCapacity: 0, availableForImportantUsage: 0)
        return ScanResult(
            root: rootNode,
            volume: volume,
            date: started,
            duration: Date().timeIntervalSince(started),
            unreadablePaths: state.unreadablePaths()
        )
    }

    // MARK: - Recursion

    private struct Context: Sendable {
        let options: ScanOptions
        let device: dev_t
        let state: ScanState
    }

    private func scanDirectory(node: FileNode, path: String, depth: Int, context: Context) async throws {
        try Task.checkCancellation()
        context.state.didEnterDirectory(path)

        let entries: [DirectoryEntry]
        do {
            entries = try Self.listDirectory(atPath: path)
        } catch {
            context.state.recordUnreadable(path, limit: context.options.maxRecordedUnreadablePaths)
            node.finalize(children: [])
            return
        }

        var children: [FileNode] = []
        var subdirectories: [(FileNode, String)] = []
        var smallBytes: Int64 = 0
        var smallCount = 0
        let threshold = context.options.smallFileThreshold

        for entry in entries {
            let childPath = path.hasSuffix("/") ? path + entry.name : path + "/" + entry.name
            switch entry.type {
            case VDIR.rawValue:
                if context.options.staysOnVolume, entry.device != context.device { continue }
                let child = FileNode(name: entry.name, kind: .directory, modificationTime: entry.modificationTime)
                children.append(child)
                subdirectories.append((child, childPath))
            default:
                // Count each hard-linked file only once.
                if entry.linkCount > 1, !context.state.claimInode(entry.fileID) { continue }
                let isLink = entry.type == VLNK.rawValue
                context.state.addFile(bytes: entry.allocatedSize)
                if !isLink, entry.allocatedSize < threshold {
                    smallBytes += entry.allocatedSize
                    smallCount += 1
                } else {
                    children.append(FileNode(
                        name: entry.name,
                        kind: isLink ? .symlink : .file,
                        size: entry.allocatedSize,
                        fileCount: isLink ? 0 : 1,
                        modificationTime: entry.modificationTime
                    ))
                }
            }
        }

        if smallCount > 0 {
            children.append(FileNode(
                name: "\(smallCount) small files",
                kind: .smallFiles(count: smallCount),
                size: smallBytes,
                fileCount: smallCount
            ))
        }

        if depth < context.options.parallelDepth, subdirectories.count > 1 {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (child, childPath) in subdirectories {
                    group.addTask {
                        try await scanDirectory(node: child, path: childPath, depth: depth + 1, context: context)
                    }
                }
                try await group.waitForAll()
            }
        } else {
            for (child, childPath) in subdirectories {
                try await scanDirectory(node: child, path: childPath, depth: depth + 1, context: context)
            }
        }

        node.finalize(children: children)
    }

    // MARK: - getattrlistbulk

    struct DirectoryEntry: Sendable {
        var name: String
        var type: UInt32
        var device: dev_t
        var fileID: UInt64
        var linkCount: UInt32
        var allocatedSize: Int64
        var modificationTime: TimeInterval
    }

    enum ListError: Error { case open(Int32), read(Int32) }

    /// The Darwin `ATTR_*` constants are imported as a mix of `Int32` and `UInt32`.
    private static func bits(_ value: some BinaryInteger) -> attrgroup_t { attrgroup_t(truncatingIfNeeded: value) }

    private static let commonAttributes: attrgroup_t =
        bits(ATTR_CMN_RETURNED_ATTRS) | bits(ATTR_CMN_ERROR) | bits(ATTR_CMN_NAME) | bits(ATTR_CMN_DEVID) |
        bits(ATTR_CMN_OBJTYPE) | bits(ATTR_CMN_MODTIME) | bits(ATTR_CMN_FILEID)
    private static let fileAttributes: attrgroup_t =
        bits(ATTR_FILE_LINKCOUNT) | bits(ATTR_FILE_ALLOCSIZE)

    /// Lists one directory with `getattrlistbulk` and closes its file descriptor before returning,
    /// so a deep or wide scan never holds many descriptors open at once.
    static func listDirectory(atPath path: String) throws -> [DirectoryEntry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ListError.open(errno) }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        request.commonattr = commonAttributes
        request.fileattr = fileAttributes

        let bufferSize = 128 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var entries: [DirectoryEntry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw ListError.read(errno)
            }
            var entryStart = buffer
            for _ in 0..<count {
                let length = Int(entryStart.loadUnaligned(as: UInt32.self))
                if let entry = parseEntry(entryStart) { entries.append(entry) }
                entryStart += length
            }
        }
        return entries
    }

    /// Parses one entry. The attributes appear in the order `getattrlistbulk(2)` documents,
    /// and only the ones listed in `returned` are present.
    private static func parseEntry(_ start: UnsafeMutableRawPointer) -> DirectoryEntry? {
        var cursor = start + MemoryLayout<UInt32>.size // skip the length field
        let returned = cursor.loadUnaligned(as: attribute_set_t.self)
        cursor += MemoryLayout<attribute_set_t>.size

        func has(_ bit: some BinaryInteger, in group: attrgroup_t) -> Bool { group & bits(bit) != 0 }

        if has(ATTR_CMN_ERROR, in: returned.commonattr) {
            let error = cursor.loadUnaligned(as: UInt32.self)
            cursor += MemoryLayout<UInt32>.size
            if error != 0 { return nil }
        }

        var name = ""
        if has(ATTR_CMN_NAME, in: returned.commonattr) {
            let reference = cursor.loadUnaligned(as: attrreference_t.self)
            let namePointer = (cursor + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
            name = String(cString: namePointer)
            cursor += MemoryLayout<attrreference_t>.size
        }
        if name.isEmpty || name == "." || name == ".." { return nil }

        var device: dev_t = 0
        if has(ATTR_CMN_DEVID, in: returned.commonattr) {
            device = cursor.loadUnaligned(as: dev_t.self)
            cursor += MemoryLayout<dev_t>.size
        }
        var type: UInt32 = VNON.rawValue
        if has(ATTR_CMN_OBJTYPE, in: returned.commonattr) {
            type = cursor.loadUnaligned(as: fsobj_type_t.self)
            cursor += MemoryLayout<fsobj_type_t>.size
        }
        var modificationTime: TimeInterval = 0
        if has(ATTR_CMN_MODTIME, in: returned.commonattr) {
            modificationTime = seconds(cursor.loadUnaligned(as: timespec.self))
            cursor += MemoryLayout<timespec>.size
        }
        var fileID: UInt64 = 0
        if has(ATTR_CMN_FILEID, in: returned.commonattr) {
            fileID = cursor.loadUnaligned(as: UInt64.self)
            cursor += MemoryLayout<UInt64>.size
        }
        var linkCount: UInt32 = 1
        if has(ATTR_FILE_LINKCOUNT, in: returned.fileattr) {
            linkCount = cursor.loadUnaligned(as: UInt32.self)
            cursor += MemoryLayout<UInt32>.size
        }
        var allocatedSize: Int64 = 0
        if has(ATTR_FILE_ALLOCSIZE, in: returned.fileattr) {
            allocatedSize = cursor.loadUnaligned(as: off_t.self)
            cursor += MemoryLayout<off_t>.size
        }

        return DirectoryEntry(
            name: name, type: type, device: device, fileID: fileID,
            linkCount: linkCount, allocatedSize: allocatedSize, modificationTime: modificationTime
        )
    }

    private static func seconds(_ time: timespec) -> TimeInterval {
        TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000
    }
}

/// State shared by every scanning task. All of it is protected by `Mutex`.
final class ScanState: Sendable {
    private struct Counters {
        var bytes: Int64 = 0
        var files = 0
        var directories = 0
        var currentPath = ""
    }

    private let counters = Mutex(Counters())
    private let seenInodes = Mutex(Set<UInt64>())
    private let unreadable = Mutex([String]())

    func addFile(bytes: Int64) {
        counters.withLock {
            $0.bytes += bytes
            $0.files += 1
        }
    }

    func didEnterDirectory(_ path: String) {
        counters.withLock {
            $0.directories += 1
            $0.currentPath = path
        }
    }

    /// Returns `true` the first time an inode is seen. Called only for files with more than one hard link.
    func claimInode(_ inode: UInt64) -> Bool {
        seenInodes.withLock { $0.insert(inode).inserted }
    }

    func recordUnreadable(_ path: String, limit: Int) {
        unreadable.withLock { if $0.count < limit { $0.append(path) } }
    }

    func unreadablePaths() -> [String] { unreadable.withLock { $0 } }

    func snapshot() -> ScanProgress {
        counters.withLock { ScanProgress(bytes: $0.bytes, files: $0.files, directories: $0.directories, currentPath: $0.currentPath) }
    }
}
