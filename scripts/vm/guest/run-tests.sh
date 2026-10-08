#!/bin/bash
#
# Runs INSIDE the guest (via `tart exec`) to execute a build-for-testing product set that the
# host has streamed into ~/hs2-run/Products. Any arguments are passed through to xcodebuild,
# e.g. "-only-testing:Hammerspoon 2Tests/HSHashIntegrationTests".
#
set -uo pipefail

RUN="$HOME/hs2-run"
xctestrun="$(ls "$RUN"/Products/*.xctestrun 2>/dev/null | head -1)"
[[ -n "$xctestrun" ]] || { echo "run-tests: no .xctestrun in $RUN/Products" >&2; exit 2; }

# Let boot-time notification banners (e.g. "App Background Activity") clear before UI tests run.
sleep "${HS2VM_SETTLE_SECONDS:-10}"

# xcodebuild only forwards TEST_RUNNER_-prefixed variables to the test host (prefix stripped),
# so tests see HS2_VM=1.
export TEST_RUNNER_HS2_VM=1

xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination 'platform=macOS' \
    -parallel-testing-enabled NO \
    -resultBundlePath "$RUN/TestResults.xcresult" \
    "$@"
