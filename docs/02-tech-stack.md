# 02 · Tech stack

| Layer | Technology | Why |
|---|---|---|
| Language | **Swift 6.4**, Swift 6 language mode (strict concurrency) | Native and fast, and the compiler catches data races in the parallel scanner |
| UI | **SwiftUI** (`NavigationSplitView`, `@Observable`), with **AppKit** bridges (`NSWorkspace`, `NSRunningApplication`) | Modern native Mac UI; AppKit supplies app icons, running-app info, and Reveal in Finder |
| Visualization | A squarified **treemap** built from SwiftUI views, **Swift Charts** (bars) | Blocks are capped at 200 per folder, so plain views stay fast and get hover, context menus, and accessibility for free; Charts covers the simple charts |
| File system | Darwin **`getattrlistbulk`**, `URLResourceValues`, `FileManager.trashItem` | Fastest way to list directories on APFS; Trash keeps cleanup undoable |
| App metadata | `Bundle`, **Security.framework** (`SecStaticCodeCopySigningInformation`) | Reads each app's bundle ID, team ID, and app-group entitlements |
| Concurrency | `TaskGroup`, `AsyncStream`, actors | Parallel scanning with progress and cancellation |
| Persistence | Codable JSON in `~/Library/Application Support/Spacera` | Simple and transparent; no database needed |
| Testing | **Swift Testing** in the `SpaceraTests` target | Built into Xcode |
| Project | **XcodeGen** (`project.yml`) | The project is a short text file; the `.xcodeproj` is generated and never committed |
| Updates | None for now; users download new versions | Auto-update needs a framework that an ad-hoc signed app can't load with library validation on (see [08-release](08-release.md)) |
| Release | Ad-hoc signing, Hardened Runtime, `hdiutil`, GitHub Releases | Direct distribution without a paid Apple Developer membership; not notarized |

## Platform
- **Minimum macOS:** 15.0
- **Developed with:** Xcode 27 and the Swift 6.4 toolchain
- **Architectures:** Universal (arm64 + x86_64)

## Why not…
- **The Mac App Store?** The sandbox blocks reading other apps' `~/Library` data, which is the core feature.
- **Electron, Tauri, or Flutter?** A native look, small size, a fast file system walker, and direct access to app icons and code signatures all point to Swift.
- **SwiftData or Core Data?** Scan snapshots are small and written once, so JSON is enough and easier to inspect.
