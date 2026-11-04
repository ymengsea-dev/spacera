import SwiftUI

@main
struct SpaceraApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(Theme.accent)
                .frame(minWidth: 960, minHeight: 620)
        }
        Settings {
            SettingsView().environment(environment).tint(Theme.accent)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    environment.updater.checkForUpdates()
                }
                .disabled(!environment.updater.isConfigured)
            }
            CommandMenu("Scan") {
                Button(environment.store.result == nil ? "Scan Disk" : "Rescan") {
                    environment.store.startScan()
                }
                .keyboardShortcut("r")
                .disabled(environment.store.phase.isWorking)

                Button("Stop Scan") {
                    environment.store.cancelScan()
                }
                .keyboardShortcut(".")
                .disabled(!environment.store.phase.isWorking)
            }
        }
    }
}
