# 05 · Cleanup and safety

## Principles
1. **Never delete permanently.** Everything goes to the Trash through `FileManager.trashItem`, so the user can always undo it.
2. **Review before acting.** Every cleanup shows a review sheet listing each item, its size, and any warnings.
3. **Safe defaults.** Only items marked *safe* are pre-selected.
4. **Some paths can never be removed.** `SafetyGuard` blocks them no matter which rule or user action asks.

## Safety levels
| Level | Meaning | Examples | UI |
|---|---|---|---|
| `safe` | Regenerated automatically; deleting it costs nothing but rebuild time | Caches, logs, DerivedData, HTTPStorages | green, pre-selected |
| `review` | Probably fine, but the user should check | Old downloads, leftovers, Application Support, `node_modules` | orange, not pre-selected |
| `userData` | The user's own data or an app itself | Containers, iOS backups, large files, `.app` bundles | red, needs a second confirmation |
| `infoOnly` | Shown but can't be cleaned from Spacera | Docker.raw, Time Machine snapshots, System & Other | grey, no checkbox |

## Blocked paths (`SafetyGuard`)
Any item that is equal to, or inside, one of these paths is **rejected**:
- `/System`, `/usr`, `/bin`, `/sbin`, `/private/var/db`, `/Library/Apple`
- `/Applications/*.app` for Apple apps (bundle ID starting `com.apple.`), and everything under `/System/Applications`
- Exactly the home folder `~`, and exactly `~/Library`, `~/Documents`, `~/Desktop`, `~/Downloads` (folders *inside* these are allowed)
- Spacera's own bundle and its Application Support folder
- Symbolic links whose target is outside the item's parent folder (they're resolved first, then checked again)

## Other checks
- **The owning app is running.** If `NSRunningApplication` finds the app that owns the data running, Spacera warns the user and offers "Quit app first."
- **The file changed.** If the item's size or modification date changed since the scan, the user is warned, so nothing is removed based on stale data.
- **`userData` items** need an extra confirmation checkbox: "I understand this contains my data."

## Action log
`ActionLog` adds one JSON record per batch to `~/Library/Application Support/Spacera/actions.json`. Each record has:
- the date,
- each item's original path, Trash path, size, and rule ID,
- the outcome (whether it was trashed, or why it failed).

The Cleanup screen shows recent batches with **Show in Trash** and **Put Back**. Put Back moves the item from its Trash path back to its original path.

## Built-in rules
| Rule | Paths | Level |
|---|---|---|
| User caches | `~/Library/Caches/*` | safe |
| User logs | `~/Library/Logs/*` | safe |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData/*` | safe |
| Xcode Archives | `~/Library/Developer/Xcode/Archives/*` | review |
| iOS DeviceSupport | `~/Library/Developer/Xcode/*DeviceSupport/*` | safe |
| Unavailable simulators | from `xcrun simctl list -j` (`isAvailable == false`) | safe |
| `node_modules` | found during the scan | review |
| Package caches | `~/.npm/_cacache`, `~/Library/pnpm/store`, `~/Library/Caches/Homebrew`, `~/Library/Caches/pip`, `~/.gradle/caches`, `~/Library/Caches/CocoaPods`, `~/.cargo/registry/cache` | safe |
| Large files | files over 1 GB anywhere in the scan | userData |
| Old downloads | `~/Downloads/*` not modified in more than 90 days | review |
| iOS backups | `~/Library/Application Support/MobileSync/Backup/*` | userData |
| Mail downloads | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | review |
| Trash | `~/.Trash` | infoOnly (show the total; offer to open the Trash) |
| Docker disk image | `Docker.raw` | infoOnly |
| Time Machine local snapshots | `tmutil listlocalsnapshots /` | infoOnly |

Every rule needs a test that confirms it matches its fixture paths and that `SafetyGuard` accepts them.
