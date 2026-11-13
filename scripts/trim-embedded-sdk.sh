#!/bin/bash
# Trims the HammerspoonSDK.framework embedded in the app down to what extension authors should
# compile against, and re-signs it. Run as an Xcode Run Script build phase on the
# "Hammerspoon 2" target, after "Embed Frameworks".
#
# Authors build against the app's own copy (-F "Hammerspoon 2.app/Contents/Frameworks"), so the
# copy keeps the SDK's public .swiftinterface, from which any later Swift compiler can build the
# module. It drops:
#   - *.private.swiftinterface: declares the @_spi(HammerspoonHost) API that only the app may use
#   - the binary *.swiftmodule: also includes that SPI, and only works with the exact compiler
#     that built it, so the compiler would fall back to the .swiftinterface anyway
#   - Project/: source info, with paths on the machine that built it
#
# Changing the framework breaks the signature Embed Frameworks gave it, so it's signed again
# here; the app itself is signed after all build phases. Release exports re-sign everything
# with the Developer ID anyway.
set -euo pipefail

FRAMEWORK="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/HammerspoonSDK.framework"
MODULE="$FRAMEWORK/Versions/A/Modules/HammerspoonSDK.swiftmodule"

if [ ! -d "$MODULE" ]; then
    echo "${BASH_SOURCE[0]}:${LINENO}: error: $MODULE is missing; extension authors would have no interface to build against." >&2
    exit 1
fi

shopt -s nullglob
EXTRA=("$MODULE"/*.private.swiftinterface "$MODULE"/*.package.swiftinterface "$MODULE"/*.swiftmodule)
[ -e "$MODULE/Project" ] && EXTRA+=("$MODULE/Project")
shopt -u nullglob

# Embed Frameworks only copies the framework when it has changed, so there's often nothing to
# do, and re-signing would needlessly touch it
if [ ${#EXTRA[@]} -eq 0 ]; then
    exit 0
fi
rm -rf "${EXTRA[@]}"

if ! ls "$MODULE"/*.swiftinterface >/dev/null 2>&1; then
    echo "${BASH_SOURCE[0]}:${LINENO}: error: $MODULE has no .swiftinterface; is BUILD_LIBRARY_FOR_DISTRIBUTION on?" >&2
    exit 1
fi

if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    # shellcheck disable=SC2086 # OTHER_CODE_SIGN_FLAGS is a list of flags
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} \
        --preserve-metadata=identifier,flags "$FRAMEWORK"
fi
