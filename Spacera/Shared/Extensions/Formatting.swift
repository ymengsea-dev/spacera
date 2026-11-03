import Foundation

extension Int64 {
    /// Formats bytes the same way Finder does (decimal units): "12.4 GB".
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension Double {
    var formattedPercent: String { formatted(.percent.precision(.fractionLength(0...1))) }
}
