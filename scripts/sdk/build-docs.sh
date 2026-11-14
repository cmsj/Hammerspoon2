#!/bin/bash
#
# Builds the HammerspoonSDK's Swift API documentation with DocC, as a static website for
# extension authors, published next to the JavaScript and TypeScript docs.
#
# It documents what authors build against: the public .swiftinterface (and the doc comments in
# the .swiftdoc) that the app ships, not the SDK's source, so the host-only SPI stays out. The
# landing page and any articles are in HammerspoonSDK/HammerspoonSDK.docc.
#
# Usage: build-docs.sh <output directory> [hosting base path]
#
# The hosting base path is where the site will be served from, without leading or trailing
# slashes, such as "Hammerspoon2/main/sdk" for https://cmsj.github.io/Hammerspoon2/main/sdk/.
# The docs then start at <base path>/documentation/hammerspoonsdk/. Without it, the site must be
# served from the root of its host.
set -euo pipefail

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

OUTPUT="${1:?usage: build-docs.sh <output directory> [hosting base path]}"
BASE_PATH="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CATALOG="$REPO_ROOT/HammerspoonSDK/HammerspoonSDK.docc"
[ -d "$CATALOG" ] || die "no documentation catalog at $CATALOG"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Building HammerspoonSDK.framework" >&2
xcodebuild build -project "$REPO_ROOT/Hammerspoon 2.xcodeproj" -target HammerspoonSDK -configuration Release \
    -skipPackagePluginValidation SYMROOT="$WORK/build" OBJROOT="$WORK/obj" CODE_SIGNING_ALLOWED=NO -quiet >&2 \
    || die "couldn't build HammerspoonSDK"

# Keep only what scripts/trim-embedded-sdk.sh leaves in the app, so the symbols come from the
# public interface
FRAMEWORKS="$WORK/frameworks"
mkdir -p "$FRAMEWORKS"
cp -R "$WORK/build/Release/HammerspoonSDK.framework" "$FRAMEWORKS/"
MODULE="$FRAMEWORKS/HammerspoonSDK.framework/Versions/A/Modules/HammerspoonSDK.swiftmodule"
rm -rf "${MODULE:?}"/*.private.swiftinterface "${MODULE:?}"/*.package.swiftinterface "${MODULE:?}"/*.swiftmodule \
    "${MODULE:?}"/*.abi.json "${MODULE:?}/Project"
INTERFACE="$(find "$MODULE" -name '*.swiftinterface' | head -1)"
[ -n "$INTERFACE" ] || die "the build has no .swiftinterface"
TARGET="$(sed -n 's/^\/\/ swift-module-flags:.*-target \([^ ]*\).*/\1/p' "$INTERFACE")"

echo "Extracting the SDK's symbols" >&2
mkdir -p "$WORK/symbols"
xcrun swift-symbolgraph-extract -module-name HammerspoonSDK -F "$FRAMEWORKS" -target "$TARGET" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" -minimum-access-level public \
    -module-cache-path "$WORK/module-cache" -output-dir "$WORK/symbols" >/dev/null \
    || die "couldn't extract the SDK's symbols"

echo "Converting with DocC" >&2
rm -rf "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
DOCC_ARGS=(--additional-symbol-graph-dir "$WORK/symbols" --output-path "$OUTPUT"
    --fallback-display-name HammerspoonSDK --fallback-bundle-identifier net.tenshu.Hammerspoon-2.SDK
    --transform-for-static-hosting)
[ -z "$BASE_PATH" ] || DOCC_ARGS+=(--hosting-base-path "$BASE_PATH")
xcrun docc convert "$CATALOG" "${DOCC_ARGS[@]}" > "$WORK/docc.log" 2>&1 \
    || { cat "$WORK/docc.log" >&2; die "DocC couldn't build the docs"; }

# Every problem DocC finds is an error, except that the JavaScript docs mark an optional
# parameter with a "?" ("- Parameter name?: ..."), which DocC sees as a parameter that doesn't
# exist and one that isn't documented
PROBLEMS="$(awk '
    /^(warning|error): / { lines[++count] = $0 }
    match($0, /Parameter .[A-Za-z0-9_]+\?. not found/) {
        name = substr($0, RSTART + 11, RLENGTH - 23); optional[name] = 1
    }
    END {
        for (i = 1; i <= count; i++) {
            line = lines[i]
            if (match(line, /Parameter .[A-Za-z0-9_]+\?. not found/)) continue
            if (match(line, /Parameter .[A-Za-z0-9_]+. is missing documentation/)) {
                name = substr(line, RSTART + 11, RLENGTH - 37)
                if (name in optional) continue
            }
            print line
        }
    }' "$WORK/docc.log")"
if [ -n "$PROBLEMS" ]; then
    echo "$PROBLEMS" >&2
    die "fix the documentation problems DocC found"
fi

echo "$OUTPUT"
