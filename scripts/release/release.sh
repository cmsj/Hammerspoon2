#!/bin/bash
#
# Build, notarise and publish a Hammerspoon 2 release.
#
#   scripts/release/release.sh [options] <version>
#
# Starting from a clean checkout of the commit to release, this:
#
#   1. archives the Release scheme with MARKETING_VERSION=<version> and
#      CURRENT_PROJECT_VERSION=<commit count>, so Sparkle's build numbers only
#      ever go up
#   2. exports it signed with Developer ID
#   3. notarises and staples it
#   4. zips it and signs the zip with the Sparkle EdDSA key
#   5. builds signed binary deltas against the previous releases that this
#      script published
#   6. writes sparkle.json, which describes all of the above
#   7. constructs a changelog from the pull requests merged since the last
#      release (or takes yours from --notes-file)
#   8. adds the release to the live appcast.xml and signs the feed with the
#      Sparkle EdDSA key, so Sparkle (with SURequireSignedFeed) can tell it
#      hasn't been tampered with
#   9. tags the commit, pushes the tag and creates a GitHub release with the
#      notes as its description and the zip, deltas, sparkle.json, appcast.xml
#      and release-notes.md attached
#
# The release is created as a draft so it can be reviewed. Publishing it (here
# with --publish, or later on GitHub) triggers the appcast workflow
# (.github/workflows/appcast.yml), which checks the attached appcast.xml is
# still current and copies it, byte for byte, to GitHub Pages. CI never
# changes the feed, because it can't re-sign it.
#
# If you edit the notes of a draft (or published) release on GitHub, the
# signed appcast no longer matches them, and the workflow will refuse to
# publish it. Rebuild and re-sign it with:
#
#   scripts/release/release.sh --update-appcast <version>
#
# One-time setup:
#   - A "Developer ID Application" certificate for team VQCYSNZB89 in your
#     keychain (or Xcode-managed cloud signing).
#   - A notarytool keychain profile:
#       xcrun notarytool store-credentials hammerspoon2-notary \
#           --apple-id <apple id> --team-id VQCYSNZB89
#   - A Sparkle EdDSA key in your keychain, with its public half in
#     Hammerspoon-2-Info.plist as SUPublicEDKey, alongside SURequireSignedFeed
#     and SUVerifyUpdateBeforeExtraction set to true. Sparkle's generate_keys
#     creates the key and prints the SUPublicEDKey entry; run
#     `scripts/release/release.sh --print-sparkle-bin` to find it.
#   - gh, authenticated with permission to push tags and create releases.
#   - node (already needed to build the docs).
#
# Environment:
#   NOTARY_PROFILE      notarytool keychain profile (default: hammerspoon2-notary)
#   SPARKLE_KEY_ACCOUNT Sparkle keychain account (default: ed25519)
#   DELTA_COUNT         previous releases to build deltas from (default: 3)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$REPO_ROOT/Hammerspoon 2.xcodeproj"
INFO_PLIST="$REPO_ROOT/Hammerspoon-2-Info.plist"
SCHEME="Release"
APP_NAME="Hammerspoon 2"
ASSET_BASENAME="Hammerspoon-2"
TEAM_ID="VQCYSNZB89"
METADATA_NAME="sparkle.json"
APPCAST_NAME="appcast.xml"
NOTES_NAME="release-notes.md"

NOTARY_PROFILE="${NOTARY_PROFILE:-hammerspoon2-notary}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"
DELTA_COUNT="${DELTA_COUNT:-3}"

PUBLISH=0
CREATE_RELEASE=1
EDIT_NOTES=0
UPDATE_APPCAST=0
NOTES_FILE=""
VERSION=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <version>
       $(basename "$0") --update-appcast <version>

Options:
  --publish            Publish the GitHub release immediately instead of
                       leaving it as a draft. This updates the live appcast.
  --notes-file FILE    Use FILE (markdown) as the release notes instead of a
                       changelog generated from merged pull requests.
  --edit-notes         Open the release notes in \$EDITOR before they're
                       signed into the appcast.
  --no-release         Build, notarise and sign everything, but don't tag,
                       push or create a GitHub release.
  --update-appcast     Don't build anything: rebuild and re-sign the appcast
                       for an existing release from its current notes on
                       GitHub, and replace the release's appcast.xml. Use
                       this after editing a release's notes.
  --print-sparkle-bin  Print the directory holding Sparkle's command line
                       tools (generate_keys, sign_update, ...) and exit.
  -h, --help           Show this help.

<version> is a tag name like 0.0.15 or 0.1.0-beta.1. Versions with a suffix
become GitHub prereleases in Sparkle's "beta" channel, which stable installs
never see.
EOF
}

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

PRINT_SPARKLE_BIN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --publish) PUBLISH=1 ;;
        --notes-file) NOTES_FILE="${2:?--notes-file needs a path}"; shift ;;
        --edit-notes) EDIT_NOTES=1 ;;
        --no-release) CREATE_RELEASE=0 ;;
        --update-appcast) UPDATE_APPCAST=1 ;;
        --print-sparkle-bin) PRINT_SPARKLE_BIN=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) usage >&2; die "unknown option: $1" ;;
        *) [ -z "$VERSION" ] || die "only one version may be given"; VERSION="$1" ;;
    esac
    shift
done

WORK_ROOT="$REPO_ROOT/build/release"
PACKAGES_DIR="$WORK_ROOT/SourcePackages"
SPARKLE_BIN="$PACKAGES_DIR/artifacts/sparkle/Sparkle/bin"

resolve_packages() {
    # Resolving into a known directory gives us Sparkle's tools from the same
    # Sparkle version that gets linked into the app.
    xcodebuild -resolvePackageDependencies \
        -project "$PROJECT" -scheme "$SCHEME" \
        -clonedSourcePackagesDirPath "$PACKAGES_DIR" >/dev/null
    [ -x "$SPARKLE_BIN/sign_update" ] || die "Sparkle tools not found in $SPARKLE_BIN"
}

if [ "$PRINT_SPARKLE_BIN" = 1 ]; then
    resolve_packages
    echo "$SPARKLE_BIN"
    exit 0
fi

[ -n "$VERSION" ] || { usage >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "version must look like 1.2.3 or 1.2.3-beta.1, got '$VERSION'"
PRERELEASE=0
[[ "$VERSION" == *-* ]] && PRERELEASE=1
if [ -n "$NOTES_FILE" ]; then
    [ -f "$NOTES_FILE" ] || die "notes file not found: $NOTES_FILE"
    NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"
fi

cd "$REPO_ROOT"

# Check everything needed to sign Sparkle artefacts and talk to GitHub.
preflight_signing() {
    for tool in xcodebuild xcrun ditto plutil codesign spctl gh git node; do
        command -v "$tool" >/dev/null || die "$tool is required"
    done
    gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
    GH_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

    resolve_packages

    PLIST_KEY="$(plutil -extract SUPublicEDKey raw "$INFO_PLIST" 2>/dev/null || true)"
    [ -n "$PLIST_KEY" ] || die "SUPublicEDKey is missing from $INFO_PLIST; run $SPARKLE_BIN/generate_keys and add the key it prints"
    for key in SURequireSignedFeed SUVerifyUpdateBeforeExtraction; do
        [ "$(plutil -extract "$key" raw "$INFO_PLIST" 2>/dev/null || true)" = "true" ] \
            || die "$INFO_PLIST must set $key to true (<key>$key</key><true/>)"
    done
    # This may ask for permission to read the key from your keychain.
    KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -p 2>/dev/null || true)"
    [ -n "$KEYCHAIN_KEY" ] || die "no Sparkle signing key for account '$SPARKLE_KEY_ACCOUNT' in your keychain"
    [ "$PLIST_KEY" = "$KEYCHAIN_KEY" ] || die "SUPublicEDKey in Info.plist does not match the Sparkle key in your keychain"
}

# build_appcast <notes.md> <sparkle.json> <output appcast.xml> [pub date]
#
# Adds the release described by sparkle.json to the appcast currently on
# gh-pages, with <notes.md> rendered as its description, then signs it.
build_appcast() {
    local notes="$1" metadata="$2" output="$3" pub_date="${4:-}"
    local scratch version
    scratch="$(dirname "$output")/appcast-work"
    rm -rf "$scratch"
    mkdir -p "$scratch"
    version="$(plutil -extract version raw "$metadata")"

    if [ -n "$(tr -d '[:space:]' < "$notes")" ]; then
        gh api markdown -f mode=gfm -f context="$GH_REPO" -F text=@"$notes" > "$scratch/notes.html"
    else
        : > "$scratch/notes.html"
    fi

    # Start from the feed as it is on gh-pages (which is what Pages serves), so
    # every earlier release stays in it.
    if git fetch --quiet origin gh-pages 2>/dev/null \
        && git cat-file -e "origin/gh-pages:$APPCAST_NAME" 2>/dev/null; then
        git show "origin/gh-pages:$APPCAST_NAME" > "$scratch/live.xml"
    else
        : > "$scratch/live.xml"
    fi
    cp "$scratch/live.xml" "$output"

    node "$REPO_ROOT/scripts/release/update-appcast.js" \
        --appcast "$output" \
        --metadata "$metadata" \
        --notes-html "$scratch/notes.html" \
        --download-prefix "https://github.com/$GH_REPO/releases/download/$version/" \
        --release-url "https://github.com/$GH_REPO/releases/tag/$version" \
        ${pub_date:+--pub-date "$pub_date"}

    "$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" "$output" >/dev/null
    "$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$output" \
        || die "the signed $APPCAST_NAME failed verification"

    # The same check the appcast workflow runs before publishing.
    node "$REPO_ROOT/scripts/release/check-appcast.js" \
        --candidate "$output" \
        --live "$scratch/live.xml" \
        --metadata "$metadata" \
        --signed-notes "$notes" \
        --release-notes "$notes"
}

# --- Update an existing release's appcast ----------------------------------

if [ "$UPDATE_APPCAST" = 1 ]; then
    log "Rebuilding the appcast for $VERSION"
    preflight_signing

    WORK="$WORK_ROOT/$VERSION-appcast"
    rm -rf "$WORK"
    mkdir -p "$WORK"
    IS_DRAFT="$(gh release view "$VERSION" --json isDraft --jq .isDraft)" \
        || die "there is no GitHub release for $VERSION"
    gh release download "$VERSION" --pattern "$METADATA_NAME" --dir "$WORK" \
        || die "release $VERSION has no $METADATA_NAME, so it wasn't made by this script"
    gh release view "$VERSION" --json body --jq .body | tr -d '\r' > "$WORK/$NOTES_NAME"

    PUB_DATE=""
    [ "$IS_DRAFT" = "true" ] || PUB_DATE="$(gh release view "$VERSION" --json publishedAt --jq .publishedAt)"

    build_appcast "$WORK/$NOTES_NAME" "$WORK/$METADATA_NAME" "$WORK/$APPCAST_NAME" "$PUB_DATE"
    gh release upload "$VERSION" "$WORK/$APPCAST_NAME" "$WORK/$NOTES_NAME" --clobber

    if [ "$IS_DRAFT" = "true" ]; then
        echo "Updated. The appcast will go live when the release is published."
    else
        gh workflow run appcast.yml -f tag="$VERSION"
        echo "Updated, and started the appcast workflow to publish it."
    fi
    exit 0
fi

# --- Preflight -------------------------------------------------------------

log "Preflight checks"

[ -z "$(git status --porcelain)" ] || die "working tree is not clean"
git fetch --quiet --tags origin
HEAD_SHA="$(git rev-parse HEAD)"
[ -n "$(git branch -r --contains "$HEAD_SHA")" ] || die "HEAD ($HEAD_SHA) has not been pushed to origin"

if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
    [ "$(git rev-parse "$VERSION^{commit}")" = "$HEAD_SHA" ] || die "tag $VERSION already exists and does not point at HEAD"
    TAG_EXISTS=1
else
    TAG_EXISTS=0
fi

preflight_signing

if [ "$CREATE_RELEASE" = 1 ] && gh release view "$VERSION" >/dev/null 2>&1; then
    die "a GitHub release for $VERSION already exists"
fi

# Sparkle compares CFBundleVersion, which must only ever increase. The number
# of commits leading up to the release does that for as long as releases come
# from one line of history, which these checks make sure of.
[ "$(git rev-parse --is-shallow-repository)" = "false" ] \
    || die "this is a shallow clone, so the commit count used as the build number would be too low (run: git fetch --unshallow)"
for other_tag in $(git tag --points-at HEAD); do
    [ "$other_tag" = "$VERSION" ] && continue
    gh release view "$other_tag" >/dev/null 2>&1 \
        && die "HEAD is already released as $other_tag, and a second release from the same commit would reuse its build number"
done
BUILD_NUMBER="$(git rev-list --count HEAD)"
LIVE_BUILD=""
if git fetch --quiet origin gh-pages 2>/dev/null \
    && git cat-file -e "origin/gh-pages:$APPCAST_NAME" 2>/dev/null; then
    LIVE_BUILD="$(git show "origin/gh-pages:$APPCAST_NAME" \
        | sed -n 's:.*<sparkle\:version>\([0-9][0-9]*\)</sparkle\:version>.*:\1:p' | sort -n | tail -1)"
fi
if [ -n "$LIVE_BUILD" ] && [ "$BUILD_NUMBER" -le "$LIVE_BUILD" ]; then
    die "build $BUILD_NUMBER is not newer than build $LIVE_BUILD in the live appcast, so Sparkle would ignore it"
fi

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notarytool profile '$NOTARY_PROFILE' is missing or invalid (see the setup notes at the top of $0)"

WORK="$WORK_ROOT/$VERSION"
rm -rf "$WORK"
mkdir -p "$WORK"
ARCHIVE="$WORK/$APP_NAME.xcarchive"
EXPORT_DIR="$WORK/export"
APP="$EXPORT_DIR/$APP_NAME.app"
ASSETS="$WORK/assets"
mkdir -p "$ASSETS"
ZIP_NAME="$ASSET_BASENAME-$VERSION.zip"
ZIP="$ASSETS/$ZIP_NAME"

echo "Version $VERSION, build $BUILD_NUMBER, commit $HEAD_SHA"
echo "Working in $WORK"

# --- Build -----------------------------------------------------------------

log "Archiving"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    > "$WORK/archive.log" 2>&1 \
    || { tail -40 "$WORK/archive.log"; die "archive failed, full log in $WORK/archive.log"; }

log "Exporting with Developer ID"
cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    > "$WORK/export.log" 2>&1 \
    || { tail -40 "$WORK/export.log"; die "export failed, full log in $WORK/export.log"; }
[ -d "$APP" ] || die "export did not produce $APP"

log "Checking the exported app"
APP_PLIST="$APP/Contents/Info.plist"
[ "$(plutil -extract CFBundleShortVersionString raw "$APP_PLIST")" = "$VERSION" ] || die "app has the wrong CFBundleShortVersionString"
[ "$(plutil -extract CFBundleVersion raw "$APP_PLIST")" = "$BUILD_NUMBER" ] || die "app has the wrong CFBundleVersion"
[ "$(plutil -extract SUPublicEDKey raw "$APP_PLIST")" = "$PLIST_KEY" ] || die "app is missing SUPublicEDKey"
MIN_SYSTEM_VERSION="$(plutil -extract LSMinimumSystemVersion raw "$APP_PLIST")"
codesign --verify --deep --strict "$APP"
SIGNATURE_INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q "^Authority=Developer ID Application: .*($TEAM_ID)" <<<"$SIGNATURE_INFO" || die "app is not signed with a Developer ID for $TEAM_ID"
grep -q "flags=.*runtime" <<<"$SIGNATURE_INFO" || die "app is not signed with the hardened runtime"

# --- Notarise --------------------------------------------------------------

log "Notarising (this usually takes a few minutes)"
NOTARY_ZIP="$WORK/notarize.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format plist > "$WORK/notarytool.plist" \
    || true
NOTARY_STATUS="$(plutil -extract status raw "$WORK/notarytool.plist" 2>/dev/null || echo unknown)"
NOTARY_ID="$(plutil -extract id raw "$WORK/notarytool.plist" 2>/dev/null || true)"
if [ "$NOTARY_STATUS" != "Accepted" ]; then
    if [ -n "$NOTARY_ID" ]; then
        xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" "$WORK/notarytool-log.json" || true
        cat "$WORK/notarytool-log.json" 2>/dev/null || true
    fi
    die "notarisation finished with status '$NOTARY_STATUS'"
fi
rm -f "$NOTARY_ZIP"

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute -vv "$APP"

# --- Sparkle artefacts -----------------------------------------------------

log "Packaging and signing $ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ZIP_SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" -p "$ZIP")"
ZIP_LENGTH="$(stat -f%z "$ZIP")"

log "Building deltas from up to $DELTA_COUNT previous releases"
# Only releases made by this script carry sparkle.json, and only their build
# numbers are guaranteed to be unique, so those are the ones we diff against.
DELTAS_JSON=""
DELTA_ASSETS=()
PREVIOUS_DIR="$WORK/previous"
mkdir -p "$PREVIOUS_DIR"
delta_count=0
PREVIOUS_TAGS=()
while read -r previous_tag; do
    [ -z "$previous_tag" ] || PREVIOUS_TAGS+=("$previous_tag")
done < <(gh release list --exclude-drafts --limit 30 --json tagName --jq '.[].tagName')
for previous_tag in ${PREVIOUS_TAGS[@]+"${PREVIOUS_TAGS[@]}"}; do
    [ "$previous_tag" != "$VERSION" ] || continue
    [ "$delta_count" -lt "$DELTA_COUNT" ] || break

    assets="$(gh release view "$previous_tag" --json assets --jq '.assets[].name')"
    grep -qx "$METADATA_NAME" <<<"$assets" || continue

    previous_work="$PREVIOUS_DIR/$previous_tag"
    mkdir -p "$previous_work"
    gh release download "$previous_tag" --pattern "$METADATA_NAME" --dir "$previous_work"
    previous_zip_name="$(plutil -extract archive.name raw "$previous_work/$METADATA_NAME")"
    gh release download "$previous_tag" --pattern "$previous_zip_name" --dir "$previous_work"
    ditto -x -k "$previous_work/$previous_zip_name" "$previous_work/app"
    previous_app="$previous_work/app/$APP_NAME.app"
    [ -d "$previous_app" ] || { echo "  $previous_tag: no $APP_NAME.app in $previous_zip_name, skipping"; continue; }

    previous_build="$(plutil -extract CFBundleVersion raw "$previous_app/Contents/Info.plist")"
    if ! [ "$previous_build" -lt "$BUILD_NUMBER" ] 2>/dev/null; then
        echo "  $previous_tag: build $previous_build is not older than $BUILD_NUMBER, skipping"
        continue
    fi

    delta_name="$ASSET_BASENAME-$BUILD_NUMBER-$previous_build.delta"
    delta="$ASSETS/$delta_name"
    echo "  $previous_tag (build $previous_build) -> $delta_name"
    "$SPARKLE_BIN/BinaryDelta" create "$previous_app" "$APP" "$delta"

    # Prove the delta reproduces a correctly signed copy of the new app before
    # shipping it.
    applied="$previous_work/applied/$APP_NAME.app"
    mkdir -p "$(dirname "$applied")"
    "$SPARKLE_BIN/BinaryDelta" apply "$previous_app" "$applied" "$delta"
    codesign --verify --deep --strict "$applied" || die "applying $delta_name produced an app that fails code signing checks"

    delta_signature="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" -p "$delta")"
    delta_length="$(stat -f%z "$delta")"
    [ -z "$DELTAS_JSON" ] || DELTAS_JSON+=","
    DELTAS_JSON+="
    { \"from\": \"$previous_build\", \"name\": \"$delta_name\", \"length\": $delta_length, \"edSignature\": \"$delta_signature\" }"
    DELTA_ASSETS+=("$delta")
    delta_count=$((delta_count + 1))
done
[ "$delta_count" -gt 0 ] || echo "  no earlier releases with $METADATA_NAME, so no deltas this time"

METADATA="$ASSETS/$METADATA_NAME"
# Prereleases go in Sparkle's beta channel, which only installs that opt in to
# it are offered.
CHANNEL_JSON=""
[ "$PRERELEASE" = 0 ] || CHANNEL_JSON='
  "channel": "beta",'
cat > "$METADATA" <<EOF
{
  "version": "$VERSION",${CHANNEL_JSON}
  "build": "$BUILD_NUMBER",
  "commit": "$HEAD_SHA",
  "minimumSystemVersion": "$MIN_SYSTEM_VERSION",
  "archive": { "name": "$ZIP_NAME", "length": $ZIP_LENGTH, "edSignature": "$ZIP_SIGNATURE" },
  "deltas": [${DELTAS_JSON}
  ]
}
EOF
plutil -convert json -o /dev/null "$METADATA" || die "generated $METADATA is not valid JSON"

# --- Changelog and appcast -------------------------------------------------

NOTES="$ASSETS/$NOTES_NAME"
if [ -n "$NOTES_FILE" ]; then
    log "Using release notes from $NOTES_FILE"
    tr -d '\r' < "$NOTES_FILE" > "$NOTES"
else
    log "Constructing a changelog from pull requests merged since the last release"
    # GitHub picks the previous release as the starting point. The tag may not
    # exist yet, so tell it which commit the release will be.
    gh api "repos/$GH_REPO/releases/generate-notes" \
        -f tag_name="$VERSION" -f target_commitish="$HEAD_SHA" \
        --jq .body > "$NOTES"
fi
if [ "$EDIT_NOTES" = 1 ]; then
    ${EDITOR:-vi} "$NOTES"
fi
echo "----"
cat "$NOTES"
echo "----"

log "Building and signing $APPCAST_NAME"
APPCAST="$ASSETS/$APPCAST_NAME"
build_appcast "$NOTES" "$METADATA" "$APPCAST"
rm -rf "$ASSETS/appcast-work"

if [ "$CREATE_RELEASE" = 0 ]; then
    log "Done (--no-release): artefacts are in $ASSETS"
    ls -l "$ASSETS"
    exit 0
fi

# --- Publish ---------------------------------------------------------------

log "Tagging $VERSION"
if [ "$TAG_EXISTS" = 0 ]; then
    git tag -a "$VERSION" -m "$APP_NAME $VERSION" "$HEAD_SHA"
fi
git push origin "refs/tags/$VERSION"

log "Creating GitHub release"
release_args=(--verify-tag --title "$APP_NAME $VERSION" --notes-file "$NOTES")
[ "$PUBLISH" = 1 ] || release_args+=(--draft)
[ "$PRERELEASE" = 0 ] || release_args+=(--prerelease)
RELEASE_URL="$(gh release create "$VERSION" "${release_args[@]}" "$ZIP" ${DELTA_ASSETS[@]+"${DELTA_ASSETS[@]}"} "$METADATA" "$APPCAST" "$NOTES")"

echo "$RELEASE_URL"
if [ "$PUBLISH" = 1 ]; then
    echo "Published. The appcast workflow will now put $APPCAST_NAME live."
else
    echo "Created as a draft. Review it, then publish it to put the appcast live:"
    echo "  gh release edit $VERSION --draft=false"
    echo "If you change its notes first, re-sign the appcast before publishing:"
    echo "  $0 --update-appcast $VERSION"
fi
