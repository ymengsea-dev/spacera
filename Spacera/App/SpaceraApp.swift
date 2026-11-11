import SwiftUI

@main
struct SpaceraApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(Theme.accent)
                .frame(minHeight: 620)
                .background(WindowMinimumWidth(960))
        }
        Settings {
            SettingsView().environment(environment).tint(Theme.accent)
        }
        .commands {
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

/// Sets the window's minimum width through AppKit. A SwiftUI `.frame(minWidth:)` here would also
/// constrain the detail column while the sidebar slides open, which leaves the toolbar too little
/// room and drops the sidebar toggle into an overflow menu.
private struct WindowMinimumWidth: NSViewRepresentable {
    let width: CGFloat

    init(_ width: CGFloat) {
        self.width = width
    }

    final class Coordinator {
        var observer: NSObjectProtocol?

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let width = width
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.apply(width, to: window)
            // SwiftUI recomputes the window's minimum size as the layout changes (for example when
            // the sidebar is toggled), so apply it again each time the user starts resizing.
            coordinator.observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willStartLiveResizeNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { Self.apply(width, to: window) }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    private static func apply(_ width: CGFloat, to window: NSWindow) {
        guard window.minSize.width < width else { return }
        window.minSize.width = width
    }
}
