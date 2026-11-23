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

mkdir -p "$BUILD_DIR"
BUILD_DIR="$(mktemp -d "$BUILD_DIR/$VERSION.XXXXXX")"

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

IDENTITY="Developer ID Application: Rolling Rabbits Sh.p.k (Q4FVJUH2ZJ)"
codesign --force --timestamp --options runtime --sign "$IDENTITY" \
  --entitlements "$PROJECT_DIR/FolioQuickLook/FolioQuickLook.entitlements" \
  "$APP_STAGED/Contents/PlugIns/FolioQuickLook.appex"
codesign --force --timestamp --options runtime --sign "$IDENTITY" \
  --entitlements "$PROJECT_DIR/Folio/Folio.entitlements" "$APP_STAGED"
codesign --verify --deep --strict "$APP_STAGED"

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

codesign --timestamp --sign "$IDENTITY" "$DMG_PATH"
codesign --verify "$DMG_PATH"
echo "Built: $DMG_PATH"

if [[ "${2:-}" == "--publish" ]]; then
  if [[ -n "${FOLIO_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$FOLIO_NOTARY_PROFILE" --wait
  else
    command -v asc >/dev/null || {
      echo "Set FOLIO_NOTARY_PROFILE or configure asc authentication for notarization." >&2
      exit 1
    }
    asc notarization submit --file "$DMG_PATH" --wait
  fi
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  gh release create "$VERSION" "$DMG_PATH" --title "$VERSION" --notes "Release $VERSION" --latest
fi
