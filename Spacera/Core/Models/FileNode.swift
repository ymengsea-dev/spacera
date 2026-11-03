import Foundation

/// One node in the scanned file tree.
///
/// This is a reference type, so the tree (often hundreds of thousands of nodes) can be shared
/// between ViewModels without copying, and so children can point back to their parent.
/// The scanner fills in nodes on background tasks. Once `DiskScanner` returns the finished
/// tree, nothing changes it again, which is why it is safe to mark it `@unchecked Sendable`.
final class FileNode: @unchecked Sendable, Identifiable {
    enum Kind: Sendable, Equatable {
        case directory
        case file
        case symlink
        /// A synthetic node that stands in for many small files in one directory.
        case smallFiles(count: Int)
    }

    /// The last path component. For the root node, this is the full path that was scanned.
    let name: String
    let kind: Kind
    /// Bytes allocated on disk, including all descendants for a directory.
    private(set) var size: Int64
    /// Number of regular files at or below this node.
    private(set) var fileCount: Int
    /// Seconds since 1970. For a directory, this is the directory entry's own modification time.
    let modificationTime: TimeInterval
    /// Sorted by size, largest first.
    private(set) var children: [FileNode]
    private(set) weak var parent: FileNode?

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    var isDirectory: Bool { kind == .directory }
    var modificationDate: Date { Date(timeIntervalSince1970: modificationTime) }

    init(name: String, kind: Kind, size: Int64 = 0, fileCount: Int = 0, modificationTime: TimeInterval = 0) {
        self.name = name
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
        self.modificationTime = modificationTime
        self.children = []
    }

    /// The full path, rebuilt from the chain of parents.
    var path: String {
        var components: [String] = []
        var node: FileNode? = self
        while let current = node {
            components.append(current.name)
            node = current.parent
        }
        guard var result = components.popLast() else { return "" }
        for component in components.reversed() {
            result += result.hasSuffix("/") ? component : "/" + component
        }
        return result
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

    func child(named name: String) -> FileNode? {
        children.first { $0.name == name }
    }

    /// Finds a descendant from relative path components, such as `["Library", "Caches"]`.
    func descendant(at components: some Sequence<String>) -> FileNode? {
        var node: FileNode? = self
        for component in components where !component.isEmpty {
            node = node?.child(named: component)
            if node == nil { return nil }
        }
        return node
    }

    /// Visits this node and every descendant, depth first. Return `false` from `visit` to skip a node's children.
    func walk(_ visit: (FileNode) -> Bool) {
        guard visit(self) else { return }
        for child in children { child.walk(visit) }
    }

    // MARK: Building the tree (used only by the scanner)

    /// Attaches the children, adds up their sizes, and sorts them largest first. Call this once per directory.
    func finalize(children newChildren: [FileNode]) {
        precondition(kind == .directory, "Only directories have children")
        var total: Int64 = size
        var files = fileCount
        for child in newChildren {
            child.parent = self
            total += child.size
            files += child.fileCount
        }
        children = newChildren.sorted { $0.size > $1.size }
        size = total
        fileCount = files
    }
}
