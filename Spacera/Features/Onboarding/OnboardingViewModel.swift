import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    private let store: ScanStore
    var isPresented = false
    /// Set after the user opens System Settings, so returning to the app re-checks access.
    private(set) var isWaitingForAccess = false
    private var dismissedThisSession = false

    init(store: ScanStore) {
        self.store = store
    }

    var hasAccess: Bool { store.hasFullDiskAccess }

    func presentIfNeeded() {
        store.refreshAccess()
        if !store.hasFullDiskAccess, !dismissedThisSession { isPresented = true }
    }

    func openSystemSettings() {
        isWaitingForAccess = true
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    /// Called when Spacera comes back to the front, for example after the user changed System Settings.
    func appDidBecomeActive() {
        let hadAccess = store.hasFullDiskAccess
        store.refreshAccess()
        if store.hasFullDiskAccess, !hadAccess || isWaitingForAccess {
            isWaitingForAccess = false
        }
    }

    func startScan() {
        isPresented = false
        dismissedThisSession = true
        store.startScan()
    }

    func continueLimited() {
        isPresented = false
        dismissedThisSession = true
    }
}
