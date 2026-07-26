#!/usr/bin/env bash
# Sign BootCaptain's nested code inside-out, then verify the sealed bundle.
# An ad-hoc identity (the default "-") makes a local read-only build runnable,
# but the privileged helper intentionally rejects it because it has no Team ID.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-}"
IDENTITY="${2:--}"

[[ -n "$APP" && -d "$APP" ]] || {
  echo "usage: scripts/sign-app.sh /path/to/BootCaptain.app [identity]" >&2
  exit 2
}

HELPER="$APP/Contents/MacOS/ch.lkmc.bootcaptain.helper"
DAEMON_PLIST="$APP/Contents/Library/LaunchDaemons/ch.lkmc.bootcaptain.helper.plist"
[[ -f "$HELPER" ]] || { echo "error: bundle is missing helper: $HELPER" >&2; exit 1; }
[[ -f "$DAEMON_PLIST" ]] || { echo "error: bundle is missing launchd plist: $DAEMON_PLIST" >&2; exit 1; }

declare -a COMMON=(--force --options runtime --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  COMMON+=(--timestamp)
fi

# Sign any nested dynamic code before the helper and outer app. Swift package
# products are currently static, but keeping this order makes additions safe.
while IFS= read -r nested; do
  codesign "${COMMON[@]}" "$nested"
done < <(find "$APP/Contents" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) -print)

codesign "${COMMON[@]}" --entitlements "$ROOT/Helper/Helper.entitlements" "$HELPER"
codesign "${COMMON[@]}" --entitlements "$ROOT/App/BootCaptain.entitlements" "$APP"

codesign --verify --strict --verbose=2 "$HELPER"
codesign --verify --strict --verbose=2 "$APP"

if [[ "$IDENTITY" != "-" ]]; then
  APP_TEAM="$(codesign --display --verbose=4 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  HELPER_TEAM="$(codesign --display --verbose=4 "$HELPER" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  [[ -n "$APP_TEAM" && "$APP_TEAM" == "$HELPER_TEAM" ]] || {
    echo "error: app and helper do not have the same non-empty Team ID" >&2
    exit 1
  }
  if [[ -n "${APPLE_TEAM_ID:-}" && "$APP_TEAM" != "$APPLE_TEAM_ID" ]]; then
    echo "error: signed Team ID $APP_TEAM does not match expected $APPLE_TEAM_ID" >&2
    exit 1
  fi

  APP_REQUIREMENT="$(codesign --display --requirements :- "$APP" 2>&1)"
  HELPER_REQUIREMENT="$(codesign --display --requirements :- "$HELPER" 2>&1)"
  [[ "$APP_REQUIREMENT" == *'identifier "ch.lkmc.bootcaptain"'* ]] || {
    echo "error: app designated requirement has an unexpected identifier" >&2
    exit 1
  }
  [[ "$HELPER_REQUIREMENT" == *'identifier "ch.lkmc.bootcaptain.helper"'* ]] || {
    echo "error: helper designated requirement has an unexpected identifier" >&2
    exit 1
  }
fi
