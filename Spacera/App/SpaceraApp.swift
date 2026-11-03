import SwiftUI

@main
struct SpaceraApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    environment.updater.checkForUpdates()
                }
                .disabled(!environment.updater.isConfigured)
            }
        }
    }
}
