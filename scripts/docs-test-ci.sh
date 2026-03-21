#!/bin/bash
# CI wrapper for docs tests that produces GitHub Actions annotations
# Run this instead of test-docs.sh in CI environments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Change to repo root so relative paths in test-docs.sh work
cd "${REPO_ROOT}"

# Capture output while also printing it
OUTPUT_FILE=$(mktemp)
trap 'rm -f "${OUTPUT_FILE}"' EXIT
set +e
bash "${SCRIPT_DIR}/test-docs.sh" 2>&1 | tee "${OUTPUT_FILE}"
EXIT_CODE=${PIPESTATUS[0]}
set -e

# If running in GitHub Actions, produce annotations from error lines
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    if [ "${EXIT_CODE}" -ne 0 ]; then
        # Convert ❌ lines to GitHub error annotations
        while IFS= read -r line; do
            # Match lines containing ❌ (docs test failure markers)
            if echo "${line}" | grep -q "❌"; then
                MSG=$(echo "${line}" | sed 's/.*❌ //')
                echo "::error::Docs test failed: ${MSG}"
            fi
        done < "${OUTPUT_FILE}"
    fi

    # Write job summary
    {
        echo "## Documentation Test Results"
        echo ""
        if [ "${EXIT_CODE}" -eq 0 ]; then
            echo "✅ All documentation tests passed!"
        else
            echo "❌ Documentation tests failed"
            echo ""
            echo "### Errors"
            echo '```'
            grep "❌" "${OUTPUT_FILE}" || true
            echo '```'
            echo ""
            echo "### Full Output"
            echo "<details>"
            echo "<summary>Click to expand</summary>"
            echo ""
            echo '```'
            cat "${OUTPUT_FILE}"
            echo '```'
            echo "</details>"
        fi
    } >> "${GITHUB_STEP_SUMMARY}"
fi

rm -f "${OUTPUT_FILE}"
exit "${EXIT_CODE}"
