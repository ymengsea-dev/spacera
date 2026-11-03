import Foundation

/// Every service the app uses, in one place. Tests build this with fakes.
struct Services: Sendable {
    var locations: LibraryLocations = .current
    var scanner: any DiskScanning = DiskScanner()
    var catalog: any AppCataloging = AppCatalog()
    var resolver: any AppFootprintResolving = AppFootprintResolver()
    var rules = CleanupRuleEngine()
    var commands: any CommandRunning = SystemCommandRunner()
    var planner = CleanupPlanner()
    var trasher: any TrashPerforming
    var log: ActionLog
    var access: any FullDiskAccessChecking = FullDiskAccess()

    static func live() -> Services {
        let log = ActionLog()
        return Services(trasher: Trasher(log: log), log: log)
    }
}
