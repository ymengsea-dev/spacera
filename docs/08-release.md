# 08 · Release

Spacera is distributed **outside the Mac App Store** as a `.dmg` on GitHub Releases. Spacera is free and open source, and the project doesn't plan to pay for the Apple Developer Program, so releases are **signed with a free self-signed certificate and are not notarized**. There is **no auto-update**: users download each new version themselves.

Sparkle was removed on purpose. A self-signed app has no Team ID, so Hardened Runtime's library validation refuses to load an embedded framework like Sparkle. Keeping it would have meant turning library validation off, which isn't worth it for an app that holds Full Disk Access.

## Status
`scripts/release.sh` is written. The signing certificate doesn't exist yet, so the script stops until it is created. `SIGN_IDENTITY=- scripts/release.sh` makes an ad-hoc test build.

## Signing identity
| Option | Full Disk Access after an update | Gatekeeper on first open | Use |
|---|---|---|---|
| Ad-hoc | **Lost on every update**: the designated requirement is the build's `cdhash` | Blocked until the user allows it | Local builds only |
| **Self-signed certificate (chosen)** | Expected to be kept: the requirement is the certificate, not the build | Blocked until the user allows it | Public releases |
| Apple Development certificate | Expected to be kept | Blocked until the user allows it | Local testing only |
| Developer ID + notarization | Kept | **Opens normally** | Not planned; paid membership |

- **Apple Development is not for public releases.** It's meant for development, its certificate name can include the developer's email, and if Apple revokes it, macOS can show users a malware warning and block the app.
- **Only sign with a certificate that belongs to this project's owner.** Check the owner first, because a Mac can hold old certificates from other teams.

## One-time setup
In Keychain Access, use **Certificate Assistant → Create a Certificate** to create a self-signed certificate named `Spacera Release`, with the certificate type **Code Signing** and a long validity period. Remove any personal details, because anyone can read them from the app.

**Export it with its private key and back it up.** A new certificate changes the designated requirement, so every user would have to grant Full Disk Access again.

## Each release
Run `scripts/release.sh patch` (or `minor`, `major`). Finder has to be running, and no volume named Spacera can be mounted. The script:
1. Raises `MARKETING_VERSION` by that part (0.1.0 → 0.1.1) and `CURRENT_PROJECT_VERSION` by 1 in `project.yml`. Without a part, it builds the version already there.
2. Stops if `build/<version>/` already exists, so a published release is never overwritten, or if the `Spacera Release` certificate is missing.
3. Runs `xcodegen generate` and the unit tests.
4. Archives a Release build signed with `Spacera Release`, with Hardened Runtime on, into a temporary folder.
5. Builds the styled installer with `scripts/dmg/make-dmg.sh`. The background's source is in `scripts/dmg/`.
6. Deletes the archive.

Only the DMG stays in the repo:
```
build/<version>/Spacera-<version>.dmg
```

Then commit the version bump in `project.yml` and attach the DMG to a GitHub Release. If the build fails after the bump, fix it and run `scripts/release.sh` without a part.

## Checks
Run these before the first public release, and the first three before every release:
- `codesign -dr - Spacera.app` shows a requirement based on the certificate, **not** `cdhash`.
- `codesign -d --entitlements - Spacera.app` shows only `app-sandbox` (false), with **no** `get-task-allow` or `disable-library-validation`.
- The release build launches, from a copy of the DMG.
- Replacing the app with a newer signed build keeps **Full Disk Access** granted. Identity checks pass on test builds, but this hasn't been tried with a real grant yet.

## What users see
Gatekeeper blocks the app because it isn't notarized, and the release notes have to explain how to continue. Because each new version is a new download, users repeat steps 1–3 for every version:
1. Open Spacera from Applications and dismiss the warning.
2. Go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Authenticate when asked.
4. On first install only, grant Full Disk Access when the app asks.

To update, users download the new DMG from GitHub and replace the app in Applications. The app doesn't check for new versions, because it makes no network connections.

On macOS 15, Control-click → Open no longer bypasses this. Homebrew's official cask repository is not an alternative, because it no longer accepts apps that fail Gatekeeper.

## If the project ever moves to Developer ID
This isn't planned. Joining the Apple Developer Program would remove the Gatekeeper step, and notarization then fits in before the DMG is published. A Team ID also lets Sparkle load with library validation on, so auto-update can come back at the same time; adding it requires the project owner's approval and updates to [09-security](09-security.md). The signature change means existing users have to grant Full Disk Access once more.
