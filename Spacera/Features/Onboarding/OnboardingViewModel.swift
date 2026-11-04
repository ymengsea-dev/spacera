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

    /// Shown at launch when Full Disk Access is missing. Skipped when the last scan was already a limited one,
    /// because the user chose that; the Overview still offers access. If access was revoked after a
    /// full scan, the next scan would quietly shrink to the home folder, so the prompt comes back.
    func presentIfNeeded() {
        store.refreshAccess()
        guard !store.hasFullDiskAccess, !dismissedThisSession else { return }
        if store.lastSnapshot?.isLimitedScan == true { return }
        isPresented = true
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

    func continueLimited() { dismiss() }

    func dismiss() {
        isPresented = false
        dismissedThisSession = true
    }
}
