# 08 · Release

Spacera is distributed **outside the Mac App Store** as a notarized `.dmg`, and updates are delivered through Sparkle.

## One-time setup
1. Get an Apple Developer Program membership and a **Developer ID Application** certificate in your login keychain.
2. Store notarization credentials:
   `xcrun notarytool store-credentials spacera-notary --apple-id <id> --team-id <TEAMID>`
3. Generate the Sparkle EdDSA keys with `generate_keys`, from Sparkle's `bin/` folder in the package checkout.
   - The **private key** stays in your Keychain. Never commit it.
   - Put the **public key** in `project.yml` as `SUPublicEDKey`.
4. Choose where to host the appcast and DMGs (for example GitHub Releases or GitHub Pages; HTTPS only), and set `SUFeedURL` in `project.yml`.

## Each release (`scripts/release.sh`)
1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. `xcodegen generate`
3. `xcodebuild archive -scheme Spacera -configuration Release -archivePath build/Spacera.xcarchive`
4. Export with `method = developer-id` (Hardened Runtime, timestamped signature).
5. `hdiutil create -volname Spacera -srcfolder build/export/Spacera.app -ov -format UDZO dist/Spacera-<ver>.dmg`
6. `codesign` the DMG, then `xcrun notarytool submit … --keychain-profile spacera-notary --wait`, then `xcrun stapler staple`.
7. `generate_appcast dist/`, which signs the update with EdDSA and updates `appcast.xml`.
8. Upload the DMG and `appcast.xml`.

## Checks
- `spctl -a -vvv -t install dist/Spacera-<ver>.dmg` reports *accepted, source=Notarized Developer ID*.
- `codesign -dv --entitlements - Spacera.app` shows only the expected entitlements.
- A previous build updates to the new one through Sparkle.
