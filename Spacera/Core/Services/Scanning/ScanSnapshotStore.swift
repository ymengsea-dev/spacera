import Foundation

/// Saves scan summaries as JSON in Application Support, keeping the most recent ones.
actor ScanSnapshotStore {
    static let maxSnapshots = 30

    let fileURL: URL
    private var snapshots: [ScanSnapshot]?

    init(fileURL: URL = ScanSnapshotStore.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spacera", isDirectory: true)
            .appendingPathComponent("snapshots.json")
    }

    /// Newest first.
    func all() -> [ScanSnapshot] { load().sorted { $0.date > $1.date } }

    func latest() -> ScanSnapshot? { all().first }

    func append(_ snapshot: ScanSnapshot) {
        var list = load()
        list.append(snapshot)
        list.sort { $0.date < $1.date }
        if list.count > Self.maxSnapshots { list.removeFirst(list.count - Self.maxSnapshots) }
        save(list)
    }

    func clear() {
        snapshots = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() -> [ScanSnapshot] {
        if let snapshots { return snapshots }
        let decoded = (try? Data(contentsOf: fileURL)).flatMap { try? Self.decoder.decode([ScanSnapshot].self, from: $0) } ?? []
        snapshots = decoded
        return decoded
    }

    private func save(_ list: [ScanSnapshot]) {
        snapshots = list
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(list).write(to: fileURL, options: [.atomic])
        } catch {
            // History is a convenience; failing to save it must never break a scan.
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
