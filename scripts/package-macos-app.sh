#!/bin/bash
# Build an unsigned macOS .app and zip it.
# This script refuses to invent an app on any other operating system.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"

if [[ "$HOST_OS" != "Darwin" ]]; then
  echo "BLOCKER: this host is ${HOST_OS} ${HOST_ARCH}."
  echo "A macOS .app was not created. swift test on Linux does not prove the SwiftUI app."
  if command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild: $(command -v xcodebuild)"
  else
    echo "xcodebuild: absent"
  fi
  if command -v swift >/dev/null 2>&1; then
    echo "swift: $(command -v swift)"
  else
    echo "swift: absent"
  fi
  echo "Unmet requirement: a Mac that is allowed to run macOS, with Xcode, to execute this script."
  echo "Notarization is not part of this script. No Apple ID or Developer ID is used."
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

# x86_64 is required for the 2018 Intel Mac mini. arm64 is included so the same app can also launch on Apple silicon.
xcodebuild \
  -project "$ROOT/MacOSManager.xcodeproj" \
  -scheme MacOSManager \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS="x86_64 arm64" \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=14.0 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

# BSD find on macOS has no -quit. Collect matches, then take the first.
APP=""
while IFS= read -r candidate; do
  if [[ -n "$candidate" ]]; then
    APP="$candidate"
    break
  fi
done <<EOF
$(find "$DERIVED/Build/Products" -type d -name 'MacOSManager.app')
EOF
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "BLOCKER: xcodebuild finished without producing MacOSManager.app."
  exit 3
fi

BINARY="$APP/Contents/MacOS/MacOSManager"
if [[ ! -f "$BINARY" ]]; then
  echo "BLOCKER: $APP has no Contents/MacOS/MacOSManager executable."
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
# LC_BUILD_VERSION / minos. otool is present with Xcode.
otool -l "$BINARY" | awk '/LC_BUILD_VERSION/,/minos/' || true
plutil -p "$APP/Contents/Info.plist" | awk '/CFBundleShortVersionString|CFBundleVersion|LSMinimumSystemVersion|CFBundleIdentifier/'
echo "Codesign:"
codesign -dv --verbose=4 "$APP" 2>&1 || true
echo "Notarization: not attempted. No Apple ID and no notarytool credentials are used."

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ZIP="$PRODUCT_DIR/MacOSManager-unsigned-${STAMP}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "ZIP: $ZIP"

# The package only copies the app into /Applications. It has no scripts, so it does not
# format a disk, run createinstallmedia, or start installing macOS.
STAGE="$PRODUCT_DIR/pkg-root"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MacOSManager.app"
COMPONENT="$PRODUCT_DIR/components.plist"
cat > "$COMPONENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>RootRelativeBundlePath</key>
    <string>MacOSManager.app</string>
    <key>BundleHasStrictIdentifier</key>
    <true/>
    <key>BundleIsRelocatable</key>
    <false/>
    <key>BundleIsVersionChecked</key>
    <true/>
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
  </dict>
</array>
</plist>
PLIST
PKG="$PRODUCT_DIR/MacOSManager-unsigned-${STAMP}.pkg"
pkgbuild \
  --root "$STAGE" \
  --install-location /Applications \
  --identifier local.review.MacOSManager.pkg \
  --version 0.1.0 \
  --component-plist "$COMPONENT" \
  "$PKG"
echo "PKG: $PKG"
echo "Unsigned and not notarized. No Developer ID was used."
echo "Gatekeeper behavior for this package has not been tested. Do not disable Gatekeeper or strip quarantine as a substitute for that test."
echo "This package is not a VoiceOver test, a USB write, or a macOS installation."
