# 03 · Architecture

## Pattern: MVVM, grouped by feature
```
View (SwiftUI, layout only)
  └─ observes ─▶ ViewModel (@MainActor @Observable: screen state + actions)
                    └─ calls (via protocol) ─▶ Service (actor or struct, no SwiftUI)
                                                   └─ uses ─▶ Models (Sendable value types)
```
- **Views** contain no business logic. They read ViewModel state and forward user actions to it.
- **ViewModels** each belong to one screen. They depend on service *protocols* (for example `DiskScanning` or `TrashPerforming`), so tests can use fakes.
- **Services** do the real work. Long-running services are `actor`s. They never import SwiftUI.
- **`AppEnvironment`**, created once in `SpaceraApp`, holds the shared service instances and the latest `ScanResult`. It's injected with `.environment(...)`.

## Folder layout
```
Spacera/
  App/        SpaceraApp, AppEnvironment, RootView
  Features/   Overview/, Apps/, DiskMap/, Cleanup/, Onboarding/     (each: View + ViewModel + Components/)
  Core/
    Models/   FileNode, AppInfo, AppFootprint, CleanupItem, SafetyLevel, VolumeInfo
    Services/ Scanning/, Apps/, Cleanup/, Permissions/, Updates/
  Shared/     Components/, Extensions/
  Resources/  Assets, Info.plist, entitlements
SpaceraTests/ Core/, Features/, Fixtures/
```

## Data flow
```
 ┌──────────────┐   FileNode tree   ┌──────────────────────┐   AppFootprint[]   ┌──────────────┐
 │ DiskScanner  │ ────────────────▶ │ AppFootprintResolver │ ─────────────────▶ │  Overview /  │
 │ (actor)      │                   │ + AppCatalog         │                    │  Apps / Map  │
 └──────────────┘                   └──────────────────────┘                    └──────┬───────┘
        │                                    │                                         │ user selects
        ▼                                    ▼                                         ▼
 ScanSnapshotStore                   CleanupRule engine ── CleanupItem[] ──▶ CleanupPlanner ─▶ SafetyGuard ─▶ Trasher ─▶ ActionLog
```

## Key models
- **`FileNode`** (a final class, so the tree can be shared without copying):
  - Fields: `name`, `size` (allocated bytes), `isDirectory`, `children`, `parent` (weak), and `fileCount`.
  - Lots of tiny files are collapsed into a single synthetic "N small files" node to keep memory down.
  - The full path is rebuilt from the parent chain, so each node doesn't store one.
- **`ScanResult`**: the root `FileNode`, a `VolumeInfo` snapshot, the scan date, and a list of paths that couldn't be read (permission denied).
- **`AppInfo`**: bundle URL, bundle ID, name, version, team ID, app groups, and bundle size.
- **`AppFootprint`**: an `AppInfo` plus a `[FootprintEntry]`. Each entry has a URL, a kind (cache, container, support, and so on), a size, a `MatchConfidence`, and a `SafetyLevel`.
- **`CleanupItem`**: URL, size, the rule ID that found it, the `SafetyLevel`, and the bundle ID of the app that owns it, if any.

## Concurrency
- `DiskScanner.scan(root:)` returns an `AsyncThrowingStream<ScanEvent>`:
  - `.progress(bytes, files, currentPath)` events are throttled to about 10 per second.
  - A final `.finished(ScanResult)` event delivers the result.
- The scan runs in parallel inside a `TaskGroup`, with one child task per top-level directory and a concurrency limit equal to the number of CPU cores.
- Cancelling the consuming task cancels the scan.
- ViewModels consume these streams on the main actor.
