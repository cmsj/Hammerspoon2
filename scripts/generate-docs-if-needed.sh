#!/bin/bash
# Regenerates docs/api.json, docs/hammerspoon.d.ts, docs/js and docs/ts from
# the /// doc comments in source, but only when something they depend on has
# changed. This is run as an Xcode Run Script build phase on the
# "Hammerspoon 2" target, before Copy Bundle Resources, so the generated docs
# that get bundled into the app never need to be committed to git.
set -euo pipefail

cd "$(dirname "$0")/.."

# Xcode Run Script phases use a minimal PATH; add the common places Node gets
# installed (Homebrew) so `npm` can be found.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# The paths that `npm run docs:generate` produces and that get bundled into
# the app. Tracked as a list so a failed or placeholder generation can be
# cleaned up without leaving any of them looking like current output.
GENERATED_PATHS=(docs/api.json docs/hammerspoon.d.ts docs/js/html docs/ts/html)

# Marks output written by the placeholder fallback below, so that once real
# documentation can be generated again the next build always regenerates for
# real instead of trusting the placeholder as current.
PLACEHOLDER_MARKER="docs/.placeholder-docs"

# A Release build (Archive/distribution) must never ship placeholder
# documentation, so fail hard rather than silently bundling empty docs. A
# Debug build falls back to placeholder docs (leaving any already-generated
# real docs in place) so local iteration isn't blocked by missing Node.js or
# an unreachable npm registry.
fail_or_use_placeholder() {
    local reason="$1"
    if [ "${CONFIGURATION:-}" = "Release" ]; then
        echo "${BASH_SOURCE[0]}:${LINENO}: error: ${reason} cannot generate documentation for a Release build." >&2
        exit 1
    fi
    echo "${BASH_SOURCE[0]}:${LINENO}: warning: ${reason} skipping documentation generation for this Debug build."
    # Make sure the bundle resources Xcode expects at these paths exist, even
    # if empty, so the build doesn't fail on a missing folder/file reference.
    # Existing real docs from an earlier successful generation are left as-is.
    mkdir -p docs/js/html docs/ts/html
    [ -f docs/api.json ] || echo '{}' > docs/api.json
    [ -f docs/hammerspoon.d.ts ] || : > docs/hammerspoon.d.ts
    [ -f docs/js/html/index.html ] || : > docs/js/html/index.html
    [ -f docs/ts/html/index.html ] || : > docs/ts/html/index.html
    : > "$PLACEHOLDER_MARKER"
    exit 0
}

if ! command -v npm >/dev/null 2>&1; then
    fail_or_use_placeholder "npm not found on PATH;"
fi

if [ ! -d node_modules ]; then
    echo "node_modules missing, running npm install..."
    if ! npm install; then
        fail_or_use_placeholder "npm install failed (offline, or the npm registry is unreachable);"
    fi
fi

STAMP="docs/api.json"
NEEDS_GENERATE=0

# A Release build must always ship documentation generated from its own
# source, never output left over from a previous build, so it skips the
# staleness check below and regenerates unconditionally.
if [ "${CONFIGURATION:-}" = "Release" ]; then
    NEEDS_GENERATE=1
elif [ ! -f "$STAMP" ] || [ ! -d docs/js/html ] || [ ! -d docs/ts/html ] || [ -f "$PLACEHOLDER_MARKER" ]; then
    NEEDS_GENERATE=1
elif find "Hammerspoon 2" scripts docs/*.md docs/tsconfig.docs.json package.json \
        \( -name "*.swift" -o -name "*.js" -o -name "*.md" -o -name "*.njk" -o -name "*.css" \
           -o -name "package.json" -o -name "tsconfig.docs.json" \) \
        -newer "$STAMP" -print -quit | grep -q .; then
    NEEDS_GENERATE=1
fi

if [ "$NEEDS_GENERATE" -eq 1 ]; then
    echo "Documentation is stale or missing, regenerating..."
    if ! npm run docs:generate; then
        # api.json lands before the HTML/TypeScript steps run, so a failure
        # partway through can otherwise leave a fresh-looking api.json next
        # to stale js/ts output that a later build would trust as current.
        echo "${BASH_SOURCE[0]}:${LINENO}: error: documentation generation failed; removing partial output so it isn't mistaken for current on the next build." >&2
        rm -rf "${GENERATED_PATHS[@]}" "$PLACEHOLDER_MARKER"
        exit 1
    fi
    # `-f` makes this a no-op (exit 0) when no placeholder marker exists; a
    # bare `[ -f ... ] && rm ...` would instead trip `set -e` on that case.
    rm -f "$PLACEHOLDER_MARKER"
else
    echo "Documentation is up to date, skipping generation."
fi
