#!/usr/bin/env bash
# The macOS CI gate: regenerate, lint, test, build the app/helper, and verify the
# exact bundle layout. Run this locally before pushing any macOS-facing change.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: BootCaptain app verification requires macOS and Xcode" >&2
  exit 2
fi

scripts/generate-project.sh

# Regenerated PNG bytes are not reproducible across platforms/Pillow builds, so
# a byte-exact diff of the icons produces false failures. Assert the asset
# catalog is structurally intact instead: the manifest is unchanged (JSON is
# reproducible) and every expected icon exists as a non-empty PNG. The build
# uses the freshly regenerated icons regardless.
git diff --exit-code -- App/Assets.xcassets/AppIcon.appiconset/Contents.json
for icon in App/Assets.xcassets/AppIcon.appiconset/icon_*.png; do
  [[ -s "$icon" ]] || { echo "error: missing or empty icon: $icon" >&2; exit 1; }
  file "$icon" | grep -q 'PNG image data' || { echo "error: not a PNG: $icon" >&2; exit 1; }
done

plutil -lint \
  App/Info.plist \
  App/BootCaptain.entitlements \
  Helper/Helper-Info.plist \
  Helper/Helper.entitlements \
  Helper/ch.lkmc.bootcaptain.helper.plist

swift test

DERIVED="$ROOT/build/DerivedData"
xcodebuild build \
  -project BootCaptain.xcodeproj \
  -scheme BootCaptain \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO

APP="$DERIVED/Build/Products/Debug/BootCaptain.app"
for path in \
  "$APP/Contents/MacOS/BootCaptain" \
  "$APP/Contents/MacOS/ch.lkmc.bootcaptain.helper" \
  "$APP/Contents/Info.plist" \
  "$APP/Contents/Library/LaunchDaemons/ch.lkmc.bootcaptain.helper.plist"; do
  [[ -f "$path" ]] || { echo "error: built bundle is missing $path" >&2; exit 1; }
done

EXPECTED_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' project.yml | head -n 1)"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$EXPECTED_VERSION" ]] || {
  echo "error: built app version $BUILT_VERSION does not match project.yml $EXPECTED_VERSION" >&2
  exit 1
}

scripts/sign-app.sh "$APP" -
