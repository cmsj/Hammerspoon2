#!/bin/bash
#
# Builds the extension and wraps it in a signed .hsmodule bundle, ready to copy into
# ~/.config/Hammerspoon2/Extensions (or a Spoon's Extensions folder).
#
# Usage: ./build.sh [output directory]   (default: ./build)
#
# Environment:
#   SIGN_IDENTITY            Code signing identity, such as "Developer ID Application: ..."
#                            (default: "-", an ad-hoc signature)
#   HAMMERSPOON_SDK_PACKAGE  Build against a local copy of the HammerspoonSDK package
set -euo pipefail

NAME="com.example.hello"
PRODUCT="ExampleExtension"

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/build}"
BUNDLE="$OUT/$NAME.hsmodule"

cd "$HERE"
swift build -c release --product "$PRODUCT"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp Bundle/Info.plist "$BUNDLE/Contents/Info.plist"
cp "$BIN_DIR/lib$PRODUCT.dylib" "$BUNDLE/Contents/MacOS/$PRODUCT"
if [ -f "Bundle/$NAME.js" ]; then
    cp "Bundle/$NAME.js" "$BUNDLE/Contents/Resources/$NAME.js"
fi

# Only the extension's own code goes in the bundle. HammerspoonSDK.framework is provided by
# Hammerspoon 2, which refuses extensions that bring their own copy.
codesign --force --timestamp=none --sign "${SIGN_IDENTITY:--}" "$BUNDLE"
codesign --verify --strict "$BUNDLE"
echo "$BUNDLE"
