#!/usr/bin/env bash
# Build, sign, notarize, package and tag a devHUD release.
#
#   scripts/release.sh 0.3.1
#
# Signing: set DEVHUD_SIGN_IDENTITY to a "Developer ID Application: ..."
# identity present in the keychain. Without it the build is ad-hoc signed and
# the script refuses to tag, because Gatekeeper will block it on other Macs.
# Notarization: store credentials once with
#   xcrun notarytool store-credentials devhud-notary --apple-id <id> --team-id E97LU2X2VL --password <app-specific>
# or the App Store Connect API key variant. Without the profile, packaging
# stops before tagging for the same reason.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
TEAM="${DEVHUD_TEAM_ID:-E97LU2X2VL}"
IDENTITY="${DEVHUD_SIGN_IDENTITY:-}"
PROFILE="${DEVHUD_NOTARY_PROFILE:-devhud-notary}"
DIST="dist"
APP="build/DerivedData/Build/Products/Release/devHUD.app"
ZIP="$DIST/devHUD-$VERSION.zip"

# 1. Version stamps come from project.yml; the build number is the commit count.
BUILD_NUMBER="$(git rev-list --count HEAD)"
sed -i '' -E "s/MARKETING_VERSION: \"[^\"]+\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \"[^\"]+\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml
xcodegen generate >/dev/null

# 2. Tests first. A release that skips them is a guess.
TEST_LOG="$(mktemp)"
xcodebuild -project devHUD.xcodeproj -scheme devHUD -configuration Debug -derivedDataPath build/DerivedData test > "$TEST_LOG" 2>&1 || true
grep -E "^/.*error:|Test Case .* failed|Executed [0-9]+ tests, with|TEST (SUCCEEDED|FAILED)" "$TEST_LOG" | grep -v SourcePackages | sort -u | tail -3
grep -q "TEST SUCCEEDED" "$TEST_LOG"

# 3. Release build. Hardened runtime and a timestamp are what notarization wants.
if [ -n "$IDENTITY" ]; then
  xcodebuild -project devHUD.xcodeproj -scheme devHUD -configuration Release -derivedDataPath build/DerivedData build \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" 2>&1 \
    | grep -E "^/.*error:|BUILD (SUCCEEDED|FAILED)" | sort -u
  codesign --verify --deep --strict --verbose=2 "$APP"
  SIGNED=1
else
  echo "WARNING: DEVHUD_SIGN_IDENTITY unset; building ad-hoc. Not shippable." >&2
  xcodebuild -project devHUD.xcodeproj -scheme devHUD -configuration Release -derivedDataPath build/DerivedData build 2>&1 \
    | grep -E "^/.*error:|BUILD (SUCCEEDED|FAILED)" | sort -u
  SIGNED=0
fi

# 4. Package. ditto keeps the bundle's resource forks and permissions intact.
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 5. Notarize and staple, then re-zip the stapled bundle.
NOTARIZED=0
if [ "$SIGNED" = 1 ] && xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose=2 "$APP"
  NOTARIZED=1
else
  echo "WARNING: not notarized (no signing identity or no '$PROFILE' keychain profile)." >&2
fi

SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "$SHA  $(basename "$ZIP")" > "$ZIP.sha256"

# 6. Cask with the new version and checksum.
sed -i '' -E "s/version \"[^\"]+\"/version \"$VERSION\"/; s/sha256 \"[^\"]+\"/sha256 \"$SHA\"/" packaging/homebrew/Casks/devhud.rb

echo
echo "built   $ZIP"
echo "sha256  $SHA"
echo "signed=$SIGNED notarized=$NOTARIZED"

# 7. Tag only a shippable build from a clean tree.
if [ "$NOTARIZED" != 1 ]; then
  echo "Not tagging: a release other Macs can open needs Developer ID signing and notarization." >&2
  exit 2
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Not tagging: commit the version bump and cask first." >&2
  exit 2
fi
git tag -a "v$VERSION" -m "devHUD $VERSION"
echo "tagged v$VERSION. Next: push main and the tag, then publish the GitHub release"
echo "with the two files in dist/ (the deploy gate requires RELEASE_AUTHORIZED to be set by a human)."
