import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.onboarding
        VStack(spacing: 22) {
            Image(systemName: model.hasAccess ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(model.hasAccess ? Theme.sage : Theme.accent)
                .contentTransition(.symbolEffect(.replace))

            VStack(spacing: 8) {
                Text(model.hasAccess ? "All set" : "Allow Full Disk Access").font(Theme.display(28)).foregroundStyle(Theme.ink)
                Text(model.hasAccess
                     ? "Spacera can now see every app's data. Start your first scan."
                     : "Apps keep most of their data in protected folders. To show how much space each app really uses, Spacera needs Full Disk Access.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.inkSecondary)
            }

            if !model.hasAccess {
                VStack(alignment: .leading, spacing: 10) {
                    Step(number: 1, text: "Click **Open System Settings**.")
                    Step(number: 2, text: "Turn on **Spacera** in the list. If it isn't listed, click **+** and choose Spacera.")
                    Step(number: 3, text: "Come back here. Spacera notices automatically.")
                }
                .card()

                VStack(alignment: .leading, spacing: 6) {
                    Promise(symbol: "network.slash", text: "Nothing you scan ever leaves your Mac.")
                    Promise(symbol: "trash", text: "Nothing is deleted. Cleanup only moves items to the Trash, after you review them.")
                    Promise(symbol: "eye", text: "Spacera reads file names and sizes, never file contents.")
                }
                .font(.callout)
            }

            Spacer(minLength: 0)

            HStack {
                if model.hasAccess {
                    Button("Not Now") { model.dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Start Scan") { model.startScan() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue with Limited Scan") { model.continueLimited() }
                    Spacer()
                    Button("Open System Settings") { model.openSystemSettings() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(32)
        .frame(width: 520, height: model.hasAccess ? 340 : 600)
        .paperBackground()
        .animation(.default, value: model.hasAccess)
    }
}

private struct Step: View {
    var number: Int
    var text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(Theme.accent).frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.14), in: Circle())
            Text(text)
            Spacer(minLength: 0)
        }
    }
}

private struct Promise: View {
    var symbol: String
    var text: String

    var body: some View {
        Label { Text(text).foregroundStyle(Theme.inkSecondary) } icon: { Image(systemName: symbol).foregroundStyle(Theme.sage.readable) }
    }
}
