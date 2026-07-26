#!/usr/bin/env bash
# Cut a signed-only BootCaptain release. The shared engine bumps project.yml,
# this stub keeps BootCaptainCoreInfo and the build number in lockstep, commits,
# tags vX.Y.Z, and pushes only with --push. The tag triggers release.yml.
#
# Usage: scripts/release.sh [X.Y[.Z]] [--push]
# Shared engine: https://github.com/L-K-M/release-tool
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ "$(uname -s)" == "Darwin" ]] || { echo "error: releases must be cut on macOS" >&2; exit 2; }
scripts/generate-project.sh

# lkm-release's xcode adapter rewrites both project.yml and the generated
# project, but project.yml is the source of truth and BootCaptain.xcodeproj is
# intentionally ignored. Keep it out of the release commit while still letting
# the engine read/verify build settings from it.
trap 'rm -rf BootCaptain.xcodeproj' EXIT

export RELEASE_APP_NAME="BootCaptain"
export RELEASE_KIND="xcode"
export RELEASE_XCODE_PROJECT="BootCaptain.xcodeproj"
export RELEASE_XCODE_SCHEME="BootCaptain"
export RELEASE_XCODEGEN_YML="project.yml"
# shellcheck disable=SC2016
export RELEASE_POST_BUMP='scripts/sync-version.sh "$RELEASE_NEW_VERSION" --increment-build'
export RELEASE_CI_NOTE="CI will re-test <tag>, require Developer ID and notarization credentials, verify the app/helper signing identities, and publish checksummed DMG and ZIP artifacts."
export RELEASE_INVOKED_AS="scripts/release.sh"

BIN="${LKM_RELEASE_BIN:-lkm-release}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-release not found; clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
"$BIN" "$@"
