import Foundation

enum CleanupCategory: String, Sendable, CaseIterable, Codable {
    case developer, system, user, leftovers

    var title: String {
        switch self {
        case .developer: "Developer"
        case .system: "Caches & Logs"
        case .user: "Your Files"
        case .leftovers: "Leftovers"
        }
    }
}

/// Everything a rule may look at. Rules only *find* items; they never remove anything.
final class RuleContext {
    let locations: LibraryLocations
    let trees: TreeSource
    let attribution: AttributionResult?
    let now: Date
    let commands: CommandRunning

    init(locations: LibraryLocations, scan: ScanResult?, attribution: AttributionResult? = nil,
         now: Date = Date(), commands: CommandRunning = SystemCommandRunner(), scanner: DiskScanner = DiskScanner()) {
        self.locations = locations
        self.trees = TreeSource(scan: scan, scanner: scanner)
        self.attribution = attribution
        self.now = now
        self.commands = commands
    }

    var scan: ScanResult? { trees.scan }

    func homePath(_ relative: String) -> String { locations.home.appendingPathComponent(relative).path }
}

/// A data-driven cleanup rule. Adding a rule requires a safety level, an explanation, and a test (see CLAUDE.md).
struct CleanupRule: Sendable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    var category: CleanupCategory
    var safety: SafetyLevel
    /// Shown to the user: what this is, and what happens if it's removed.
    var explanation: String
    var find: @Sendable (RuleContext) async -> [CleanupItem]
}

struct RuleFinding: Sendable, Identifiable {
    var rule: CleanupRule
    /// Largest first.
    var items: [CleanupItem]

    var id: String { rule.id }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Runs the rules in order. If two rules find the same path, or one item is inside another, the first rule keeps it.
struct CleanupRuleEngine: Sendable {
    var rules: [CleanupRule] = BuiltinRules.all

    func run(_ context: RuleContext) async -> [RuleFinding] {
        var claimed: [String] = []
        var findings: [RuleFinding] = []
        for rule in rules {
            var kept: [CleanupItem] = []
            for item in await rule.find(context) {
                let overlaps = claimed.contains { item.path == $0 || item.path.hasPrefix($0 + "/") || $0.hasPrefix(item.path + "/") }
                if overlaps { continue }
                kept.append(item)
            }
            claimed += kept.map(\.path)
            kept.sort { $0.size > $1.size }
            if !kept.isEmpty { findings.append(RuleFinding(rule: rule, items: kept)) }
        }
        return findings
    }
}

// MARK: - Running Apple's command-line tools

protocol CommandRunning: Sendable {
    /// Runs an executable and returns its standard output, or nil if it failed.
    func run(_ executable: String, _ arguments: [String]) -> String?
}

struct SystemCommandRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
