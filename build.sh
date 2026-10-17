#!/bin/bash
# Builds build/Temiz.app. Signs with your Developer ID if one is in the keychain, otherwise ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary: build each architecture, then merge.
# Both triples write to the same products folder, so copy each binary out right away.
mkdir -p build/arch
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx14.0"
  cp "$(swift build -c release --triple "$arch-apple-macosx14.0" --show-bin-path)/Temiz" "build/arch/Temiz-$arch"
done

APP=build/Temiz.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create build/arch/Temiz-arm64 build/arch/Temiz-x86_64 -output "$APP/Contents/MacOS/Temiz"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Mascot/*.png "$APP/Contents/Resources/"
cp Resources/Sounds/*.wav "$APP/Contents/Resources/"

TEAM_ID="${TEAM_ID:-JMAQX8DJ8J}"
IDENTITY="${SIGN_IDENTITY-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' -v t="($TEAM_ID)" '/Developer ID Application/ && index($2, t) {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --entitlements Resources/Temiz.entitlements --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --entitlements Resources/Temiz.entitlements --sign - "$APP"
  echo "Signed ad-hoc (no Developer ID found)"
fi
echo "Built $APP"
