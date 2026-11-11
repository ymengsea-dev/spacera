# 09 · Security

Spacera gets Full Disk Access and can move files to the Trash, so users have to be able to trust it. This document sets the rules.

## Dependency policy
Everything comes from Apple frameworks (SwiftUI, AppKit, Foundation, Darwin, Security, and Charts) except for **exactly one approved external dependency**, which doesn't ship in the app:

| Dependency | Licence | Ships in the app? | Purpose | Safeguards |
|---|---|---|---|---|
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT | **No**, it only runs on the developer's Mac | Generates `Spacera.xcodeproj` from `project.yml` | Installed with Homebrew; it produces only a project file, never app code |

**Adding any other dependency** (library, package, or build tool) requires explicit approval from the project owner and an update to this document.

## Network
- The app makes **no network connections** and contains no networking code.
- There is no analytics, telemetry, crash uploading, account system, or update check. Scan data never leaves the Mac.

## Release integrity
- Releases are signed with a self-signed certificate and are **not notarized** (see [08-release](08-release.md)), so Apple doesn't vouch for them. The signature only shows that a build came from whoever holds the certificate.
- The private signing key lives only in the maintainer's Keychain and a secure backup. `.gitignore` excludes key files. A self-signed certificate can't be revoked, so if the key leaks, the only fix is a new certificate.

## Code signing and entitlements
- **Hardened Runtime** is on in Release builds.
- **Library validation stays on.** **No** `allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation`, or `get-task-allow` in Release builds. This is why the app embeds no frameworks: with no Team ID, Hardened Runtime would refuse to load them (see [08-release](08-release.md)).
- Releases must use the **same signing certificate** every time. macOS ties the Full Disk Access grant to the signature, so ad-hoc signing or a new certificate makes users grant it again.
- Only sign with a certificate that belongs to the project owner, and never ship a build signed with an Apple Development certificate.
- **Not sandboxed**, because the core feature needs it. Full Disk Access is granted by the user in System Settings; the app can't grant it to itself.

## How deletions are guarded
- `SafetyGuard` has a blocked-path list and resolves symbolic links before checking (see [05-cleanup-safety](05-cleanup-safety.md)).
- **Trash only.** The codebase never calls `removeItem` on scanned paths, and code review enforces this.
- Every removal is recorded in `ActionLog` with Put Back support.
- Tests run only on temporary fixture directories.

## Privacy
- Scan snapshots store only folder paths and sizes in `~/Library/Application Support/Spacera`, readable only by the user.
- **Clear history** in Settings deletes all snapshots and the action log.
