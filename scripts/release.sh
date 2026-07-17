#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 vX.Y.Z" >&2
  exit 1
fi

[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Version must look like vX.Y.Z (e.g. v0.1.0)" >&2
  exit 1
}
MARKETING_VERSION="${VERSION#v}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
APP_NAME="Folio"

command -v create-dmg >/dev/null || {
  echo "create-dmg not found. Install with: brew install create-dmg" >&2
  exit 1
}
command -v xcodegen >/dev/null || {
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
}

cd "$PROJECT_DIR"
xcodegen generate

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT_DIR/${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$MARKETING_VERSION" \
  archive

APP_SRC="$BUILD_DIR/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"
STAGED_DIR="$BUILD_DIR/staged"
APP_STAGED="$STAGED_DIR/${APP_NAME}.app"
mkdir -p "$STAGED_DIR"
cp -R "$APP_SRC" "$APP_STAGED"

# Ad-hoc sign so macOS has a consistent code signature. Does NOT bypass Gatekeeper
# (that needs a paid Apple Developer ID + notarization); it just gives the bundle a signature.
# Sign inside-out with explicit --entitlements per bundle: `--deep` alone re-signs nested
# bundles but without entitlements, which drops FolioQuickLook's sandbox entitlement and
# makes PlugInKit reject it ("plug-ins must be sandboxed"), silently breaking Quick Look.
codesign --force --sign - \
  --entitlements "$PROJECT_DIR/FolioQuickLook/FolioQuickLook.entitlements" \
  "$APP_STAGED/Contents/PlugIns/FolioQuickLook.appex"
codesign --force --sign - \
  --entitlements "$PROJECT_DIR/Folio/Folio.entitlements" \
  "$APP_STAGED"

DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"
create-dmg \
  --volname "$APP_NAME" \
  --window-size 540 380 \
  --icon-size 96 \
  --icon "${APP_NAME}.app" 140 180 \
  --app-drop-link 400 180 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$STAGED_DIR"

echo "Built: $DMG_PATH"

gh release create "$VERSION" \
  "$DMG_PATH" \
  --title "$VERSION" \
  --notes "Release $VERSION" \
  --latest
