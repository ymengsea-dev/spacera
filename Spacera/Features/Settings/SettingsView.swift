import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmClear = false
    @State private var cleared = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Full Disk Access") {
                    HStack {
                        Text(env.store.hasFullDiskAccess ? "Granted" : "Not granted")
                            .foregroundStyle(env.store.hasFullDiskAccess ? .green : .orange)
                        Button("Open System Settings") { env.onboarding.openSystemSettings() }
                    }
                }
            }
            Section {
                LabeledContent("Scan & cleanup history") {
                    Button(cleared ? "Cleared" : "Clear History…") { confirmClear = true }
                        .disabled(cleared)
                }
                Text("Spacera keeps summaries of your last 30 scans and a log of what it moved to the Trash, so it can show growth and offer Put Back. They contain only folder names and sizes, and never leave your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .confirmationDialog("Clear all scan summaries and cleanup history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) {
                Task {
                    await env.services.snapshots.clear()
                    await env.services.log.clear()
                    await env.store.loadLastSnapshot()
                    cleared = true
                }
            }
        } message: {
            Text("Items already in the Trash stay there, but Put Back will no longer be available in Spacera. You can still use Put Back in Finder.")
        }
    }
}
