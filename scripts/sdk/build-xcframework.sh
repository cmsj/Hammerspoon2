#!/bin/bash
#
# Packages the HammerspoonSDK.framework inside a built Hammerspoon 2.app as a zipped
# XCFramework, for extension authors who want to build without Hammerspoon 2 installed (in CI,
# say) and for the HammerspoonSDK Swift package, then prints the zip's Swift Package Manager
# checksum.
#
# The framework is taken from the app, rather than built separately, so it's exactly what the
# app ships: trimmed to the public .swiftinterface by scripts/trim-embedded-sdk.sh, and signed
# as the app is. Before zipping it, this checks that it has no private interface, and that code
# using the SDK type-checks against it.
#
# Usage: build-xcframework.sh <Hammerspoon 2.app> <output .xcframework.zip>
set -euo pipefail

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

APP="${1:?usage: build-xcframework.sh <Hammerspoon 2.app> <output .xcframework.zip>}"
OUTPUT="${2:?usage: build-xcframework.sh <Hammerspoon 2.app> <output .xcframework.zip>}"
FRAMEWORK="$APP/Contents/Frameworks/HammerspoonSDK.framework"
MODULE="$FRAMEWORK/Modules/HammerspoonSDK.swiftmodule"

[ -d "$FRAMEWORK" ] || die "$APP has no HammerspoonSDK.framework"
ls "$MODULE"/*.swiftinterface >/dev/null 2>&1 || die "$FRAMEWORK has no .swiftinterface to build against"
if ls "$MODULE"/*.private.swiftinterface "$MODULE"/*.package.swiftinterface >/dev/null 2>&1; then
    die "$FRAMEWORK still has its private interface; it should have been trimmed by scripts/trim-embedded-sdk.sh"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcodebuild -create-xcframework -framework "$FRAMEWORK" -output "$WORK/HammerspoonSDK.xcframework" >/dev/null

# An extension built against the package must compile
SLICE="$(find "$WORK/HammerspoonSDK.xcframework" -mindepth 2 -maxdepth 2 -name HammerspoonSDK.framework | head -1)"
[ -n "$SLICE" ] || die "the XCFramework has no HammerspoonSDK.framework"
cat > "$WORK/check.swift" <<'SWIFT'
import JavaScriptCore
import HammerspoonSDK

@MainActor func check() -> HSSDKVersion {
    AKDebug("SDK \(HSSDK.version)")
    return HSSDK.version
}
SWIFT
xcrun swiftc -typecheck -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos27.0" \
    -F "$(dirname "$SLICE")" "$WORK/check.swift" \
    || die "code using the SDK doesn't type-check against the XCFramework"

mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
rm -f "$OUTPUT"
# Without extended attributes, which ditto would otherwise add as ._ files
(cd "$WORK" && ditto -c -k --norsrc --noextattr --noqtn --keepParent HammerspoonSDK.xcframework "$OUTPUT")
# From the work directory, since it leaves a .build directory in the current one
(cd "$WORK" && swift package compute-checksum "$OUTPUT")
