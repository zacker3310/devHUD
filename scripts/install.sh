#!/usr/bin/env bash
# Build a Release devHUD and put it in /Applications, where a login item can
# point at a path that survives the next `xcodebuild test`.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="/Applications"
CONFIGURATION="${CONFIGURATION:-Release}"
mkdir -p "$DEST"
xcodegen generate >/dev/null
xcodebuild -project devHUD.xcodeproj -scheme devHUD -configuration "$CONFIGURATION" \
  -derivedDataPath build/DerivedData build 2>&1 | grep -E "^/.*error:|BUILD (SUCCEEDED|FAILED)" | sort -u
pkill -x devHUD 2>/dev/null || true
sleep 1
rm -rf "$DEST/devHUD.app"
cp -R "build/DerivedData/Build/Products/$CONFIGURATION/devHUD.app" "$DEST/devHUD.app"
open "$DEST/devHUD.app"
echo "installed $DEST/devHUD.app and launched it. Turn on Launch at Login from the gear menu."
