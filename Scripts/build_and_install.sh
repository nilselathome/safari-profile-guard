#!/bin/bash
# Builds a Release build of SafariProfileGuard and installs it to /Applications,
# so it can be launched normally (Spotlight, Dock, Launchpad) without opening Xcode.
set -euo pipefail

cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen not found (brew install xcodegen)"; exit 1; }
xcodegen generate

DERIVED_DATA="$(mktemp -d)"
trap 'rm -rf "$DERIVED_DATA"' EXIT

xcodebuild -project SafariProfileGuard.xcodeproj \
  -scheme SafariProfileGuard \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/SafariProfileGuard.app"
DEST="/Applications/SafariProfileGuard.app"

# If it's running, quit it first so we can overwrite the bundle.
osascript -e 'quit app "SafariProfileGuard"' >/dev/null 2>&1 || true
sleep 0.5

rm -rf "$DEST"
cp -R "$BUILT_APP" "$DEST"

echo "Installed to $DEST"
open "$DEST"
