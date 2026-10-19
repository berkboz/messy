#!/bin/bash
# Builds a Developer ID signed, notarized and stapled DMG in build/.
#
# Then writes build/appcast.xml for Sparkle, and with PUBLISH=1 creates the GitHub release with both files.
# Shipping an update to everyone: raise CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist,
# then run `PUBLISH=1 ./release.sh` (NOTES=path/to/notes.md for the release notes).
#
# One-time setup (stores an app-specific password in your keychain):
#   xcrun notarytool store-credentials messy-notary --apple-id <you@example.com> --team-id JMAQX8DJ8J
# The Sparkle signing key was made once with .build/artifacts/sparkle/Sparkle/bin/generate_keys and lives in
# the login keychain; its public half is SUPublicEDKey in Info.plist. Back it up: generate_keys -x <file>.
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-messy-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
REPO=berkboz/messy
FEED="https://github.com/$REPO/releases/latest/download/appcast.xml"

# Sparkle compares CFBundleVersion, so every release needs a higher one than the published feed.
PUBLISHED=$(curl -fsL "$FEED" 2>/dev/null | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | head -1 || true)
if [ -n "$PUBLISHED" ] && [ "$BUILD" -le "$PUBLISHED" ]; then
  echo "CFBundleVersion $BUILD is not above the published build $PUBLISHED. Raise it in Resources/Info.plist." >&2
  exit 1
fi
TEAM_ID="${TEAM_ID:-JMAQX8DJ8J}"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' -v t="($TEAM_ID)" '/Developer ID Application/ && index($2, t) {print $2; exit}')
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity for team $TEAM_ID in the keychain." >&2; exit 1; }

SIGN_IDENTITY="$IDENTITY" ./build.sh

APP=build/Messy.app
# Stable name so https://github.com/berkboz/messy/releases/latest/download/Messy.dmg always works.
DMG="build/Messy.dmg"
codesign --verify --deep --strict "$APP"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# Notarize the app itself first and staple it, so it opens offline even after it leaves the DMG.
echo "Submitting the app for notarization…"
ditto -c -k --keepParent "$APP" "$STAGE/Messy.zip"
xcrun notarytool submit "$STAGE/Messy.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$STAGE/Messy.zip"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Messy" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "Submitting the DMG for notarization…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"

# Sparkle feed: one item, signed with the EdDSA key from the keychain.
SIGN_UPDATE=$(find .build/artifacts -path '*/bin/sign_update' -type f | head -1)
[ -n "$SIGN_UPDATE" ] || { echo "sign_update not found; run swift package resolve." >&2; exit 1; }
SIGNATURE=$("$SIGN_UPDATE" "$DMG")   # sparkle:edSignature="…" length="…"
notes_html() {
  [ -n "${NOTES:-}" ] && [ -f "$NOTES" ] || { echo "<p>Bug fixes and improvements.</p>"; return; }
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$NOTES" | awk '
    /^#/ { sub(/^#+ */, ""); print "<h3>" $0 "</h3>"; next }
    /^[-*] / { sub(/^[-*] /, ""); print "<li>" $0 "</li>"; next }
    NF { print "<p>" $0 "</p>" }'
}
cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Messy</title>
    <link>$FEED</link>
    <item>
      <title>Messy $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
$(notes_html)
      ]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Messy.dmg" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML

echo
echo "Ready: $DMG"
echo "Feed:   build/appcast.xml (build $BUILD)"
echo "Size:   $(du -h "$DMG" | cut -f1)"
echo "SHA256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"

if [ "${PUBLISH:-0}" = 1 ]; then
  command -v gh >/dev/null || { echo "Install the GitHub CLI (gh) to publish, or upload both files to a v$VERSION release by hand." >&2; exit 1; }
  read -r -p "Publish Messy $VERSION to github.com/$REPO? Every user with automatic updates gets it. [y/N] " ok || ok=""
  [ "$ok" = y ] || { echo "Not published."; exit 0; }
  NOTE_ARGS=(--generate-notes)
  [ -n "${NOTES:-}" ] && NOTE_ARGS=(--notes-file "$NOTES")
  gh release create "v$VERSION" "$DMG" build/appcast.xml -R "$REPO" --title "Messy $VERSION" "${NOTE_ARGS[@]}"
  echo "Published. Feed: $FEED"
else
  echo "To ship it: PUBLISH=1 ./release.sh, or attach Messy.dmg and appcast.xml to a v$VERSION release."
fi
