import Foundation

/// How risky it is to remove an item. See docs/05-cleanup-safety.md.
enum SafetyLevel: Int, Sendable, Codable, Comparable, CaseIterable {
    /// Regenerated automatically (caches, logs). Pre-selected for cleanup.
    case safe
    /// Probably fine, but the user should check (support files, leftovers).
    case review
    /// The user's own data or an app itself. Needs a second confirmation.
    case userData
    /// Shown for information only; Spacera never removes it.
    case infoOnly

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
