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
if command -v lipo >/dev/null 2>&1; then
  lipo -info "$BINARY" || true
fi
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "$BINARY" || true
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
codesign -dv --verbose=4 "$APP" 2>&1 || true
echo "Signing and App Store submission wait for Apple Developer account activation. No Developer ID or distribution certificate is used here."

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ZIP="$PRODUCT_DIR/MacOSManagerStore-unsigned-${STAMP}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "ZIP: $ZIP"
echo "This zip is not for sale and is not an App Store submission."
