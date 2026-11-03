import Foundation

/// A record of every cleanup batch, stored as JSON in Application Support. It powers the History
/// list and Put Back. It contains only paths and sizes, never file contents.
actor ActionLog {
    static let maxBatches = 200

    let fileURL: URL
    private var batches: [TrashBatch]?

    init(fileURL: URL = ActionLog.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spacera", isDirectory: true)
            .appendingPathComponent("actions.json")
    }

    /// Newest first.
    func allBatches() -> [TrashBatch] {
        load().sorted { $0.date > $1.date }
    }

    func append(_ batch: TrashBatch) {
        var list = load()
        list.append(batch)
        if list.count > Self.maxBatches { list.removeFirst(list.count - Self.maxBatches) }
        save(list)
    }

    func markRestored(path: String) {
        var list = load()
        for b in list.indices {
            for o in list[b].outcomes.indices where list[b].outcomes[o].item.path == path && list[b].outcomes[o].status == .trashed {
                list[b].outcomes[o].status = .restored
            }
        }
        save(list)
    }

    func clear() {
        batches = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() -> [TrashBatch] {
        if let batches { return batches }
        let decoded = (try? Data(contentsOf: fileURL)).flatMap { try? Self.decoder.decode([TrashBatch].self, from: $0) } ?? []
        batches = decoded
        return decoded
    }

    private func save(_ list: [TrashBatch]) {
        batches = list
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(list).write(to: fileURL, options: [.atomic])
        } catch {
            // The log is a convenience; failing to write it must never block a cleanup.
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
