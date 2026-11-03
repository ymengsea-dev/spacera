# 09 · Security

Spacera gets Full Disk Access and can move files to the Trash, so users have to be able to trust it. This document sets the rules.

## Dependency policy
Everything comes from Apple frameworks (SwiftUI, AppKit, Foundation, Darwin, Security, and Charts) except for **exactly two approved external dependencies**:

| Dependency | Licence | Ships in the app? | Purpose | Safeguards |
|---|---|---|---|---|
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT | **No**, it only runs on the developer's Mac | Generates `Spacera.xcodeproj` from `project.yml` | Installed with Homebrew; it produces only a project file, never app code |
| [Sparkle 2](https://github.com/sparkle-project/Sparkle) | MIT | Yes, as an embedded framework | Auto-update | Pinned to an **exact version** in `project.yml`, with `Package.resolved` committed; release notes reviewed before each upgrade |

**Adding any other dependency** (library, package, or build tool) requires explicit approval from the project owner and an update to this document.

## Network
- The **only** network traffic is Sparkle fetching `SUFeedURL` and downloading updates, over HTTPS only.
- There is no analytics, telemetry, crash uploading, or account system. Scan data never leaves the Mac.

## Update integrity
- Every update archive is signed with **EdDSA (ed25519)**. Sparkle rejects any update whose signature doesn't match `SUPublicEDKey`.
- Updates must also carry a valid Developer ID signature and notarization, which Gatekeeper checks.
- The private EdDSA key lives only in the maintainer's Keychain. `.gitignore` excludes key files.

## Code signing and entitlements
- **Hardened Runtime** is on.
- **No** `allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation`, or `get-task-allow` in Release builds.
- **Not sandboxed**, because the core feature needs it. Full Disk Access is granted by the user in System Settings; the app can't grant it to itself.

## How deletions are guarded
- `SafetyGuard` has a blocked-path list and resolves symbolic links before checking (see [05-cleanup-safety](05-cleanup-safety.md)).
- **Trash only.** The codebase never calls `removeItem` on scanned paths, and code review enforces this.
- Every removal is recorded in `ActionLog` with Put Back support.
- Tests run only on temporary fixture directories.

## Privacy
- Scan snapshots store only folder paths and sizes in `~/Library/Application Support/Spacera`, readable only by the user.
- **Clear history** in Settings deletes all snapshots and the action log.
