#!/bin/bash
# Builds a Developer ID signed, notarized and stapled DMG in build/.
#
# One-time setup (stores an app-specific password in your keychain):
#   xcrun notarytool store-credentials temiz-notary --apple-id <you@example.com> --team-id JMAQX8DJ8J
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-temiz-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TEAM_ID="${TEAM_ID:-JMAQX8DJ8J}"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' -v t="($TEAM_ID)" '/Developer ID Application/ && index($2, t) {print $2; exit}')
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity for team $TEAM_ID in the keychain." >&2; exit 1; }

SIGN_IDENTITY="$IDENTITY" ./build.sh

APP=build/Temiz.app
# Stable name so https://github.com/berkboz/temiz/releases/latest/download/Temiz.dmg always works.
DMG="build/Temiz.dmg"
codesign --verify --deep --strict "$APP"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# Notarize the app itself first and staple it, so it opens offline even after it leaves the DMG.
echo "Submitting the app for notarization…"
ditto -c -k --keepParent "$APP" "$STAGE/Temiz.zip"
xcrun notarytool submit "$STAGE/Temiz.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$STAGE/Temiz.zip"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Temiz" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "Submitting the DMG for notarization…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"

echo
echo "Ready: $DMG"
echo "Size:   $(du -h "$DMG" | cut -f1)"
echo "SHA256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
