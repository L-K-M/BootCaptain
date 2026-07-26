#!/usr/bin/env bash
# Build and stage the macOS app. Release configuration is the default; --debug
# selects Debug. Local builds are ad-hoc signed and read-only unless
# SIGN_IDENTITY names a real signing identity. Privileged mutations remain
# disabled independently of signing.
#
# Usage: scripts/build.sh [--clean] [--debug] [--run] [--install] [--zip] [--dmg] [--check]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="Release"
CLEAN=false
RUN=false
INSTALL=false
ZIP=false
DMG=false
CHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) CLEAN=true ;;
    --debug) CONFIG="Debug" ;;
    --run) RUN=true ;;
    --install) INSTALL=true ;;
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
INSTALLED="/Applications/BootCaptain.app"
IDENTITY="${SIGN_IDENTITY:--}"

# A stable Apple identity keeps TCC grants and makes app/helper mutual
# authentication work. Prefer Apple Development for local installs, then
# Developer ID. A machine without either still gets a runnable read-only app.
if $INSTALL && [[ "$IDENTITY" == "-" ]] && command -v security >/dev/null 2>&1; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Apple Development/ {print $2; found=1; exit} END {if (!found) exit 1}' || true)"
  if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | awk '/Developer ID Application/ {print $2; exit}' || true)"
  fi
  [[ -n "$IDENTITY" ]] || IDENTITY="-"
fi

if $CHECK; then
  echo "configuration: $CONFIG"
  echo "version:       $VERSION"
  echo "identity:      $IDENTITY"
  echo "product:       $STAGED"
  $INSTALL && echo "install:       $INSTALLED"
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

scripts/sign-app.sh "$BUILT" "$IDENTITY"
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

if $INSTALL; then
  if [[ "$IDENTITY" == "-" ]]; then
    echo "warning: no Apple signing identity found; installing an ad-hoc signed read-only build" >&2
    echo "warning: TCC grants will not persist across rebuilds and helper authentication is unavailable" >&2
  fi
  osascript -e 'tell application "BootCaptain" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x BootCaptain >/dev/null 2>&1 || break
    sleep 0.25
  done
  if pgrep -x BootCaptain >/dev/null 2>&1; then
    echo "error: BootCaptain is still running; quit it before installing" >&2
    exit 1
  fi
  rm -rf "$INSTALLED"
  ditto "$STAGED" "$INSTALLED"
  codesign --verify --strict --verbose=2 "$INSTALLED"
  echo "installed: $INSTALLED"
fi

if $RUN; then
  if $INSTALL; then
    open "$INSTALLED"
  else
    open "$STAGED"
  fi
elif $INSTALL; then
  open -R "$INSTALLED"
else
  open -R "$STAGED"
fi
