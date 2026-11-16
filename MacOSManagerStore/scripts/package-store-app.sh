#!/bin/bash
# Build an unsigned Mac App Store edition .app and zip it.
# This script refuses to invent an app on any other operating system.
# It does not sign, notarize, or submit to App Store Connect.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"

if [[ "$HOST_OS" != "Darwin" ]]; then
  echo "BLOCKER: this host is ${HOST_OS} ${HOST_ARCH}."
  echo "A macOS .app was not created. swift test on Linux does not prove the SwiftUI app."
  echo "Notarization and App Store submission are not part of this script."
  exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "BLOCKER: Darwin host has no xcodebuild."
  exit 2
fi

if [[ "${MACOS_MANAGER_SKIP_UNIT_TEST:-}" == "1" ]]; then
  echo "Skipping swift test because it already ran in this job."
else
  swift test
fi

DERIVED="$ROOT/build/DerivedData"
PRODUCT_DIR="$ROOT/build/product"
rm -rf "$PRODUCT_DIR"
mkdir -p "$PRODUCT_DIR"

xcodebuild \
  -project "$ROOT/MacOSManagerStore.xcodeproj" \
  -scheme MacOSManagerStore \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS="x86_64 arm64" \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=14.0 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP=""
while IFS= read -r candidate; do
  if [[ -n "$candidate" ]]; then
    APP="$candidate"
    break
  fi
done <<EOFIND
$(find "$DERIVED/Build/Products" -type d -name 'MacOSManagerStore.app')
EOFIND
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "BLOCKER: xcodebuild finished without producing MacOSManagerStore.app."
  exit 3
fi

BINARY="$APP/Contents/MacOS/MacOSManagerStore"
if [[ ! -f "$BINARY" ]]; then
  echo "BLOCKER: $APP has no Contents/MacOS/MacOSManagerStore executable."
  exit 3
fi

echo "Product: $APP"
file "$BINARY"
if ! command -v lipo >/dev/null 2>&1; then
  echo "BLOCKER: lipo is required to confirm the universal binary."
  exit 3
fi
LIPO_INFO="$(lipo -info "$BINARY")"
echo "$LIPO_INFO"
if [[ "$LIPO_INFO" != *"x86_64"* || "$LIPO_INFO" != *"arm64"* ]]; then
  echo "BLOCKER: the app executable must contain both x86_64 and arm64 slices."
  exit 3
fi
if command -v vtool >/dev/null 2>&1; then
  VTOOL=(vtool)
elif xcrun --find vtool >/dev/null 2>&1; then
  VTOOL=(xcrun vtool)
else
  echo "BLOCKER: vtool is required to confirm the minimum system version."
  exit 3
fi
BUILD_INFO="$("${VTOOL[@]}" -show-build "$BINARY")"
echo "$BUILD_INFO"
if ! grep -q "minos 14.0" <<<"$BUILD_INFO"; then
  echo "BLOCKER: expected LC_BUILD_VERSION minos 14.0."
  exit 3
fi
OTHER_MINOS="$(grep "minos" <<<"$BUILD_INFO" | grep -v "minos 14.0" || true)"
if [[ -n "$OTHER_MINOS" ]]; then
  echo "BLOCKER: unexpected minimum system version:"
  echo "$OTHER_MINOS"
  exit 3
fi
otool -l "$BINARY" | awk '/LC_BUILD_VERSION/,/minos/' || true
plutil -p "$APP/Contents/Info.plist" | awk '/CFBundleShortVersionString|CFBundleVersion|LSMinimumSystemVersion|CFBundleIdentifier/'
echo "Privacy manifest:"
if [[ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ]]; then
  plutil -p "$APP/Contents/Resources/PrivacyInfo.xcprivacy" || true
else
  echo "BLOCKER: PrivacyInfo.xcprivacy was not copied into the app bundle."
  exit 3
fi
echo "Entitlements requested in the project include App Sandbox. This unsigned CI build is not a signed App Store archive."
echo "Codesign:"
SIGN_STATUS="$(codesign -dv --verbose=4 "$APP" 2>&1 || true)"
echo "$SIGN_STATUS"
if grep -q "Authority=" <<<"$SIGN_STATUS"; then
  echo "BLOCKER: this build attached a signing authority. The App Store edition CI artifact must stay unsigned."
  exit 4
fi
if ! grep -q "not signed at all" <<<"$SIGN_STATUS"; then
  echo "BLOCKER: expected codesign to report that the app is not signed at all."
  exit 4
fi
echo "Confirmed the app is unsigned. Signing and App Store submission wait for Apple Developer account activation. No Developer ID or distribution certificate is used here."

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ZIP="$PRODUCT_DIR/MacOSManagerStore-unsigned-${STAMP}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "ZIP: $ZIP"
echo "This zip is not for sale and is not an App Store submission."
