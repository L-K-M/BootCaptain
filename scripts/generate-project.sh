#!/usr/bin/env bash
# Regenerate icons and the disposable Xcode project from tracked sources.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: Xcode project generation requires macOS" >&2
  exit 2
fi
command -v xcodegen >/dev/null 2>&1 || {
  echo "error: XcodeGen is required; install it with: brew install xcodegen" >&2
  exit 1
}
python3 -c 'import PIL' >/dev/null 2>&1 || {
  echo "error: Pillow is required; install it with: python3 -m pip install -r requirements-icons.txt" >&2
  exit 1
}

python3 scripts/make-icons.py
xcodegen generate --spec project.yml --project .
