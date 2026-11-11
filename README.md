# Spacera

**See which apps are using your Mac's storage, and clean it up safely.**

- **Per-app storage, with icons.** Spacera adds up each installed app's bundle and all of its hidden data (Caches, Containers, Application Support, Logs, and more), so you can see what each app really costs you.
- **Disk map.** Your disk as blocks sized by what they use. Click to drill into any folder.
- **Smart cleanup.** Finds developer junk (Xcode DerivedData, `node_modules`, package caches), leftovers from uninstalled apps, large files, and old downloads.
- **Safe by design.** Everything goes to the Trash after a review step. System paths are blocked.

## Requirements
- macOS 15 or later
- Full Disk Access, so the app can see all app data

## Tech Stack


- **Swift 6.4** (strict concurrency mode) with **SwiftUI** and AppKit bridges
- **Visualization:** a SwiftUI treemap and Swift Charts
- **File system:** Darwin `getattrlistbulk`, `URLResourceValues`, `FileManager.trashItem`
- **App metadata:** `Bundle` and Security.framework
- **Persistence:** Codable JSON in `~/Library/Application Support/Spacera`
- **Testing:** Swift Testing with temporary directory fixtures
- **Build system:** XcodeGen (configuration-driven project generation)
- **Updates:** manual download from GitHub Releases (no auto-update for now)
- **Distribution:** ad-hoc signed `.dmg` on GitHub Releases, not notarized (not sandboxed)

## Getting Started



### Build from source
```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Spacera.xcodeproj -scheme Spacera build
```

### Run the app


```sh
open "$(xcodebuild -project Spacera.xcodeproj -scheme Spacera -showBuildSettings 2>/dev/null | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p')/Spacera.app"
```

### Run tests


```sh
xcodebuild test -project Spacera.xcodeproj -scheme Spacera
```

### Build and release


```sh
scripts/release.sh patch   # bump version, test, archive, sign, DMG → build/<version>/ (docs/08-release.md)
```

## Project Layout

```
Spacera/

├── App/              @main, AppEnvironment, RootView
├── Features/         MVVM by feature (Views + ViewModels + Components)
├── Core/
│   ├── Models/       Value types (FileNode, AppInfo, AppFootprint, etc.)
│   └── Services/     Business logic (Scanning, Apps, Cleanup, Permissions)
└── Shared/           Reusable views and extensions

SpaceraTests/         Mirrors app structure; Fixtures/ for temporary test trees
docs/                 Architecture and design decisions
```

## Architecture



Spacera follows **MVVM grouped by feature:**

- **Views** are layout-only; they receive data and send user actions upward.
- **ViewModels** are `@MainActor @Observable` and call services only through protocols (enables testing with fakes).
- **Services** are protocol-driven, never import SwiftUI, and own all business logic.
- **Models** are plain Swift value types with no dependencies.

## Safety & Cleanup

- All file removals go through `SafetyGuard` (validates against system paths) then `Trasher` (moves to Trash, never direct delete).
- Every removal is recorded in `ActionLog` for audit trails.
- Each `CleanupRule` has a `SafetyLevel`, user-facing explanation, and tests.

## Dependencies

**XcodeGen** (build tool, never shipped) is the only approved external dependency, and the app makes no network connections. No third-party Swift Package Manager imports in the app. Ask before adding new dependencies.

## Contributing

- Edit `project.yml` (not the Xcode project file directly); run `xcodegen generate` after changes.
- Write tests for all cleanup rules.
- Update [`docs/`](docs/README.md) for architectural changes or design decisions.
- Never commit temporary Xcode build artifacts.

## Documentation

Full design docs, safety policies, and architecture details are in [`docs/`](docs/README.md).
