#!/usr/bin/env bash
# Builds a universal Release copy of MarkdownPeek and packages it as
# dist/MarkdownPeek-<version>.dmg (app + a shortcut to /Applications).
#
# Signing:
#   default        Ad-hoc ("Sign to Run Locally"). No team ID or name ends up in
#                  the download. macOS asks users to allow the app once.
#   DEVELOPER_ID   Set to your "Developer ID Application: Name (TEAMID)" identity
#                  (paid Apple Developer Program) to sign for distribution.
#   NOTARY_PROFILE With DEVELOPER_ID: a `xcrun notarytool store-credentials`
#                  profile name, to notarize and staple the DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED=build/dmg
APP="$DERIVED/Build/Products/Release/MarkdownPeek.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ -n "${DEVELOPER_ID:-}" ]; then
  TEAM=$(sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p' <<< "$DEVELOPER_ID")
  SIGNING=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM" OTHER_CODE_SIGN_FLAGS=--timestamp)
  echo "==> Signing with $DEVELOPER_ID"
else
  # Overrides Config/Local.xcconfig so a personal team never ships in the DMG.
  SIGNING=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
  echo "==> Ad-hoc signing (set DEVELOPER_ID for a notarizable build)"
fi

echo "==> Building universal Release"
rm -rf "$DERIVED/Build/Products/Release"
xcodebuild -project MarkdownPeek.xcodeproj -scheme MarkdownPeek -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  "${SIGNING[@]}" build -quiet
# Xcode registers build products with LaunchServices; don't let this copy
# compete with the one users install.
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/MarkdownPeek-$VERSION.dmg"

echo "==> Drawing installer background"
ASSETS=build/dmg-assets
swift scripts/dmg/make-background.swift "$ASSETS" >/dev/null
# One TIFF holding both resolutions, so Finder picks the sharp one on Retina.
tiffutil -cathidpicheck "$ASSETS/background.png" "$ASSETS/background@2x.png" \
  -out "$ASSETS/background.tiff" 2>/dev/null

# dmgbuild writes Finder's window layout (.DS_Store) directly, so this works
# without scripting Finder and in CI. Installed into a private venv under build/.
# 1.6.7+ is required for background images on macOS 26.2+ (dmgbuild#273), and
# needs Python 3.10+; macOS's own /usr/bin/python3 is 3.9.
DMGBUILD_VERSION=1.6.7
DMGBUILD_VENV="build/dmgbuild-$DMGBUILD_VERSION"
if [ ! -x "$DMGBUILD_VENV/bin/dmgbuild" ]; then
  PYTHON=""
  for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3 \
                   /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if command -v "$candidate" >/dev/null 2>&1 &&
       "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
      PYTHON=$(command -v "$candidate"); break
    fi
  done
  [ -n "$PYTHON" ] || { echo "Python 3.10+ is required to build the DMG: brew install python"; exit 1; }
  echo "==> Installing dmgbuild $DMGBUILD_VERSION into $DMGBUILD_VENV (using $PYTHON)"
  "$PYTHON" -m venv "$DMGBUILD_VENV"
  "$DMGBUILD_VENV/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==$DMGBUILD_VERSION"
fi

echo "==> Packaging $DMG"
mkdir -p dist
rm -f "$DMG"
"$DMGBUILD_VENV/bin/dmgbuild" -s scripts/dmg/settings.py \
  -D app="$APP" -D background="$ASSETS/background.tiff" \
  "MarkdownPeek" "$DMG" >/dev/null

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
lipo -archs "$APP/Contents/MacOS/MarkdownPeek" | sed 's/^/    architectures: /'
codesign -dv "$APP" 2>&1 | grep -E '^(Signature|TeamIdentifier)=' | sed 's/^/    /'
