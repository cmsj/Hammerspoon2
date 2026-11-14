#!/bin/bash
#
# Checks that changes to HammerspoonSDK's public API come with the right change to its version
# (HSSDK.version, in HammerspoonSDK/HSSDK.swift), by comparing a built SDK with the API of the
# newest SDK version that has been released, which is recorded in scripts/sdk/api/<x.y>.json:
#
#   - Removing or changing API, or adding a requirement to a protocol, breaks extensions built
#     against the released version, so it needs a new major version.
#   - Adding API needs a new minor version, so extensions that use it can say they need it.
#   - A released version's API can't change at all.
#
# The records are swift-api-digester dumps of the public .swiftinterface that ships in the app,
# so they don't include the host-only SPI. Each release that ships a new SDK version records it:
# release.sh prepare refuses to release one that isn't recorded.
#
# Usage:
#   check-api.sh check  <Hammerspoon 2.app | HammerspoonSDK.framework>
#   check-api.sh record <Hammerspoon 2.app | HammerspoonSDK.framework>
#   check-api.sh version     prints HSSDK.version, and whether it has been recorded
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RECORDS="$REPO_ROOT/scripts/sdk/api"
VERSION_SOURCE="$REPO_ROOT/HammerspoonSDK/HSSDK.swift"

die() { echo "$(basename "$0"): $*" >&2; exit 1; }
usage() { die "usage: $(basename "$0") check|record <Hammerspoon 2.app | HammerspoonSDK.framework>, or version"; }

CURRENT="$(sed -n 's/.*static let version = HSSDKVersion(major: \([0-9]*\), minor: \([0-9]*\)).*/\1.\2/p' "$VERSION_SOURCE")"
[ -n "$CURRENT" ] || die "can't find HSSDK.version in $VERSION_SOURCE"
CURRENT_MAJOR="${CURRENT%.*}"
CURRENT_MINOR="${CURRENT#*.}"

COMMAND="${1:-}"
BUILT="${2:-}"
if [ "$COMMAND" = "version" ]; then
    if [ -f "$RECORDS/$CURRENT.json" ]; then
        echo "$CURRENT (recorded)"
    else
        echo "$CURRENT (not recorded)"
    fi
    exit 0
fi
[ "$COMMAND" = "check" ] || [ "$COMMAND" = "record" ] || usage
[ -n "$BUILT" ] || usage

case "$BUILT" in
    *.app | *.app/) FRAMEWORK="$BUILT/Contents/Frameworks/HammerspoonSDK.framework" ;;
    *) FRAMEWORK="$BUILT" ;;
esac
[ -d "$FRAMEWORK" ] || die "no HammerspoonSDK.framework at $FRAMEWORK"
INTERFACE="$(find "$FRAMEWORK/Modules/HammerspoonSDK.swiftmodule/" -name '*.swiftinterface' \
    ! -name '*.private.swiftinterface' ! -name '*.package.swiftinterface' | head -1)"
[ -n "$INTERFACE" ] || die "$FRAMEWORK has no .swiftinterface"
TARGET="$(sed -n 's/^\/\/ swift-module-flags:.*-target \([^ ]*\).*/\1/p' "$INTERFACE")"
[ -n "$TARGET" ] || die "can't find the target in $INTERFACE"

# The newest recorded version, or nothing
BASELINE=""
if [ -d "$RECORDS" ]; then
    BASELINE="$(find "$RECORDS" -maxdepth 1 -name '*.*.json' | sed 's|.*/||; s|\.json$||' \
        | sort -t. -k1,1n -k2,2n | tail -1)"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Dumps the built SDK's public API, in a form that doesn't depend on where it was built
dump() {
    # Built from the .swiftinterface, the only module the trimmed framework has
    xcrun swift-api-digester -dump-sdk -abi -avoid-location -avoid-tool-args \
        -module HammerspoonSDK -F "$(dirname "$FRAMEWORK")" -target "$TARGET" \
        -module-cache-path "$WORK/module-cache" -o "$1" \
        || die "swift-api-digester couldn't read the SDK's interface"
}

# diagnose <old dump> <new dump> [-abi]: what changed from one to the other, one change per line
diagnose() {
    xcrun swift-api-digester -diagnose-sdk "${@:3}" -input-paths "$1" -input-paths "$2" -o "$WORK/diagnosis" \
        || die "swift-api-digester couldn't compare $1 with $2"
    grep -v '^$' "$WORK/diagnosis" | grep -v '^/\*' || true
}

dump "$WORK/current.json"

if [ "$COMMAND" = "record" ]; then
    if [ -f "$RECORDS/$CURRENT.json" ]; then
        die "SDK $CURRENT is already recorded; a released version's API can't change (run check)"
    fi
    if [ -n "$BASELINE" ]; then
        "$0" check "$BUILT"
    fi
    mkdir -p "$RECORDS"
    cp "$WORK/current.json" "$RECORDS/$CURRENT.json"
    echo "Recorded the API of SDK $CURRENT in ${RECORDS#"$REPO_ROOT"/}/$CURRENT.json"
    exit 0
fi

if [ -z "$BASELINE" ]; then
    echo "No SDK version has been recorded yet, so there's nothing to compare SDK $CURRENT with."
    exit 0
fi
BASELINE_MAJOR="${BASELINE%.*}"
BASELINE_MINOR="${BASELINE#*.}"
if [ "$CURRENT_MAJOR" -lt "$BASELINE_MAJOR" ] \
    || { [ "$CURRENT_MAJOR" -eq "$BASELINE_MAJOR" ] && [ "$CURRENT_MINOR" -lt "$BASELINE_MINOR" ]; }; then
    die "HSSDK.version is $CURRENT, older than the released SDK $BASELINE"
fi

BASE="$RECORDS/$BASELINE.json"
# Source-level changes, which include new protocol requirements (@objc protocols have no
# witness tables, so ABI checking doesn't treat those as breaking)...
diagnose "$BASE" "$WORK/current.json" > "$WORK/api"
# ...and binary-level ones, which also list everything added
diagnose "$BASE" "$WORK/current.json" -abi > "$WORK/abi"
ADDED="$(grep "is a new API without '@available'" "$WORK/abi" | sed "s/ is a new API without '@available'//" || true)"
BREAKING="$( { cat "$WORK/api"; grep -v "is a new API without '@available'" "$WORK/abi" || true; } | sort -u)"
# Anything else is visible comparing the other way round, as something "removed"
REVERSE="$(diagnose "$WORK/current.json" "$BASE")"

if [ -z "$BREAKING" ] && [ -z "$ADDED" ] && [ -z "$REVERSE" ]; then
    echo "The SDK's API is unchanged since SDK $BASELINE."
    exit 0
fi

report() {
    if [ -n "$BREAKING" ]; then
        echo "Changes that break extensions built against SDK $BASELINE:"
        sed 's/^/  /' <<<"$BREAKING"
    fi
    if [ -n "$ADDED" ]; then
        echo "Added since SDK $BASELINE:"
        sed 's/^/  /' <<<"$ADDED"
    elif [ -z "$BREAKING" ]; then
        echo "Changes since SDK $BASELINE, compared the other way round:"
        sed 's/^/  /' <<<"$REVERSE"
    fi
}

NEXT_MAJOR="$((BASELINE_MAJOR + 1)).0"
NEXT_MINOR="$BASELINE_MAJOR.$((BASELINE_MINOR + 1))"
if [ "$CURRENT" = "$BASELINE" ]; then
    report >&2
    if [ -n "$BREAKING" ]; then
        die "SDK $BASELINE has been released, so its API can't change. Avoid the breaking changes, or set HSSDK.version to $NEXT_MAJOR."
    fi
    die "SDK $BASELINE has been released, so its API can't change. Set HSSDK.version to $NEXT_MINOR."
fi
if [ -n "$BREAKING" ] && [ "$CURRENT_MAJOR" -eq "$BASELINE_MAJOR" ]; then
    report >&2
    die "SDK $CURRENT can't break extensions built against SDK $BASELINE. Avoid the breaking changes, or set HSSDK.version to $NEXT_MAJOR."
fi
report
echo "SDK $CURRENT's version allows these changes."
