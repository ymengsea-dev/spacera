import Foundation

/// Capacity of the volume that was scanned, as macOS reports it.
struct VolumeInfo: Sendable, Equatable, Codable {
    var name: String
    var totalCapacity: Int64
    /// Free space that is actually free right now.
    var availableCapacity: Int64
    /// Free space including purgeable data (such as iCloud-optimised files and caches) that macOS can reclaim.
    var availableForImportantUsage: Int64

    var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    /// Space macOS can free on its own, if needed.
    var purgeableCapacity: Int64 { max(0, availableForImportantUsage - availableCapacity) }

    static func read(for url: URL) throws -> VolumeInfo {
        let values = try url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let available = Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeInfo(
            name: values.volumeName ?? "Disk",
            totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
            availableCapacity: available,
            availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage ?? available
        )
    }
}
