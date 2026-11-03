import Foundation

/// The result of trying to move one item.
struct TrashOutcome: Sendable, Codable, Identifiable, Equatable {
    enum Status: String, Sendable, Codable {
        case trashed, blocked, missing, failed, restored
    }

    var item: CleanupItem
    var status: Status
    /// Where the item is in the Trash now, when it was trashed.
    var trashPath: String?
    var message: String?

    var id: String { item.path }
}

struct TrashBatch: Sendable, Codable, Identifiable {
    var id: UUID
    var date: Date
    var outcomes: [TrashOutcome]

    var trashedSize: Int64 { outcomes.filter { $0.status == .trashed }.reduce(0) { $0 + $1.item.size } }
}

protocol TrashPerforming: Sendable {
    func trash(_ items: [CleanupItem]) async -> TrashBatch
    func putBack(_ outcome: TrashOutcome) async -> TrashOutcome
}

/// The **only** code in Spacera that moves user files. It never deletes: it moves items to the Trash
/// with `FileManager.trashItem`, so the user can always put them back. Every item goes through
/// `SafetyGuard` again here, even though the planner already checked it.
struct Trasher: TrashPerforming {
    var guardrail: SafetyGuard = .standard()
    var log: ActionLog? = nil

    func trash(_ items: [CleanupItem]) async -> TrashBatch {
        var outcomes: [TrashOutcome] = []
        for item in items {
            outcomes.append(trashOne(item))
        }
        let batch = TrashBatch(id: UUID(), date: Date(), outcomes: outcomes)
        await log?.append(batch)
        return batch
    }

    private func trashOne(_ item: CleanupItem) -> TrashOutcome {
        if item.safety == .infoOnly {
            return TrashOutcome(item: item, status: .blocked, message: "Information only")
        }
        if case .blocked(let reason) = guardrail.check(item.path) {
            return TrashOutcome(item: item, status: .blocked, message: reason)
        }
        var info = stat()
        guard lstat(item.path, &info) == 0 else {
            return TrashOutcome(item: item, status: .missing, message: "It no longer exists")
        }
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: item.url, resultingItemURL: &resulting)
            return TrashOutcome(item: item, status: .trashed, trashPath: resulting?.path)
        } catch {
            return TrashOutcome(item: item, status: .failed, message: Self.describe(error))
        }
    }

    /// Moves an item from the Trash back to where it was. It refuses if something now exists at the
    /// original path, or if the item is no longer in a Trash folder.
    func putBack(_ outcome: TrashOutcome) async -> TrashOutcome {
        var result = outcome
        guard outcome.status == .trashed, let trashPath = outcome.trashPath else { return outcome }
        guard trashPath.split(separator: "/").contains(".Trash") || trashPath.split(separator: "/").contains(".Trashes") else {
            result.message = "Not in the Trash"
            return result
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: trashPath) else {
            result.message = "It's no longer in the Trash"
            return result
        }
        guard !fileManager.fileExists(atPath: outcome.item.path) else {
            result.message = "Something already exists at the original location"
            return result
        }
        do {
            try fileManager.createDirectory(at: outcome.item.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(atPath: trashPath, toPath: outcome.item.path)
            result.status = .restored
            result.message = nil
            await log?.markRestored(path: outcome.item.path)
        } catch {
            result.message = Self.describe(error)
        }
        return result
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError {
            return "Permission denied. Items in /Library may need an administrator; use Reveal in Finder to remove them there."
        }
        return nsError.localizedDescription
    }
}
