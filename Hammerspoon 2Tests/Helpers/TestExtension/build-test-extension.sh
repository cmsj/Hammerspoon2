#!/usr/bin/env bash
#
# Builds "hs2.testextension.hsmodule", the third-party extension the extension tests load (see
# TestExtension.swift next to this script), into <output directory>/TestExtensions, and prints
# its path. Does nothing when it is up to date.
#
# It's built the way a third party would build one: compiled with `swiftc` against
# HammerspoonSDK.framework and nothing else from the app, then given an ad-hoc signature.
#
# Usage: build-test-extension.sh <output directory> <directory containing HammerspoonSDK.framework>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?usage: build-test-extension.sh <output directory> <SDK framework directory>}"
SDK_DIR="${2:?usage: build-test-extension.sh <output directory> <SDK framework directory>}"

NAME="hs2.testextension"
SOURCE="$HERE/TestExtension.swift"
SCRIPT="$HERE/$NAME.js"
SDK_BINARY="$SDK_DIR/HammerspoonSDK.framework/HammerspoonSDK"
BUNDLE="$OUT/TestExtensions/$NAME.hsmodule"
CONTENTS="$BUNDLE/Contents"
EXECUTABLE="$CONTENTS/MacOS/HS2TestExtension"
MIN_MACOS="27.0"

if [[ ! -x "$EXECUTABLE" || "$SOURCE" -nt "$EXECUTABLE" || "$SCRIPT" -nt "$EXECUTABLE" \
      || "$SDK_BINARY" -nt "$EXECUTABLE" || "$0" -nt "$EXECUTABLE" ]]; then
    rm -rf "$BUNDLE"
    mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

    # Xcode's build settings in the environment (SDKROOT and friends) would mislead swiftc;
    # DEVELOPER_DIR stays, so a build phase uses the Xcode that runs it. The SDK framework is
    # already loaded by the app that loads the extension, so it's found through the app's rpath.
    env -i PATH="/usr/bin:/bin" HOME="$HOME" ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} xcrun swiftc \
        -parse-as-library -emit-library -swift-version 6 -D TEST_EXTENSION \
        -module-name HS2TestExtension \
        -target "$(uname -m)-apple-macos$MIN_MACOS" \
        -F "$SDK_DIR" -framework HammerspoonSDK \
        "$SOURCE" -o "$EXECUTABLE" >&2

    cp "$SCRIPT" "$CONTENTS/Resources/$NAME.js"

    cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>HS2TestExtension</string>
  <key>CFBundleIdentifier</key>
  <string>net.tenshu.Hammerspoon-2.TestExtension</string>
  <key>CFBundleName</key>
  <string>Hammerspoon 2 Test Extension</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>NSPrincipalClass</key>
  <string>HS2TestExtensionModule</string>
  <key>HSModuleName</key>
  <string>$NAME</string>
  <key>HSSDKVersion</key>
  <string>1.0</string>
</dict>
</plist>
PLIST

    # A sealed ad-hoc signature, covering the Info.plist and the script as well as the code
    codesign --force --sign - "$BUNDLE" >&2
fi

echo "$BUNDLE"
