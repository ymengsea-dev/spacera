#!/bin/zsh
# Builds an ad-hoc signed release DMG into build/<version>/. The archive is made in a temporary folder and deleted
# afterwards, so the DMG is all that stays. See docs/08-release.md.
#
# Usage: scripts/release.sh [patch|minor|major]
#   With a part, raises MARKETING_VERSION in project.yml by that part and CURRENT_PROJECT_VERSION by 1.
#   Without one, builds the version already in project.yml.
#   SIGN_IDENTITY=<certificate name> signs with that certificate instead.
set -euo pipefail

name="Spacera"
identity="${SIGN_IDENTITY:--}"
root="${0:A:h:h}"
cd "$root"

version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml)
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$build" =~ '^[0-9]+$' ]]; then
    echo "Could not read MARKETING_VERSION and CURRENT_PROJECT_VERSION from project.yml." >&2
    exit 1
fi

if (( $# > 0 )); then
    parts=("${(@s:.:)version}")
    case "$1" in
        major) version="$((parts[1] + 1)).0.0" ;;
        minor) version="${parts[1]}.$((parts[2] + 1)).0" ;;
        patch) version="${parts[1]}.${parts[2]}.$((parts[3] + 1))" ;;
        *) echo "Usage: scripts/release.sh [patch|minor|major]" >&2; exit 1 ;;
    esac
    build=$((build + 1))
fi

out="build/$version"
dmg="$out/$name-$version.dmg"
if [[ -e "$out" ]]; then
    echo "$out already exists. Bump the version, or delete that folder to rebuild it." >&2
    exit 1
fi

if [[ "$identity" != "-" ]] && ! security find-identity -v -p codesigning | grep -qF "\"$identity\""; then
    echo "No code signing certificate named \"$identity\". Create it first, or leave SIGN_IDENTITY unset to sign ad-hoc." >&2
    exit 1
fi

if (( $# > 0 )); then
    sed -i '' -E \
        -e "s/^( *MARKETING_VERSION: )\"[^\"]*\"/\1\"$version\"/" \
        -e "s/^( *CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$build\"/" \
        project.yml
    echo "Version is now $version ($build). If the build fails, fix it and run scripts/release.sh without a part."
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/$name-release.XXXXXX")
trap 'rm -rf "$work"' EXIT

xcodegen generate --quiet
xcodebuild test -quiet -project "$name.xcodeproj" -scheme "$name" -destination 'platform=macOS'
xcodebuild archive -quiet -project "$name.xcodeproj" -scheme "$name" -configuration Release \
    -archivePath "$work/$name.xcarchive" CODE_SIGN_IDENTITY="$identity" CODE_SIGN_STYLE=Manual

mkdir -p "$out"
scripts/dmg/make-dmg.sh "$work/$name.xcarchive/Products/Applications/$name.app" "$dmg"

echo
echo "Release $version ($build), signed with \"$identity\":"
echo "  $dmg"
