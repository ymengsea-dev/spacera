import Foundation
import Testing
@testable import Spacera

struct DiskScannerTests {
    let scanner = DiskScanner()

    @Test func totalsMatchAllocatedSizeOnDisk() async throws {
        let tree = try TempTree()
        try tree.file("a.bin", bytes: 1_000_000)
        try tree.file("docs/b.txt", bytes: 12_345)
        try tree.file("docs/deep/c/d/e.bin", bytes: 3_000_000)
        try tree.file("empty.txt", bytes: 0)
        try tree.directory("emptyDir")

        let result = try await scanner.scanTree(root: tree.root)

        #expect(result.root.size == (try tree.expectedAllocatedSize()))
        #expect(result.root.fileCount == 4)
        let docs = try #require(result.root.child(named: "docs"))
        #expect(docs.size == (try tree.expectedAllocatedSize(of: "docs")))
    }

    @Test func childrenAreSortedLargestFirstAndParentsAreLinked() async throws {
        let tree = try TempTree()
        try tree.file("small/x.bin", bytes: 300_000)
        try tree.file("large/y.bin", bytes: 3_000_000)
        try tree.file("medium/z.bin", bytes: 1_000_000)

        let result = try await scanner.scanTree(root: tree.root)

        #expect(result.root.children.map(\.name) == ["large", "medium", "small"])
        let y = try #require(result.root.descendant(at: ["large", "y.bin"]))
        #expect(y.parent?.name == "large")
        #expect(y.path == tree.url("large/y.bin").path)
    }

    @Test func hardLinksAreCountedOnce() async throws {
        let tree = try TempTree()
        try tree.file("original.bin", bytes: 2_000_000)
        try tree.hardLink(from: "original.bin", to: "other/link.bin")

        let result = try await scanner.scanTree(root: tree.root)

        let single = try tree.expectedAllocatedSize(of: "") // the reference also counts it once
        #expect(result.root.size == single)
        #expect(result.root.fileCount == 1)
    }

    @Test func symlinksAreNotFollowed() async throws {
        let outside = try TempTree()
        try outside.file("huge.bin", bytes: 5_000_000)
        let tree = try TempTree()
        try tree.file("real.bin", bytes: 400_000)
        try tree.symlink("link-to-outside", pointingTo: outside.root)

        let result = try await scanner.scanTree(root: tree.root)

        #expect(result.root.size < 5_000_000)
        let link = try #require(result.root.child(named: "link-to-outside"))
        #expect(link.kind == .symlink)
    }

    @Test func smallFilesAreMergedButStillCounted() async throws {
        let tree = try TempTree()
        for index in 0..<20 { try tree.file("many/f\(index).txt", bytes: 1_000) }
        try tree.file("many/big.bin", bytes: 1_000_000)

        let result = try await scanner.scanTree(root: tree.root, options: ScanOptions(smallFileThreshold: 100_000))

        let many = try #require(result.root.child(named: "many"))
        #expect(many.children.count == 2)
        let merged = try #require(many.children.first { if case .smallFiles = $0.kind { true } else { false } })
        #expect(merged.kind == .smallFiles(count: 20))
        #expect(many.fileCount == 21)
        #expect(many.size == (try tree.expectedAllocatedSize(of: "many")))
    }

    @Test func unreadableDirectoryIsRecordedAndScanContinues() async throws {
        let tree = try TempTree()
        try tree.file("ok/a.bin", bytes: 500_000)
        try tree.file("locked/secret.bin", bytes: 500_000)
        chmod(tree.url("locked").path, 0o000)

        let result = try await scanner.scanTree(root: tree.root)

        #expect(result.unreadablePaths == [tree.url("locked").path])
        #expect(result.root.child(named: "ok")?.size ?? 0 > 0)
        #expect(result.root.child(named: "locked")?.size == 0)
    }

    @Test func parallelAndSerialScansAgree() async throws {
        let tree = try TempTree()
        for a in 0..<4 { for b in 0..<4 { for c in 0..<3 {
            try tree.file("d\(a)/d\(b)/f\(c).bin", bytes: 10_000 * (a + b + c + 1))
        } } }

        let parallel = try await scanner.scanTree(root: tree.root, options: ScanOptions(parallelDepth: 5))
        let serial = try await scanner.scanTree(root: tree.root, options: ScanOptions(parallelDepth: 0))

        #expect(parallel.root.size == serial.root.size)
        #expect(parallel.root.fileCount == serial.root.fileCount)
        #expect(parallel.root.fileCount == 48)
    }

    @Test func cancelledScanThrows() async throws {
        let tree = try TempTree()
        try tree.file("a/b.bin", bytes: 10_000)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scanTree(root: tree.root)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func missingRootThrows() async {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        await #expect(throws: ScanError.self) { try await scanner.scanTree(root: missing) }
    }

    @Test func streamDeliversFinishedEvent() async throws {
        let tree = try TempTree()
        try tree.file("x.bin", bytes: 700_000)

        var finished: ScanResult?
        for try await event in scanner.scan(root: tree.root, options: ScanOptions()) {
            if case .finished(let result) = event { finished = result }
        }
        let result = try #require(finished)
        #expect(result.root.size == (try tree.expectedAllocatedSize()))
    }

    @Test func nodeLookupAcceptsDataVolumePrefix() async throws {
        let tree = try TempTree()
        try tree.file("Library/Caches/com.example/blob.bin", bytes: 300_000)
        let result = try await scanner.scanTree(root: tree.root)

        let path = tree.url("Library/Caches/com.example").path
        #expect(result.node(atPath: path)?.name == "com.example")
        #expect(result.node(atPath: path + "/missing") == nil)
        #expect(result.node(atPath: "/elsewhere") == nil)
        #expect(ScanResult.logicalPath("/System/Volumes/Data/Users/me") == "/Users/me")
        #expect(ScanResult.logicalPath("/System/Volumes/Data") == "/")
    }
}
