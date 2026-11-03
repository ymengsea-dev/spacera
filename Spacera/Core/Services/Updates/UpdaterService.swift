import Foundation
import Sparkle

/// A thin wrapper around Sparkle. Sparkle is an approved dependency (see docs/09-security.md).
/// The updater only starts once `SUFeedURL` and `SUPublicEDKey` are both set in Info.plist,
/// so development builds never connect to the network.
@MainActor
final class UpdaterService {
    private let controller: SPUStandardUpdaterController?

    var isConfigured: Bool { controller != nil }

    init(bundle: Bundle = .main) {
        if Self.hasValidConfiguration(info: bundle.infoDictionary ?? [:]) {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            controller = nil
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    nonisolated static func hasValidConfiguration(info: [String: Any]) -> Bool {
        guard
            let feed = info["SUFeedURL"] as? String,
            let url = URL(string: feed), url.scheme == "https",
            let key = info["SUPublicEDKey"] as? String, !key.isEmpty
        else { return false }
        return true
    }
}
