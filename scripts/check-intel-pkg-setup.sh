#!/bin/bash
# Static checks for the 2018 Intel Mac mini target and the unsigned package plan.
# This does not build an app or a package.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$ROOT/MacOSManager.xcodeproj/project.pbxproj"
WF="$ROOT/.github/workflows/macos-build.yml"
PKG="$ROOT/scripts/package-macos-app.sh"
fail() { echo "FAIL: $1"; exit 1; }

grep -q 'ARCHS = "x86_64 arm64";' "$PBX" || fail "project is missing a universal x86_64 arm64 target"
grep -q 'ONLY_ACTIVE_ARCH = NO;' "$PBX" || fail "active-arch-only would drop Intel when built on Apple silicon"
if grep -q 'ONLY_ACTIVE_ARCH = YES;' "$PBX"; then
  fail "a Debug setting still builds only the active architecture"
fi
grep -q 'MACOSX_DEPLOYMENT_TARGET = 14.0;' "$PBX" || fail "deployment target is not macOS 14"
grep -q 'LSMinimumSystemVersion' "$ROOT/MacOSManagerApp/Info.plist" || fail "Info.plist has no minimum system version"
grep -q '<string>14.0</string>' "$ROOT/MacOSManagerApp/Info.plist" || fail "Info.plist minimum is not 14.0"
grep -q 'runs-on: macos-15-intel' "$WF" || fail "workflow is not pinned to the Intel macOS 15 runner"
if grep -E 'runs-on: macos-(latest|26)$' "$WF"; then
  fail "workflow still uses an arm64 runner label"
fi
grep -q 'pkgbuild' "$PKG" || fail "package script does not call pkgbuild"
grep -q -- '--install-location /Applications' "$PKG" || fail "package does not install into /Applications"
if grep -E 'spctl --|xattr |com\.apple\.quarantine' "$PKG" "$WF"; then
  fail "a script tries to change Gatekeeper or quarantine"
fi
if grep -n -- '--scripts' "$PKG"; then
  fail "package script adds installer scripts"
fi
echo "Intel package setup checks passed. No pkg was built."
