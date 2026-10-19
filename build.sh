#!/bin/bash
# Builds build/Messy.app. Signs with your Developer ID if one is in the keychain, otherwise ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary: build each architecture, then merge.
# Both triples write to the same products folder, so copy each binary out right away.
mkdir -p build/arch
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx14.0"
  BIN="$(swift build -c release --triple "$arch-apple-macosx14.0" --show-bin-path)"
  cp "$BIN/Messy" "build/arch/Messy-$arch"
done

APP=build/Messy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create build/arch/Messy-arm64 build/arch/Messy-x86_64 -output "$APP/Contents/MacOS/Messy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Mascot/*.png "$APP/Contents/Resources/"
cp Resources/Sounds/*.wav "$APP/Contents/Resources/"
# Sparkle ships one universal framework; the executable finds it through @executable_path/../Frameworks.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

# Sign inside out: Sparkle's helpers, the framework, then the app.
sign() {
  for item in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --preserve-metadata=entitlements "$@" "$item"
  done
  codesign --force "$@" --entitlements Resources/Messy.entitlements "$APP"
}

TEAM_ID="${TEAM_ID:-JMAQX8DJ8J}"
IDENTITY="${SIGN_IDENTITY-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' -v t="($TEAM_ID)" '/Developer ID Application/ && index($2, t) {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
  sign --options runtime --timestamp --sign "$IDENTITY"
  echo "Signed with: $IDENTITY"
else
  sign --sign -
  echo "Signed ad-hoc (no Developer ID found)"
fi
echo "Built $APP"
