# Spacera

Spacera is a native macOS app that shows **which apps are using your storage**, each with its own icon. It can draw an interactive map of the disk and safely clean up junk by moving it to the Trash. It does what people otherwise ask an AI agent to do ("check my disk and show me what's using it"), as a standalone app that anyone can use.

Full design docs are in [`docs/`](docs/README.md). Read them before making architectural changes.

## Tech stack
- **Swift 6.4** in Swift 6 language mode (strict concurrency). **SwiftUI** with AppKit bridges. Deployment target **macOS 15**.
- Visualization: a squarified treemap built from SwiftUI views, and Swift Charts.
- File system: Darwin `getattrlistbulk`, `URLResourceValues`, `FileManager.trashItem`.
- App metadata: `Bundle` and Security.framework (`SecStaticCodeCopySigningInformation`).
- Persistence: Codable JSON files in `~/Library/Application Support/Spacera`.
- Tests: Swift Testing (`@Test`, `#expect`).
- Project: **XcodeGen** (`project.yml`). Updates: none for now; users download new versions.
- Distribution: direct download (self-signed `.dmg` on GitHub Releases, not notarized). **Not sandboxed**; the app needs Full Disk Access.

## Commands
```sh
xcodegen generate                                            # after editing project.yml or on a fresh clone
xcodebuild -project Spacera.xcodeproj -scheme Spacera build
xcodebuild test -project Spacera.xcodeproj -scheme Spacera
scripts/release.sh                                           # not written yet: archive → sign → dmg
```

## Layout: MVVM grouped by feature
```
Spacera/App/          @main, AppEnvironment (service container), RootView
Spacera/Features/<X>/ <X>View.swift + <X>ViewModel.swift (+ Components/)
Spacera/Core/Models/  plain value types (FileNode, AppInfo, AppFootprint, ...)
Spacera/Core/Services/ Scanning, Apps, Cleanup, Permissions
Spacera/Shared/       reusable views and extensions
SpaceraTests/         mirrors the app folders; Fixtures/ builds temporary directory trees
```

## Rules
- **Dependencies:** the only approved external dependency is **XcodeGen** (a build tool that never ships in the app). **Ask before adding any other library, package, or tool.** The app must embed no frameworks: self-signed builds have no Team ID, so library validation would refuse them, and it must stay on.
- **Network:** the app makes no network connections. Add no analytics, telemetry, update checks, or other networking.
- **Project file:** never commit `Spacera.xcodeproj`. Edit `project.yml` and run `xcodegen generate`.
- **MVVM:**
  - Views are layout only.
  - ViewModels are `@MainActor @Observable` and call services only through protocols, so tests can use fakes.
  - Services never import SwiftUI.
- **Deleting files:**
  - Never delete files directly.
  - Every removal goes through `SafetyGuard` and then `Trasher`, which only moves items to the Trash, and every removal is recorded in `ActionLog`.
  - Never call `removeItem` on user data.
- **Cleanup rules:** every new `CleanupRule` needs a `SafetyLevel`, a user-facing explanation, and a test.
- **Tests:** build temporary directory trees and never touch the real `~/Library` or `/Applications`.
- **Docs:** update `docs/` when you change architecture, attribution rules, the safety policy, or dependencies.
