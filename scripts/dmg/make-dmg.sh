#!/bin/zsh
# Packs an already signed Spacera.app into a styled DMG. Finder has to be running, and macOS may ask
# to let the terminal control it, because Finder is what saves the window layout.
#
# Usage: scripts/dmg/make-dmg.sh <path to Spacera.app> <output.dmg>
set -euo pipefail

app="$1"
out="$2"
here="${0:A:h}"
volume="Spacera"
mountpoint="/Volumes/$volume"

if [[ -e "$mountpoint" ]]; then
    echo "$mountpoint is already mounted. Eject it first." >&2
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/spacera-dmg.XXXXXX")
trap '[[ -e "$mountpoint" ]] && hdiutil detach "$mountpoint" -quiet; rm -rf "$work"' EXIT

mkdir -p "$work/stage/.background"
ditto "$app" "$work/stage/Spacera.app"
ln -s /Applications "$work/stage/Applications"
tiffutil -cathidpicheck "$here/background.png" "$here/background@2x.png" -out "$work/stage/.background/background.tiff" 2>/dev/null

hdiutil create -quiet -volname "$volume" -fs HFS+ -srcfolder "$work/stage" -format UDRW "$work/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$work/rw.dmg"

# The bounds are the 660x400 background plus Finder's title bar. Icon positions match make_background.py.
osascript <<EOF
tell application "Finder"
    tell disk "$volume"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {200, 120, 860, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Spacera.app" of container window to {165, 170}
        set position of item "Applications" of container window to {495, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Finder writes the background (pBBk) soon after the window closes, then replaces it with a version
# that has no background when the disk ejects. Keep the good file and restore it with Finder out of the way.
for attempt in {1..30}; do
    grep -aq pBBk "$mountpoint/.DS_Store" 2>/dev/null && break
    sleep 1
done
if ! grep -aq pBBk "$mountpoint/.DS_Store" 2>/dev/null; then
    echo "Finder didn't save the window layout." >&2
    exit 1
fi
cp "$mountpoint/.DS_Store" "$work/DS_Store"
hdiutil detach -quiet "$mountpoint"

hdiutil attach -quiet -readwrite -noverify -noautoopen -nobrowse "$work/rw.dmg"
cp "$work/DS_Store" "$mountpoint/.DS_Store"
sync
hdiutil detach -quiet "$mountpoint"
mkdir -p "${out:h}"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$out"
echo "Created $out"
