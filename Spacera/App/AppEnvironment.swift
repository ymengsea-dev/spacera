import Observation

/// Holds the services and state that all features share. It's created once in `SpaceraApp`
/// and injected with `.environment(_:)`. ViewModels get their services from here.
@MainActor
@Observable
final class AppEnvironment {
    let updater: UpdaterService

    init(updater: UpdaterService = UpdaterService()) {
        self.updater = updater
    }
}
