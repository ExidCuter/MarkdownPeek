#!/usr/bin/env bash
# Builds MarkdownPeek (Release), installs it to ~/Applications and registers
# its Quick Look extensions. Re-run after any code change.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${DEST:-$HOME/Applications}"
APP_NAME=MarkdownPeek.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

cd "$ROOT"
# Signing: use Config/Local.xcconfig if present, otherwise create it from the
# first "Apple Development" certificate (override with TEAM_ID=XXXXXXXXXX).
LOCAL_XCCONFIG=Config/Local.xcconfig
if [ ! -f "$LOCAL_XCCONFIG" ]; then
  TEAM_ID="${TEAM_ID:-$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p')}"
  if [ -n "$TEAM_ID" ]; then
    printf 'CODE_SIGN_IDENTITY = Apple Development\nDEVELOPMENT_TEAM = %s\n' "$TEAM_ID" > "$LOCAL_XCCONFIG"
    echo "==> Signing with Apple Development, team $TEAM_ID (saved to $LOCAL_XCCONFIG)"
  else
    echo "==> No Apple Development certificate found: building ad-hoc signed."
    echo "    If Quick Look ignores the extensions, see Config/Local.xcconfig.example."
  fi
fi

echo "==> Building (Release)"
xcodebuild -project MarkdownPeek.xcodeproj -scheme MarkdownPeek -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build -quiet

BUILT="build/DerivedData/Build/Products/Release/$APP_NAME"
[ -d "$BUILT" ] || { echo "Build product not found at $BUILT"; exit 1; }

echo "==> Installing to $DEST"
mkdir -p "$DEST"
# Unregister any stale copy (e.g. a Debug build) so Quick Look picks this one.
for old in "$DEST/$APP_NAME" build/DerivedData/Build/Products/Debug/$APP_NAME; do
  [ -d "$old" ] && "$LSREGISTER" -u "$old" >/dev/null 2>&1 || true
done
rm -rf "$DEST/$APP_NAME"
ditto "$BUILT" "$DEST/$APP_NAME"

echo "==> Registering extensions"
# Build products also get registered by LaunchServices; drop them so Quick Look
# always runs the installed copy.
for built in build/DerivedData/Build/Products/*/$APP_NAME; do
  [ -d "$built" ] && "$LSREGISTER" -u "$built" >/dev/null 2>&1 || true
done
"$LSREGISTER" -f -R -trusted "$DEST/$APP_NAME"
pluginkit -a "$DEST/$APP_NAME/Contents/PlugIns/MarkdownPreview.appex"
pluginkit -a "$DEST/$APP_NAME/Contents/PlugIns/MarkdownThumbnail.appex"
pluginkit -e use -i com.markdownpeek.MarkdownPeek.Preview || true
pluginkit -e use -i com.markdownpeek.MarkdownPeek.Thumbnail || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "==> Registered extensions"
pluginkit -m -v -i com.markdownpeek.MarkdownPeek.Preview || true
pluginkit -m -v -i com.markdownpeek.MarkdownPeek.Thumbnail || true

echo
echo "Done. Select a .md file in Finder and press Space."
echo "If Finder still shows plain text: System Settings > General > Login Items & Extensions > Quick Look > enable MarkdownPeek, then relaunch Finder (Option-right-click Finder in Dock > Relaunch)."
