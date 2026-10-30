#!/usr/bin/env bash
#
# Builds "Hammerspoon 2 Test App.app", the app the integration tests launch instead of Finder or
# Chess (see TestApp.swift next to this script), into the given directory and prints its path.
# Does nothing when it is up to date.
#
# An app bundle is only a folder with an executable and an Info.plist, so `swiftc` and a few
# lines here are enough; there is no Xcode target for it. The test target's "Build Test App"
# phase runs this script with $BUILT_PRODUCTS_DIR, so the app sits next to "Hammerspoon 2.app"
# and travels with the build products (TestAppControl.swift looks for it there).
#
# Usage: build-test-app.sh <output directory>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?usage: build-test-app.sh <output directory>}"
mkdir -p "$OUT"

SOURCE="$HERE/TestApp.swift"
APP_BUNDLE="$OUT/Hammerspoon 2 Test App.app"
CONTENTS="$APP_BUNDLE/Contents"
EXECUTABLE="$CONTENTS/MacOS/Hammerspoon2TestApp"
MIN_MACOS="14.0"

if [[ ! -x "$EXECUTABLE" || "$SOURCE" -nt "$EXECUTABLE" || "$0" -nt "$EXECUTABLE" ]]; then
    rm -rf "$APP_BUNDLE"
    mkdir -p "$CONTENTS/MacOS"

    # Xcode's build settings in the environment (SDKROOT and friends) would mislead swiftc;
    # DEVELOPER_DIR stays, so a build phase uses the Xcode that runs it. Without -target, swiftc
    # targets the host's macOS version, and a VM guest on an older one refuses to launch the app
    env -i PATH="/usr/bin:/bin" HOME="$HOME" ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} xcrun swiftc -O -parse-as-library -D TEST_APP \
        -target "$(uname -m)-apple-macos$MIN_MACOS" "$SOURCE" -o "$EXECUTABLE" >&2

    cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Hammerspoon2TestApp</string>
  <key>CFBundleIdentifier</key>
  <string>net.tenshu.Hammerspoon-2.TestApp</string>
  <key>CFBundleName</key>
  <string>Hammerspoon 2 Test App</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

    # A sealed ad-hoc signature, like the one hs2vm gives the main app; the linker's alone
    # doesn't cover the Info.plist
    codesign --force --sign - "$APP_BUNDLE" >&2
fi

echo "$APP_BUNDLE"
