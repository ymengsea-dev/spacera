# Spacera

**See which apps are using your Mac's storage, and clean it up safely.**

- **Per-app storage, with icons.** Spacera adds up each installed app's bundle and all of its hidden data (Caches, Containers, Application Support, Logs, and more), so you can see what each app really costs you.
- **Disk map.** An interactive sunburst of your disk. Click to drill into any folder.
- **Smart cleanup.** Finds developer junk (Xcode DerivedData, `node_modules`, package caches), leftovers from uninstalled apps, large files, and old downloads.
- **Safe by design.** Everything goes to the Trash after a review step. System paths are blocked.

## Requirements
- macOS 15 or later
- Full Disk Access, so the app can see all app data

## Build from source
```sh
brew install xcodegen
xcodegen generate
open Spacera.xcodeproj
```

## Documentation
See [`docs/`](docs/README.md).
