# 04 · App attribution

This is the core feature: working out **how much space each installed app really uses**.

## 1. Finding apps (`AppCatalog`)
Search locations, each searched up to 3 levels deep so suite folders like `Adobe Photoshop 2022/` and `Unity/` are covered:
- `/Applications`
- `~/Applications`
- `/Applications/Setapp`

For each `.app` it reads:
- From `Info.plist`: `CFBundleIdentifier`, `CFBundleName` / `CFBundleDisplayName`, and `CFBundleShortVersionString`.
- From the code signature (`SecStaticCodeCopySigningInformation`): the **team ID** and the **`com.apple.security.application-groups`** entitlement.
- Its icon, from `NSWorkspace.shared.icon(forFile:)`, cached in memory.

The system's own apps in `/System/Applications` are listed for information only. Their data can't be cleaned up.

## 2. Matching data to apps (`AppFootprintResolver`)
| Location | Match key | Confidence | Default safety |
|---|---|---|---|
| The `.app` bundle | bundle path | exact | userData (uninstall) |
| `~/Library/Containers/<bundleID>` | bundle ID | exact | userData |
| `~/Library/Group Containers/<group>` | an app-group entitlement, or `<teamID>.*` | group | userData |
| `~/Library/Application Support/<bundleID>` | bundle ID | exact | review |
| `~/Library/Application Support/<Name>` or `<Vendor>/<Name>` | normalized name | likely | review |
| `~/Library/Caches/<bundleID or Name>` | bundle ID or name | exact or likely | safe |
| `~/Library/HTTPStorages/<bundleID>` | bundle ID | exact | safe |
| `~/Library/WebKit/<bundleID>` | bundle ID | exact | safe |
| `~/Library/Logs/<bundleID or Name>` | bundle ID or name | exact or likely | safe |
| `~/Library/Saved Application State/<bundleID>.savedState` | bundle ID | exact | safe |
| `~/Library/Preferences/<bundleID>.plist` | bundle ID | exact | review |
| `~/Library/Cookies/<bundleID>.binarycookies` | bundle ID | exact | review |
| `/Library/Application Support/<bundleID or Name>` | bundle ID or name | exact or likely | review |
| `~/Library/LaunchAgents/<bundleID>*.plist`, `/Library/LaunchAgents`, `/Library/LaunchDaemons` | bundle-ID prefix | likely | review |

**Name normalization:** lower-case the name, strip spaces, punctuation, and version suffixes like "2022", then compare. For example `"Visual Studio Code"` becomes `visualstudiocode`, which also matches `Code` because of an override.

**Overrides (`AttributionOverrides`):** a hand-maintained table for apps whose data lives in unusual places:
- **Xcode:** `~/Library/Developer/Xcode/DerivedData`, `Archives`, `iOS DeviceSupport`, and `~/Library/Developer/CoreSimulator`.
- **Docker:** `~/Library/Containers/com.docker.docker` (`Docker.raw`).
- **VS Code:** `~/Library/Application Support/Code`, `~/.vscode`.
- **JetBrains IDEs:** `~/Library/Caches/JetBrains/<Product>*`, `~/Library/Application Support/JetBrains/<Product>*`.
- **Unity:** `~/Library/Unity`, `~/Library/Caches/com.unity3d.*`.
- **Adobe:** `~/Library/Application Support/Adobe/<Product>`, `~/Library/Caches/Adobe`.
- **Steam:** `~/Library/Application Support/Steam` (games).
- **Ollama:** `~/.ollama/models`.

When more than one app matches the same folder, the **exact** match wins, then the longest name match. If it's still ambiguous, the entry is marked *shared*.

## 3. Leftovers from uninstalled apps
These are folders in `Containers`, `Caches`, `Application Support`, `Saved Application State`, `HTTPStorages`, `WebKit`, and `Preferences` that:
- look like a bundle ID (reverse-DNS, like `com.vendor.app`), **and**
- don't match any installed app, Apple app (`com.apple.*`), or override.

They're grouped by bundle ID, labelled "Leftover from <best-guess name>", and given the safety level *review*.

## 4. Footprint total
An app's total is its bundle size plus all of its attributed entries. Each folder is counted **once**: when folders are nested, only the outermost one counts.
