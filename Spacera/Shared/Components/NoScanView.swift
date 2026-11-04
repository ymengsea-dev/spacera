import SwiftUI

/// Shown by a screen that needs a scan before it has anything to show. Matches the Overview's start screen.
struct NoScanView: View {
    @Environment(AppEnvironment.self) private var env
    var title = "No scan yet"
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(Theme.display(30)).foregroundStyle(Theme.ink)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: 420)
            Group {
                if env.store.phase.isWorking {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(env.store.phase.title).foregroundStyle(Theme.inkSecondary)
                        }
                        Button("Stop Scan") { env.store.cancelScan() }
                            .buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Button {
                        env.store.startScan()
                    } label: {
                        Text("Scan Disk").padding(.horizontal, 14).padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.top, 10)
        }
        .padding(40)
        .paperBackground()
    }
}
