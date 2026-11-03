import Observation

/// Holds the services and state that all features share. It's created once in `SpaceraApp` and
/// injected with `.environment(_:)`. It also owns each feature's ViewModel, so a screen keeps
/// its state (selection, drill-down, filters) when you switch away and come back.
@MainActor
@Observable
final class AppEnvironment {
    let updater: UpdaterService
    let services: Services
    let store: ScanStore

    let overview: OverviewViewModel
    let apps: AppsViewModel
    let diskMap: DiskMapViewModel
    let cleanup: CleanupViewModel
    let onboarding: OnboardingViewModel

    init(services: Services = .live(), updater: UpdaterService = UpdaterService()) {
        self.services = services
        self.updater = updater
        let store = ScanStore(services: services)
        self.store = store
        self.overview = OverviewViewModel(store: store)
        self.apps = AppsViewModel(store: store)
        self.diskMap = DiskMapViewModel(store: store)
        self.cleanup = CleanupViewModel(store: store)
        self.onboarding = OnboardingViewModel(store: store)
    }

    /// Builds the review step for any set of items, from any screen.
    func makeReview(for items: [CleanupItem]) -> ReviewViewModel {
        ReviewViewModel(items: items, store: store)
    }
}
