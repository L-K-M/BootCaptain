#!/usr/bin/env bash
# Keep project.yml and the portable Swift version constant in lockstep. App and
# helper plists consume the Xcode build settings and therefore need no rewrite.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
MODE="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
  echo "usage: scripts/sync-version.sh X.Y[.Z] [--increment-build]" >&2
  exit 2
}
[[ -z "$MODE" || "$MODE" == "--increment-build" ]] || {
  echo "error: unknown argument: $MODE" >&2
  exit 2
}

CURRENT_BUILD="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*$/\1/p' project.yml | head -n 1)"
[[ -n "$CURRENT_BUILD" ]] || { echo "error: could not read CURRENT_PROJECT_VERSION" >&2; exit 1; }
BUILD="$CURRENT_BUILD"
[[ "$MODE" == "--increment-build" ]] && BUILD=$((CURRENT_BUILD + 1))

VERSION="$VERSION" BUILD="$BUILD" perl -pi -e '
  s/(MARKETING_VERSION:\s*)"?[^"\s]+"?/$1"$ENV{VERSION}"/;
  s/(CURRENT_PROJECT_VERSION:\s*)"?[0-9]+"?/$1"$ENV{BUILD}"/;
' project.yml
VERSION="$VERSION" perl -pi -e 's/(public static let version = ")[^"]+(")/$1$ENV{VERSION}$2/' Sources/BootCaptainCore/Info.swift

PROJECT_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' project.yml | head -n 1)"
SWIFT_VERSION="$(sed -nE 's/.*version = "([^"]+)".*/\1/p' Sources/BootCaptainCore/Info.swift | head -n 1)"
[[ "$PROJECT_VERSION" == "$VERSION" && "$SWIFT_VERSION" == "$VERSION" ]] || {
  echo "error: version synchronization failed (project=$PROJECT_VERSION swift=$SWIFT_VERSION)" >&2
  exit 1
}

echo "BootCaptain $VERSION (build $BUILD)"
