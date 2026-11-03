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

**Nothing is hard-coded.** Apps are discovered on each Mac at scan time. **Spotlight** (`MDQuery` for `com.apple.application-bundle`) also finds apps installed anywhere else. These Spotlight results are filtered out:
- helper apps inside other bundles, and apps in the Trash, on other volumes, or under any `Library/` folder;
- build output from people's own projects: paths through `target/`, `build/`, `builds/`, `dist/`, `.build/`, `out/`, `node_modules/`, `debug/`, or `release/`, and anything inside a folder that contains `.git`.

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

**Overrides (`AttributionOverrides`):** an *optional* hand-maintained table that only adds extra paths. Every app is matched by the general rules above without it. If an installed app's bundle ID matches an override exactly, only that app gets it. Prefix matches (for example `com.google.Chrome.app.<id>` web-app shims) are used only when no app matches exactly. The table lists for apps whose data lives in unusual places:
- **Xcode:** `~/Library/Developer/Xcode/DerivedData`, `Archives`, `iOS DeviceSupport`, and `~/Library/Developer/CoreSimulator`.
- **Docker:** `~/Library/Containers/com.docker.docker` (`Docker.raw`).
- **VS Code:** `~/Library/Application Support/Code`, `~/.vscode`.
- **JetBrains IDEs:** `~/Library/Caches/JetBrains/<Product>*`, `~/Library/Application Support/JetBrains/<Product>*`.
- **Unity:** `~/Library/Unity`, `~/Library/Caches/com.unity3d.*`.
- **Adobe:** `~/Library/Application Support/Adobe/<Product>`, `~/Library/Caches/Adobe`.
- **Steam:** `~/Library/Application Support/Steam` (games).
- **Ollama:** `~/.ollama`.

When more than one app matches the same folder, the **exact** match wins, then the longest name match. If it's still ambiguous, the entry is marked *shared*.

## 3. Leftovers from uninstalled apps
These are folders in `Containers`, `Caches`, `Application Support`, `Saved Application State`, `HTTPStorages`, `WebKit`, and `Preferences` that:
- look like a bundle ID (reverse-DNS, like `com.vendor.app`), **and**
- don't match any installed app, Apple app (`com.apple.*`), or override.

They're grouped by bundle ID, labelled "Leftover from <best-guess name>", and given the safety level *review*.

Identifiers that belong to command-line tools or to frameworks many apps embed are never reported as leftovers: `org.swift.*`, `com.Breakpad.*`, Sparkle, Sentry, Keystone, Homebrew, and similar (`AttributionOverrides.nonAppIdentifierPrefixes`).

## 3b. Background items
Spacera reads every plist in `~/Library/LaunchAgents`, `/Library/LaunchAgents`, and `/Library/LaunchDaemons`, and lists every file in `/Library/PrivilegedHelperTools`.
- **Owned:** the item's `Program` or `ProgramArguments[0]` is inside an installed app's bundle, or its `AssociatedBundleIdentifiers` names an installed app. It's shown on that app's page with the note "Runs <path>".
- **Orphaned:** the program it should run no longer exists, or its associated app isn't installed. Privileged helper tools that no installed app matches are orphaned too. These are reported as leftovers with a warning note. They're typically left behind when an app is dragged to the Trash, and helper tools keep running with admin rights.
- The scanner never merges small files in these folders (or in `Preferences`, `Cookies`, and `HTTPStorages`), so each item keeps its own name.

Spacera is **not** malware detection; macOS XProtect does that. It shows what is installed and running in the background, and what each item belongs to.

## 4. Footprint total
An app's total is its bundle size plus all of its attributed entries. Each folder is counted **once**: when folders are nested, only the outermost one counts.
