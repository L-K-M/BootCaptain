#!/usr/bin/env bash
# Build and stage the macOS app. Release configuration is the default; --debug
# selects Debug. Local builds are ad-hoc signed and read-only unless
# SIGN_IDENTITY names a real signing identity. Privileged mutations remain
# disabled independently of signing.
#
# Usage: scripts/build.sh [--clean] [--debug] [--run] [--zip] [--dmg] [--check]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="Release"
CLEAN=false
RUN=false
ZIP=false
DMG=false
CHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) CLEAN=true ;;
    --debug) CONFIG="Debug" ;;
    --run) RUN=true ;;
    --zip) ZIP=true ;;
    --dmg) DMG=true ;;
    --check) CHECK=true ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail/{ /^#/s/^# \{0,1\}//p; }' "$0"
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' project.yml | head -n 1)"
DERIVED="$ROOT/build/DerivedData"
BUILT="$DERIVED/Build/Products/$CONFIG/BootCaptain.app"
STAGED="$ROOT/dist/BootCaptain.app"

if $CHECK; then
  echo "configuration: $CONFIG"
  echo "version:       $VERSION"
  echo "identity:      ${SIGN_IDENTITY:--}"
  echo "product:       $STAGED"
  exit 0
fi

[[ "$(uname -s)" == "Darwin" ]] || { echo "error: BootCaptain.app requires macOS" >&2; exit 2; }

if $CLEAN; then
  rm -rf "$DERIVED" "$ROOT/dist"
fi

scripts/generate-project.sh
xcodebuild build \
  -project BootCaptain.xcodeproj \
  -scheme BootCaptain \
  -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO

scripts/sign-app.sh "$BUILT" "${SIGN_IDENTITY:--}"
mkdir -p "$ROOT/dist"
rm -rf "$STAGED"
ditto "$BUILT" "$STAGED"

if $ZIP; then
  ditto -c -k --keepParent "$STAGED" "$ROOT/dist/BootCaptain-$VERSION.zip"
fi
if $DMG; then
  rm -f "$ROOT/dist/BootCaptain-$VERSION.dmg"
  hdiutil create -volname "BootCaptain $VERSION" -srcfolder "$STAGED" \
    -ov -format UDZO "$ROOT/dist/BootCaptain-$VERSION.dmg"
fi
if $RUN; then
  open "$STAGED"
else
  open -R "$STAGED"
fi
