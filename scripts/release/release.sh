#!/bin/bash
#
# Build, notarise and publish a Hammerspoon 2 release, in two phases.
#
#   scripts/release/release.sh prepare [--notes-file FILE] [--since TAG] [--edit-notes] [--channel NAME] <version>
#   scripts/release/release.sh execute [--dry-run] [--yes] <version>
#
# or build a signed, notarised copy of the app for local testing, from main
# with pull requests merged in, with
#
#   scripts/release/release.sh local [--pr NUMBER]... [--base REF] [--install | --install-to DIR]
#
# It's signed with the same Developer ID and bundle identifier as releases, so
# macOS carries the permissions you've granted (Accessibility and so on) over
# to it, which it doesn't for Xcode's builds. It builds in a temporary worktree
# (so uncommitted changes aren't included), and leaves the app and its
# archive (for symbolicating crashes) in build/release/local/<label>.<time>.<pid>,
# removing earlier builds of the same pull requests once it's done. It needs
# the Developer ID certificate and notarytool profile, but not the Sparkle key.
#
# prepare changes nothing outside build/release/<version>. Once it has checked
# that <version> is unused and that every tool, key and permission both phases
# need is in place, it:
#
#   1. archives the Release scheme from HEAD with MARKETING_VERSION=<version>
#      and CURRENT_PROJECT_VERSION=<commit count>, so Sparkle's build numbers
#      only ever go up
#   2. exports it signed with Developer ID, notarises it and staples it
#   3. zips it and signs the zip with the Sparkle EdDSA key, and zips the
#      archive's dSYMs (checking every executable of ours has one) so crash
#      reports from the release can be symbolicated
#   4. builds signed binary deltas against the previous releases that this
#      script published, and writes sparkle.json to describe all of the above
#   5. writes a changelog from the Changelog-Added/Changed/Fixed trailers in
#      the commits since the last release (see scripts/release/changelog.js),
#      or takes yours from --notes-file
#   6. adds the release to the live appcast.xml and signs the feed, so Sparkle
#      (with SURequireSignedFeed) can tell it hasn't been tampered with
#
# and leaves the results in build/release/<version>/prepared for review:
#
#   assets/            everything to attach to the GitHub release
#   release-notes.md   the release's description, also signed into the appcast
#   appcast.xml        the signed feed to put on gh-pages
#   manifest.json      checksums and state that execute checks against
#
# If you edit release-notes.md, re-sign the appcast to match with
#
#   scripts/release/release.sh appcast <version>
#
# which also rebuilds it on top of any release that has gone live since.
#
# execute publishes exactly what prepare left, after checking it's unchanged
# and still current. It:
#
#   1. tags the release's commit and pushes the tag
#   2. creates the GitHub release with the notes and assets (as a draft until
#      every asset is uploaded and checked) and publishes it
#   3. commits appcast.xml to gh-pages and pushes it
#   4. deploys www.hammerspoon.org (deploy.yml in $SITE_REPO, which serves
#      gh-pages at /2/) and checks the feed it serves is the new one
#   5. commits the new version and sha256 to the Homebrew cask in $TAP_REPO,
#      unless --channel kept the release out of the default Sparkle channel
#   6. commits the version to MARKETING_VERSION in the project file on main and
#      pushes it (bypassing main's ruleset, so you must be allowed to), so
#      builds from source report the last release they include; Spoons'
#      minimumVersion is checked against it. This is skipped if main doesn't
#      include the release's commit, or already has a newer release's version.
#
# Each step checks whether it's already done, so if execute stops partway, fix
# the problem and run it again to carry on. `execute --dry-run` shows what's
# done and what's left.
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
#     `scripts/release/release.sh sparkle-bin` to find it.
#   - gh, authenticated with permission to push to the repository.
#   - node (already needed to build the docs) and jq (part of macOS).
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
# The website, which serves gh-pages at /2/, and the workflow that deploys it.
SITE_REPO="Hammerspoon/hammerspoon.github.io"
PAGES_WORKFLOW="deploy.yml"
# The Homebrew tap (brew install --cask hammerspoon/tap/hammerspoon2).
TAP_REPO="Hammerspoon/homebrew-tap"
CASK_PATH="Casks/hammerspoon2.rb"
# The branch releases come from, whose project file records the last release.
MAIN_BRANCH="main"
PBXPROJ_PATH="Hammerspoon 2.xcodeproj/project.pbxproj"

NOTARY_PROFILE="${NOTARY_PROFILE:-hammerspoon2-notary}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"
DELTA_COUNT="${DELTA_COUNT:-3}"

usage() {
    cat <<EOF
Usage: $(basename "$0") prepare [--notes-file FILE] [--since TAG] [--edit-notes] [--channel NAME] <version>
       $(basename "$0") appcast <version>
       $(basename "$0") execute [--dry-run] [--yes] <version>
       $(basename "$0") local [--pr NUMBER]... [--base REF] [--install | --install-to DIR]
       $(basename "$0") sparkle-bin

Commands:
  prepare      Check everything is ready, then build, notarise and sign the
               release, its changelog and its appcast into
               build/release/<version>/prepared. Changes nothing else.
  appcast      Rebuild and re-sign the prepared appcast, after editing
               release-notes.md or when another release has gone live since.
  execute      Tag, push, create the GitHub release, put the appcast live and
               update the Homebrew cask, from what prepare left. Run it again
               to resume if it stops.
  local        Build a signed, notarised app for local testing from --base
               with the given pull requests merged in, into
               build/release/local/. Being signed like a release, it
               keeps the permissions you've granted to Hammerspoon 2.
  sparkle-bin  Print the directory holding Sparkle's command line tools
               (generate_keys, sign_update, ...).

Options:
  --notes-file FILE  (prepare) Use FILE (markdown) as the release notes instead
                     of a changelog generated from commit message trailers.
  --since TAG        (prepare) Build the changelog from the commits since TAG,
                     instead of since the latest published release that HEAD
                     contains.
  --edit-notes       (prepare) Open the release notes in \$EDITOR before
                     they're signed into the appcast.
  --channel NAME     (prepare) Put the release in Sparkle channel NAME (e.g.
                     beta), which only installs that opt in to it are offered.
                     The app doesn't opt in to any channel yet, so a release
                     in one reaches nobody through Sparkle.
  --dry-run          (execute) Run the checks and show what's done and what's
                     left, without changing anything.
  --yes              (execute) Don't ask for confirmation.
  --pr NUMBER        (local) Merge pull request NUMBER into the build. Give it
                     more than once to merge several, in order.
  --base REF         (local) Build from REF instead of origin/main (fetched
                     first), e.g. HEAD for this checkout's last commit.
  --install          (local) Quit Hammerspoon 2 if it's running, replace
                     /Applications/Hammerspoon 2.app with the build and open it.
  --install-to DIR   (local) Like --install, but into DIR.
  -h, --help         Show this help.

<version> is a tag name like 0.0.15 or 1.0.0-beta.1. Versions with a suffix
become GitHub prereleases titled like "1.0.0 Beta 1", but are offered to
every install, like any other release, unless --channel says otherwise.
EOF
}

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

COMMAND="${1:-}"
[ $# -eq 0 ] || shift
NOTES_FILE=""
SINCE_TAG=""
EDIT_NOTES=0
CHANNEL=""
DRY_RUN=0
ASSUME_YES=0
LOCAL_PRS=()
LOCAL_BASE="origin/main"
INSTALL_DIR=""
VERSION=""
while [ $# -gt 0 ]; do
    case "$COMMAND:$1" in
        prepare:--notes-file) NOTES_FILE="${2:?--notes-file needs a path}"; shift ;;
        prepare:--since) SINCE_TAG="${2:?--since needs a tag}"; shift ;;
        prepare:--edit-notes) EDIT_NOTES=1 ;;
        prepare:--channel) CHANNEL="${2:?--channel needs a name}"; shift ;;
        execute:--dry-run) DRY_RUN=1 ;;
        execute:--yes) ASSUME_YES=1 ;;
        local:--pr) LOCAL_PRS+=("${2:?--pr needs a pull request number}"); shift ;;
        local:--base) LOCAL_BASE="${2:?--base needs a git ref}"; shift ;;
        local:--install) INSTALL_DIR="/Applications" ;;
        local:--install-to) INSTALL_DIR="${2:?--install-to needs a directory}"; shift ;;
        *:-h|*:--help) usage; exit 0 ;;
        *:-*) usage >&2; die "unknown option for '$COMMAND': $1" ;;
        local:*) usage >&2; die "local takes no version: $1" ;;
        *) [ -z "$VERSION" ] || die "only one version may be given"; VERSION="$1" ;;
    esac
    shift
done

WORK_ROOT="$REPO_ROOT/build/release"
PACKAGES_DIR="$WORK_ROOT/SourcePackages"
SPARKLE_BIN="$PACKAGES_DIR/artifacts/sparkle/Sparkle/bin"

cd "$REPO_ROOT"

# --- Helpers ----------------------------------------------------------------

require_tools() {
    for tool in "$@"; do
        command -v "$tool" >/dev/null || die "$tool is required"
    done
}

resolve_packages() {
    # Resolving into a known directory gives us Sparkle's tools from the same
    # Sparkle version that gets linked into the app.
    xcodebuild -resolvePackageDependencies \
        -project "$PROJECT" -scheme "$SCHEME" \
        -clonedSourcePackagesDirPath "$PACKAGES_DIR" >/dev/null
    [ -x "$SPARKLE_BIN/sign_update" ] || die "Sparkle tools not found in $SPARKLE_BIN"
}

# Check gh can do everything execute needs, and the workflow it runs exists.
check_github() {
    gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
    GH_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
    [ "$(gh api "repos/$GH_REPO" --jq .permissions.push)" = "true" ] \
        || die "your GitHub account can't push to $GH_REPO, so it can't tag or release"
    gh workflow view -R "$SITE_REPO" "$PAGES_WORKFLOW" >/dev/null 2>&1 \
        || die "$PAGES_WORKFLOW isn't on $SITE_REPO's default branch, and execute needs it to deploy the appcast"
    [ "$(gh api "repos/$SITE_REPO" --jq .permissions.push)" = "true" ] \
        || die "your GitHub account can't run workflows in $SITE_REPO, so it can't deploy the appcast"
    [ "$(gh api "repos/$TAP_REPO" --jq .permissions.push)" = "true" ] \
        || die "your GitHub account can't push to $TAP_REPO, so it can't update the Homebrew cask"
}

# Check the Sparkle signing key is in the keychain and matches the app's.
check_sparkle_key() {
    PLIST_KEY="$(plutil -extract SUPublicEDKey raw "$INFO_PLIST" 2>/dev/null || true)"
    [ -n "$PLIST_KEY" ] || die "SUPublicEDKey is missing from $INFO_PLIST; run $SPARKLE_BIN/generate_keys and add the key it prints"
    for key in SURequireSignedFeed SUVerifyUpdateBeforeExtraction; do
        [ "$(plutil -extract "$key" raw "$INFO_PLIST" 2>/dev/null || true)" = "true" ] \
            || die "$INFO_PLIST must set $key to true (<key>$key</key><true/>)"
    done
    # This may ask for permission to read the key from your keychain.
    local keychain_key
    keychain_key="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -p 2>/dev/null || true)"
    [ -n "$keychain_key" ] || die "no Sparkle signing key for account '$SPARKLE_KEY_ACCOUNT' in your keychain"
    [ "$PLIST_KEY" = "$keychain_key" ] || die "SUPublicEDKey in Info.plist does not match the Sparkle key in your keychain"
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# check_dsyms <app> <dSYMs directory>
#
# Check every executable we build into <app> (everything but its frameworks)
# has a dSYM with a matching UUID for each of its architectures, or crashes in
# it couldn't be symbolicated.
check_dsyms() {
    local app="$1" dsyms="$2" known file uuid missing=""
    [ -d "$dsyms" ] || die "the archive has no dSYMs; is DEBUG_INFORMATION_FORMAT dwarf-with-dsym for Release?"
    known="$(find "$dsyms" -path '*.dSYM/Contents/Resources/DWARF/*' -type f -print0 \
        | xargs -0 xcrun dwarfdump --uuid | awk '/^UUID:/ { print $2 }')"
    while IFS= read -r -d '' file; do
        file -b "$file" | grep -q 'Mach-O' || continue
        for uuid in $(xcrun dwarfdump --uuid "$file" | awk '/^UUID:/ { print $2 }'); do
            grep -qx "$uuid" <<<"$known" || missing+=" ${file#"$app"/} ($uuid)"
        done
    done < <(find "$app" -type f -perm +111 -not -path '*/Frameworks/*' -print0)
    [ -z "$missing" ] || die "no dSYM matches:$missing"
}

# fetch_live_appcast <output>
#
# Write the appcast on gh-pages (which is what Pages serves) to <output>, or
# an empty file if there isn't one yet.
fetch_live_appcast() {
    local status=0
    git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1 || status=$?
    if [ "$status" = 2 ]; then
        : > "$1"
        return
    fi
    [ "$status" = 0 ] || die "couldn't reach origin to read the live appcast"
    git fetch --quiet origin gh-pages
    if git cat-file -e "origin/gh-pages:$APPCAST_NAME" 2>/dev/null; then
        git show "origin/gh-pages:$APPCAST_NAME" > "$1"
    else
        : > "$1"
    fi
}

# check_build_is_newest <build> <appcast>
#
# Sparkle compares CFBundleVersion, so a build that isn't newer than every
# other release in the feed would never be offered.
check_build_is_newest() {
    local newest
    newest="$(sed -n 's:.*<sparkle\:version>\([0-9][0-9]*\)</sparkle\:version>.*:\1:p' "$2" \
        | { grep -vx "$1" || true; } | sort -n | tail -1)"
    if [ -n "$newest" ] && [ "$1" -le "$newest" ]; then
        die "build $1 is not newer than build $newest in the live appcast, so Sparkle would ignore it"
    fi
}

# Set PREVIOUS_RELEASE_TAG to the newest published release whose tag HEAD
# contains, or nothing if there isn't one. The changelog covers the commits
# since it. Not a $(...) function, so a failed lookup stops the script
# instead of looking like there's no earlier release.
previous_release_tag() {
    local tags tag
    tags="$(gh release list --exclude-drafts --limit 100 --json tagName,createdAt \
        --jq 'sort_by(.createdAt) | reverse | .[].tagName')" \
        || die "couldn't list the GitHub releases to find the previous one (use --since TAG to name it)"
    PREVIOUS_RELEASE_TAG=""
    while read -r tag; do
        [ -n "$tag" ] || continue
        if git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null \
            && git merge-base --is-ancestor "$tag" HEAD; then
            PREVIOUS_RELEASE_TAG="$tag"
            return
        fi
    done <<<"$tags"
}

# The commit the tag points at on origin, or nothing if it isn't there.
remote_tag_commit() {
    # An annotated tag is followed by its peeled ("^{}") commit.
    git ls-remote --tags origin "refs/tags/$VERSION" "refs/tags/$VERSION^{}" | awk '{ print $1 }' | tail -1
}

# Check every asset in the manifest is unchanged since prepare made it.
verify_assets() {
    local name sha
    while IFS=$'\t' read -r name sha; do
        [ -f "$ASSETS/$name" ] || die "$name is missing from $ASSETS; run prepare again"
        [ "$(sha256_of "$ASSETS/$name")" = "$sha" ] || die "$name has changed since prepare made it; run prepare again"
    done < <(jq -r '.assets[] | "\(.name)\t\(.sha256)"' "$MANIFEST")
}

# build_appcast [pub date]
#
# Add the prepared release to the appcast currently on gh-pages, with the
# prepared notes as its description, sign it, and record in the manifest what
# was signed and what it was built on.
build_appcast() {
    local pub_date="${1:-}" scratch="$WORK/appcast-work" build
    rm -rf "$scratch"
    mkdir -p "$scratch"
    build="$(jq -r .build "$METADATA")"

    if [ -n "$(tr -d '[:space:]' < "$NOTES")" ]; then
        gh api markdown -f mode=gfm -f context="$GH_REPO" -F text=@"$NOTES" > "$scratch/notes.html"
    else
        : > "$scratch/notes.html"
    fi

    # Start from the live feed, so every earlier release stays in it.
    fetch_live_appcast "$scratch/live.xml"
    # A release that's already live keeps its place; a new one must be newest.
    if ! grep -q "<sparkle:version>$build</sparkle:version>" "$scratch/live.xml"; then
        check_build_is_newest "$build" "$scratch/live.xml"
    fi
    cp "$scratch/live.xml" "$APPCAST"

    node "$REPO_ROOT/scripts/release/update-appcast.js" \
        --appcast "$APPCAST" \
        --metadata "$METADATA" \
        --notes-html "$scratch/notes.html" \
        --download-prefix "https://github.com/$GH_REPO/releases/download/$VERSION/" \
        --release-url "https://github.com/$GH_REPO/releases/tag/$VERSION" \
        ${pub_date:+--pub-date "$pub_date"}

    "$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" "$APPCAST" >/dev/null
    "$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$APPCAST" \
        || die "the signed $APPCAST_NAME failed verification"

    node "$REPO_ROOT/scripts/release/check-appcast.js" \
        --candidate "$APPCAST" \
        --live "$scratch/live.xml" \
        --metadata "$METADATA" \
        --signed-notes "$NOTES" \
        --release-notes "$NOTES"

    jq --arg notes "$(sha256_of "$NOTES")" \
        --arg appcast "$(sha256_of "$APPCAST")" \
        --arg live "$(sha256_of "$scratch/live.xml")" \
        '.notesSha256 = $notes | .appcastSha256 = $appcast | .liveAppcastSha256 = $live' \
        "$MANIFEST" > "$scratch/manifest.json"
    mv "$scratch/manifest.json" "$MANIFEST"
    rm -rf "$scratch"
}

# build_notarised_app <project> <work dir> <version> <build>
#
# Archive the Release scheme of <project> as <work dir>/$APP_NAME.xcarchive
# with the given version and build number, export it signed with Developer ID
# to <work dir>/export/$APP_NAME.app, check it, then notarise and staple it.
build_notarised_app() {
    local project="$1" work="$2" version="$3" build="$4"
    local archive="$work/$APP_NAME.xcarchive"
    local export_dir="$work/export"
    local app="$export_dir/$APP_NAME.app"

    log "Archiving"
    xcodebuild archive \
        -project "$project" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$archive" \
        -clonedSourcePackagesDirPath "$PACKAGES_DIR" \
        -skipPackagePluginValidation \
        MARKETING_VERSION="$version" \
        CURRENT_PROJECT_VERSION="$build" \
        > "$work/archive.log" 2>&1 \
        || { tail -40 "$work/archive.log"; die "archive failed, full log in $work/archive.log"; }

    log "Exporting with Developer ID"
    cat > "$work/ExportOptions.plist" <<EOF
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
        -archivePath "$archive" \
        -exportOptionsPlist "$work/ExportOptions.plist" \
        -exportPath "$export_dir" \
        > "$work/export.log" 2>&1 \
        || { tail -40 "$work/export.log"; die "export failed, full log in $work/export.log"; }
    [ -d "$app" ] || die "export did not produce $app"

    log "Checking the exported app"
    local app_plist="$app/Contents/Info.plist"
    [ "$(plutil -extract CFBundleShortVersionString raw "$app_plist")" = "$version" ] || die "app has the wrong CFBundleShortVersionString"
    [ "$(plutil -extract CFBundleVersion raw "$app_plist")" = "$build" ] || die "app has the wrong CFBundleVersion"
    [ -z "${PLIST_KEY:-}" ] || [ "$(plutil -extract SUPublicEDKey raw "$app_plist")" = "$PLIST_KEY" ] || die "app is missing SUPublicEDKey"
    # The app compares its build number with the IPC broker's to spot a broker left running across
    # an update, and hs2 compares with the app's, so every binary we ship must carry the same one.
    # The command line tools have their Info.plist embedded in a __TEXT,__info_plist section.
    local helper_plist="$app/Contents/XPCServices/HammerspoonOSAScriptHelper.xpc/Contents/Info.plist"
    [ "$(plutil -extract CFBundleVersion raw "$helper_plist")" = "$build" ] || die "HammerspoonOSAScriptHelper has the wrong CFBundleVersion"
    local tool
    for tool in HammerspoonIPCBroker hs2; do
        [ "$(xcrun otool -X -s __TEXT __info_plist -v "$app/Contents/MacOS/$tool" | plutil -extract CFBundleVersion raw -)" = "$build" ] \
            || die "$tool has the wrong CFBundleVersion"
    done
    codesign --verify --deep --strict "$app"
    local signature_info
    signature_info="$(codesign -dvv "$app" 2>&1)"
    grep -q "^Authority=Developer ID Application: .*($TEAM_ID)" <<<"$signature_info" || die "app is not signed with a Developer ID for $TEAM_ID"
    grep -q "flags=.*runtime" <<<"$signature_info" || die "app is not signed with the hardened runtime"

    log "Notarising (this usually takes a few minutes)"
    local notary_zip="$work/notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$notary_zip"
    xcrun notarytool submit "$notary_zip" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --output-format plist > "$work/notarytool.plist" \
        || true
    local notary_status notary_id
    notary_status="$(plutil -extract status raw "$work/notarytool.plist" 2>/dev/null || echo unknown)"
    notary_id="$(plutil -extract id raw "$work/notarytool.plist" 2>/dev/null || true)"
    if [ "$notary_status" != "Accepted" ]; then
        if [ -n "$notary_id" ]; then
            xcrun notarytool log "$notary_id" --keychain-profile "$NOTARY_PROFILE" "$work/notarytool-log.json" || true
            cat "$work/notarytool-log.json" 2>/dev/null || true
        fi
        die "notarisation finished with status '$notary_status'"
    fi
    rm -f "$notary_zip"

    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute -vv "$app"
}

# --- prepare ----------------------------------------------------------------

cmd_prepare() {
    if [ -n "$NOTES_FILE" ]; then
        [ -f "$NOTES_FILE" ] || die "notes file not found: $NOTES_FILE"
        NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"
    fi
    [ -z "$NOTES_FILE" ] || [ -z "$SINCE_TAG" ] || die "--since has no effect with --notes-file"
    [ -z "$CHANNEL" ] || [[ "$CHANNEL" =~ ^[a-z0-9-]+$ ]] || die "channel names are lower case letters, digits and dashes, got '$CHANNEL'"

    log "Preflight checks"
    require_tools xcodebuild xcrun ditto plutil codesign spctl gh git node jq shasum curl file
    check_github

    [ -z "$(git status --porcelain)" ] || die "working tree is not clean"
    git fetch --quiet origin
    HEAD_SHA="$(git rev-parse HEAD)"
    [ -n "$(git branch -r --contains "$HEAD_SHA")" ] || die "HEAD ($HEAD_SHA) has not been pushed to origin"

    git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null && die "tag $VERSION already exists locally"
    [ -z "$(remote_tag_commit)" ] || die "tag $VERSION already exists on origin"
    gh release view "$VERSION" >/dev/null 2>&1 && die "a GitHub release for $VERSION already exists"

    # The build number is the number of commits leading up to the release,
    # which only goes up for as long as releases come from one line of
    # history. These make sure it's complete and unique.
    [ "$(git rev-parse --is-shallow-repository)" = "false" ] \
        || die "this is a shallow clone, so the commit count used as the build number would be too low (run: git fetch --unshallow)"
    git fetch --quiet --tags origin
    for other_tag in $(git tag --points-at HEAD); do
        gh release view "$other_tag" >/dev/null 2>&1 \
            && die "HEAD is already released as $other_tag, and a second release from the same commit would reuse its build number"
    done
    BUILD_NUMBER="$(git rev-list --count HEAD)"
    if [ -n "$SINCE_TAG" ]; then
        git rev-parse -q --verify "refs/tags/$SINCE_TAG^{commit}" >/dev/null || die "--since: no tag $SINCE_TAG"
        git merge-base --is-ancestor "$SINCE_TAG" HEAD || die "--since: $SINCE_TAG isn't an ancestor of HEAD"
    fi
    mkdir -p "$WORK_ROOT"
    fetch_live_appcast "$WORK_ROOT/live-$VERSION.xml"
    check_build_is_newest "$BUILD_NUMBER" "$WORK_ROOT/live-$VERSION.xml"
    rm -f "$WORK_ROOT/live-$VERSION.xml"

    resolve_packages
    check_sparkle_key
    FEED_URL="$(plutil -extract SUFeedURL raw "$INFO_PLIST")"

    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "notarytool profile '$NOTARY_PROFILE' is missing or invalid (see the setup notes at the top of $0)"

    rm -rf "$WORK"
    mkdir -p "$ASSETS"
    local archive="$WORK/$APP_NAME.xcarchive"
    local export_dir="$WORK/export"
    local app="$export_dir/$APP_NAME.app"
    local zip_name="$ASSET_BASENAME-$VERSION.zip"
    local zip="$ASSETS/$zip_name"
    local dsyms_zip="$ASSETS/$ASSET_BASENAME-$VERSION-dSYMs.zip"

    echo "Version $VERSION, build $BUILD_NUMBER, commit $HEAD_SHA"
    echo "Working in $WORK"

    # --- Build --------------------------------------------------------------

    build_notarised_app "$PROJECT" "$WORK" "$VERSION" "$BUILD_NUMBER"
    local min_system_version
    min_system_version="$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")"

    # --- Sparkle artefacts --------------------------------------------------

    log "Packaging and signing $zip_name"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
    local zip_signature zip_length
    zip_signature="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" -p "$zip")"
    zip_length="$(stat -f%z "$zip")"

    log "Packaging dSYMs"
    check_dsyms "$app" "$archive/dSYMs"
    ditto -c -k --keepParent "$archive/dSYMs" "$dsyms_zip"

    log "Building deltas from up to $DELTA_COUNT previous releases"
    # Only releases made by this script carry sparkle.json, and only their build
    # numbers are guaranteed to be unique, so those are the ones we diff against.
    local deltas_json="" delta_count=0 previous_dir="$WORK/previous"
    local previous_tag previous_tags=() assets previous_work previous_zip_name previous_app
    local previous_build delta_name delta applied delta_signature delta_length
    mkdir -p "$previous_dir"
    while read -r previous_tag; do
        [ -z "$previous_tag" ] || previous_tags+=("$previous_tag")
    done < <(gh release list --exclude-drafts --limit 30 --json tagName --jq '.[].tagName')
    for previous_tag in ${previous_tags[@]+"${previous_tags[@]}"}; do
        [ "$delta_count" -lt "$DELTA_COUNT" ] || break

        assets="$(gh release view "$previous_tag" --json assets --jq '.assets[].name')"
        grep -qx "$METADATA_NAME" <<<"$assets" || continue

        previous_work="$previous_dir/$previous_tag"
        mkdir -p "$previous_work"
        gh release download "$previous_tag" --pattern "$METADATA_NAME" --dir "$previous_work"
        previous_zip_name="$(jq -r .archive.name "$previous_work/$METADATA_NAME")"
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
        "$SPARKLE_BIN/BinaryDelta" create "$previous_app" "$app" "$delta"

        # Prove the delta reproduces a correctly signed copy of the new app
        # before shipping it.
        applied="$previous_work/applied/$APP_NAME.app"
        mkdir -p "$(dirname "$applied")"
        "$SPARKLE_BIN/BinaryDelta" apply "$previous_app" "$applied" "$delta"
        codesign --verify --deep --strict "$applied" || die "applying $delta_name produced an app that fails code signing checks"

        delta_signature="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" -p "$delta")"
        delta_length="$(stat -f%z "$delta")"
        [ -z "$deltas_json" ] || deltas_json+=","
        deltas_json+="
    { \"from\": \"$previous_build\", \"name\": \"$delta_name\", \"length\": $delta_length, \"edSignature\": \"$delta_signature\" }"
        delta_count=$((delta_count + 1))
    done
    [ "$delta_count" -gt 0 ] || echo "  no earlier releases with $METADATA_NAME, so no deltas this time"

    # Prereleases go in the default channel too, unless --channel says
    # otherwise (see releaseKind in update-appcast.js).
    local kind channel channel_json="" prerelease
    kind="$(node -p 'JSON.stringify(require(process.argv[1]).releaseKind(process.argv[2], process.argv[3]))' \
        "$REPO_ROOT/scripts/release/update-appcast.js" "$VERSION" "$CHANNEL")"
    prerelease="$(jq -r .prerelease <<<"$kind")"
    channel="$(jq -r '.channel // ""' <<<"$kind")"
    if [ -n "$channel" ]; then
        channel_json="
  \"channel\": \"$channel\","
    fi
    cat > "$METADATA" <<EOF
{
  "version": "$VERSION",${channel_json}
  "build": "$BUILD_NUMBER",
  "commit": "$HEAD_SHA",
  "minimumSystemVersion": "$min_system_version",
  "archive": { "name": "$zip_name", "length": $zip_length, "edSignature": "$zip_signature" },
  "deltas": [${deltas_json}
  ]
}
EOF
    jq empty "$METADATA" || die "generated $METADATA is not valid JSON"

    # Record what execute will publish, so it can tell if any of it changes.
    local asset
    for asset in "$ASSETS"/*; do
        jq -n --arg name "$(basename "$asset")" --arg sha256 "$(sha256_of "$asset")" \
            --argjson size "$(stat -f%z "$asset")" '{$name, $sha256, $size}'
    done | jq -s \
        --arg version "$VERSION" --arg build "$BUILD_NUMBER" --arg commit "$HEAD_SHA" \
        --argjson prerelease "$prerelease" --arg feedUrl "$FEED_URL" \
        '{$version, $build, $commit, $prerelease, $feedUrl, assets: .}' > "$MANIFEST"

    # --- Changelog and appcast ----------------------------------------------

    if [ -n "$NOTES_FILE" ]; then
        log "Using release notes from $NOTES_FILE"
        tr -d '\r' < "$NOTES_FILE" > "$NOTES"
    else
        local since="$SINCE_TAG"
        if [ -z "$since" ]; then
            previous_release_tag
            since="$PREVIOUS_RELEASE_TAG"
        fi
        local since_args=()
        if [ -n "$since" ]; then
            log "Constructing a changelog from commit trailers since $since"
            since_args=(--from "$since")
        else
            log "Constructing a changelog from commit trailers in all of history (no earlier release)"
        fi
        node "$REPO_ROOT/scripts/release/changelog.js" notes ${since_args[@]+"${since_args[@]}"} \
            --to "$HEAD_SHA" --repo "$GH_REPO" --version "$VERSION" > "$NOTES"
        if grep -qx 'No user-facing changes.' "$NOTES"; then
            warn "no commits since ${since:-the beginning} have Changelog-* trailers; consider --edit-notes or --notes-file"
        fi
    fi
    if [ "$EDIT_NOTES" = 1 ]; then
        ${EDITOR:-vi} "$NOTES"
    fi

    log "Building and signing $APPCAST_NAME"
    build_appcast

    log "Prepared $VERSION (build $BUILD_NUMBER) in $PREPARED"
    ls -l "$ASSETS"
    echo "----"
    cat "$NOTES"
    echo "----"
    echo "Review the release, then publish it with:"
    echo "  $0 execute $VERSION"
    echo "If you edit $NOTES_NAME, re-sign the appcast first with:"
    echo "  $0 appcast $VERSION"
}

# --- appcast ----------------------------------------------------------------

cmd_appcast() {
    [ -f "$MANIFEST" ] || die "$VERSION hasn't been prepared (no $MANIFEST)"
    require_tools xcodebuild plutil gh git node jq shasum
    check_github
    resolve_packages
    check_sparkle_key
    verify_assets

    # Keep the date a published release went live; otherwise it's now.
    local pub_date=""
    if [ "$(gh release view "$VERSION" --json isDraft --jq .isDraft 2>/dev/null || true)" = "false" ]; then
        pub_date="$(gh release view "$VERSION" --json publishedAt --jq .publishedAt)"
    fi

    log "Rebuilding and signing $APPCAST_NAME for $VERSION"
    build_appcast "$pub_date"
    echo "Updated $APPCAST. Review it, then publish it with:"
    echo "  $0 execute $VERSION"
}

# --- local ------------------------------------------------------------------

# local_cleanup: remove the temporary source worktree, if there is one.
local_cleanup() {
    if [ -n "${LOCAL_SRC:-}" ] && [ -d "$LOCAL_SRC" ]; then
        git worktree remove --force "$LOCAL_SRC" 2>/dev/null || rm -rf "$LOCAL_SRC"
        git worktree prune
    fi
    if [ -n "${LOCAL_INSTALL_LOCK:-}" ]; then
        rm -rf "$LOCAL_INSTALL_LOCK"
        LOCAL_INSTALL_LOCK=""
    fi
}

cmd_local() {
    local pr
    for pr in ${LOCAL_PRS[@]+"${LOCAL_PRS[@]}"}; do
        [[ "$pr" =~ ^[0-9]+$ ]] || die "--pr needs a pull request number, got '$pr'"
    done
    if [ -n "$INSTALL_DIR" ]; then
        [ -d "$INSTALL_DIR" ] || die "--install: no such directory: $INSTALL_DIR"
        INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
    fi

    log "Preflight checks"
    require_tools xcodebuild xcrun ditto plutil codesign spctl git node jq
    if [ ${#LOCAL_PRS[@]} -gt 0 ]; then
        require_tools gh
        gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
    fi
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "notarytool profile '$NOTARY_PROFILE' is missing or invalid (see the setup notes at the top of $0)"

    git fetch --quiet origin
    local base_sha
    base_sha="$(git rev-parse -q --verify "$LOCAL_BASE^{commit}")" || die "--base: no commit $LOCAL_BASE"

    local label=""
    for pr in ${LOCAL_PRS[@]+"${LOCAL_PRS[@]}"}; do
        label+="${label:+-}pr$pr"
    done
    [ -n "$label" ] || label="$(git rev-parse --short "$base_sha")"
    # Each run gets a directory of its own, so runs at the same time can't
    # touch each other's files. Its pid marks it as in use until it's done.
    mkdir -p "$WORK_ROOT/local"
    local work="$WORK_ROOT/local/$label.$(date +%Y%m%d-%H%M%S).$$"
    mkdir "$work" || die "couldn't create $work"
    echo $$ > "$work/.pid"
    trap local_cleanup EXIT

    # Build in a throwaway worktree, so neither this checkout nor its
    # uncommitted changes are touched or included.
    LOCAL_SRC="$work/src"
    git worktree add --quiet --detach "$LOCAL_SRC" "$base_sha"
    echo "Base: $LOCAL_BASE ($(git log -1 --format='%h %s' "$base_sha"))"

    local info
    for pr in ${LOCAL_PRS[@]+"${LOCAL_PRS[@]}"}; do
        info="$(gh pr view "$pr" --json number,title,state,headRefName \
            --jq '"#\(.number) \(.title) [\(.headRefName), \(.state | ascii_downcase)]"' 2>/dev/null)" \
            || die "couldn't find pull request #$pr"
        echo "Merging $info"
        git -C "$LOCAL_SRC" fetch --quiet origin "pull/$pr/head" || die "couldn't fetch pull request #$pr"
        if ! git -C "$LOCAL_SRC" merge --quiet --no-ff --no-edit -m "Merge pull request #$pr (local build)" FETCH_HEAD; then
            git -C "$LOCAL_SRC" merge --abort || true
            die "pull request #$pr doesn't merge cleanly onto $LOCAL_BASE${LOCAL_PRS[1]+ plus the pull requests before it}"
        fi
    done

    # Sparkle and the IPC broker compare build numbers, so use the same commit
    # count a release would. The version is only there to tell builds apart.
    local build version base_version
    [ "$(git rev-parse --is-shallow-repository)" = "false" ] \
        || warn "this is a shallow clone, so the build number will be too low"
    build="$(git -C "$LOCAL_SRC" rev-list --count HEAD)"
    base_version="$(git -C "$LOCAL_SRC" describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)"
    version="$base_version-local.${label//-/.}"
    echo "Version $version, build $build, commit $(git -C "$LOCAL_SRC" rev-parse --short HEAD)"
    echo "Working in $work"

    build_notarised_app "$LOCAL_SRC/$(basename "$PROJECT")" "$work" "$version" "$build"

    local app="$work/$APP_NAME.app"
    rm -rf "$app"
    ditto "$work/export/$APP_NAME.app" "$app"
    rm -rf "$work/export"
    local_cleanup
    LOCAL_SRC=""
    if [ -n "$INSTALL_DIR" ]; then
        local installed="$INSTALL_DIR/$APP_NAME.app" bundle_id
        bundle_id="$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")"
        log "Installing to $installed"
        # Two runs replacing the app at once could move one build inside the
        # other, so installs take turns. Installs are quick, so a lock that
        # doesn't go away was left by a run that died, and is for you to remove.
        local install_lock="$WORK_ROOT/local/install.lock" waited=0
        until mkdir "$install_lock" 2>/dev/null; do
            [ "$waited" -lt 120 ] || die "another install has held $install_lock for a minute; if none is running, remove it and run again"
            [ "$waited" -gt 0 ] || echo "Waiting for another install to finish"
            sleep 0.5
            waited=$((waited + 1))
        done
        LOCAL_INSTALL_LOCK="$install_lock"
        if pgrep -xq "$APP_NAME"; then
            echo "Quitting the running $APP_NAME"
            osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null || true
            waited=0
            while pgrep -xq "$APP_NAME"; do
                [ "$waited" -lt 20 ] || die "$APP_NAME didn't quit; quit it and run again, or copy $app yourself"
                sleep 0.5
                waited=$((waited + 1))
            done
        fi
        if [ -e "$installed" ]; then
            [ "$(plutil -extract CFBundleIdentifier raw "$installed/Contents/Info.plist" 2>/dev/null || true)" = "$bundle_id" ] \
                || die "$installed isn't $APP_NAME ($bundle_id), so it won't be replaced"
        fi
        # Copy beside the installed app first, so a failed copy leaves it alone.
        local incoming="$INSTALL_DIR/.$APP_NAME.app.new-$$" outgoing="$INSTALL_DIR/.$APP_NAME.app.old-$$"
        rm -rf "$incoming" "$outgoing"
        ditto "$app" "$incoming" || { rm -rf "$incoming"; die "couldn't copy the build to $INSTALL_DIR"; }
        if [ -e "$installed" ]; then
            mv "$installed" "$outgoing" || { rm -rf "$incoming"; die "couldn't move $installed aside"; }
        fi
        # mv would move it inside an app that's somehow still there.
        if [ -e "$installed" ] || ! mv "$incoming" "$installed"; then
            [ ! -e "$outgoing" ] || [ -e "$installed" ] || mv "$outgoing" "$installed"
            rm -rf "$incoming"
            die "couldn't move the build into $installed"
        fi
        rm -rf "$outgoing"
        open "$installed"
        rm -rf "$LOCAL_INSTALL_LOCK"
        LOCAL_INSTALL_LOCK=""
    fi

    # Only now, after any install, is this build finished with its files.
    : > "$work/.done"

    # Clear out earlier builds of the same pull requests that have finished,
    # or whose run has died, keeping only this one.
    local other other_pid
    for other in "$WORK_ROOT/local/$label".*; do
        [ -d "$other" ] && [ "$other" != "$work" ] || continue
        if [ ! -f "$other/.done" ]; then
            other_pid="$(cat "$other/.pid" 2>/dev/null || true)"
            [ -n "$other_pid" ] && ! kill -0 "$other_pid" 2>/dev/null || continue
        fi
        rm -rf "$other"
    done
    git worktree prune

    log "Built $version (build $build)"
    echo "App:     $app"
    echo "Archive: $work/$APP_NAME.xcarchive (for symbolicating crashes)"
    if [ -z "$INSTALL_DIR" ]; then
        echo "Install it with:"
        echo "  ditto \"$app\" \"/Applications/$APP_NAME.app\""
    fi
}

# --- execute ----------------------------------------------------------------

# Print the manifest's assets that the release in <release json> doesn't have
# exactly.
release_asset_mismatches() {
    local name sha size remote
    while IFS=$'\t' read -r name sha size; do
        remote="$(jq -r --arg name "$name" \
            '.assets[] | select(.name == $name and .state == "uploaded") | "\(.digest // "")\t\(.size)"' <<<"$1")"
        if [ "${remote%%$'\t'*}" = "sha256:$sha" ]; then
            continue
        fi
        # Fall back to the size if GitHub hasn't computed a digest.
        if [ "$remote" = $'\t'"$size" ]; then
            continue
        fi
        echo "$name"
    done < <(jq -r '.assets[] | "\(.name)\t\(.sha256)\t\(.size)"' "$MANIFEST")
}

# Whether the body in <release json> is the prepared notes, ignoring the CRLF
# line endings and trailing whitespace GitHub's editor adds.
release_notes_match() {
    jq -r --rawfile notes "$NOTES" \
        'def norm: gsub("\r"; "") | sub("^\\s+"; "") | sub("\\s+$"; "");
         (.body | norm) == ($notes | norm)' <<<"$1"
}

served_appcast_sha() {
    curl -fsSL -H 'Cache-Control: no-cache' "$FEED_URL?nocache=$(date +%s)" 2>/dev/null | shasum -a 256 | cut -d' ' -f1
}

step_tag() {
    log "Tagging $COMMIT as $VERSION"
    if ! git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
        git tag -a "$VERSION" -m "$APP_NAME $VERSION" "$COMMIT"
    fi
    git push origin "refs/tags/$VERSION"
}

step_release() {
    log "Creating the GitHub release"
    local release_json mismatches name
    if [ "$RELEASE_STATE" = absent ]; then
        local create_args=(--verify-tag --draft --title "$RELEASE_TITLE" --notes-file "$NOTES")
        [ "$PRERELEASE" = false ] || create_args+=(--prerelease)
        gh release create "$VERSION" "${create_args[@]}" >/dev/null
        RELEASE_STATE=draft
    fi

    if [ "$RELEASE_STATE" = draft ]; then
        # Upload whatever's missing or wrong (all of it, for a new release).
        release_json="$(gh release view "$VERSION" --json assets)"
        mismatches="$(release_asset_mismatches "$release_json")"
        for name in $mismatches; do
            echo "  uploading $name"
            gh release upload "$VERSION" "$ASSETS/$name" --clobber
        done
        release_json="$(gh release view "$VERSION" --json assets)"
        mismatches="$(release_asset_mismatches "$release_json")"
        [ -z "$mismatches" ] || die "these assets didn't upload correctly: $mismatches"

        gh release edit "$VERSION" --draft=false --prerelease="$PRERELEASE" \
            --title "$RELEASE_TITLE" --notes-file "$NOTES" >/dev/null
    elif [ "$NOTES_STATE" = differ ]; then
        echo "  updating the notes"
        gh release edit "$VERSION" --notes-file "$NOTES" >/dev/null
    fi
    gh release view "$VERSION" --json url --jq .url
}

step_appcast() {
    log "Putting $APPCAST_NAME on gh-pages"
    local live="$WORK/live.xml" body="$WORK/release-body.md"
    local index="$WORK/gh-pages.index" blob tree commit attempt checked=0
    # Pushing the tag starts publish-docs.yml, which replaces gh-pages with a
    # new commit (carrying the live appcast through), so gh-pages can move
    # between our fetch and our push. When it does, fetch it again, check the
    # appcast wasn't changed, and commit on top of the new gh-pages.
    for attempt in 1 2 3 4 5; do
        fetch_live_appcast "$live"
        case "$(sha256_of "$live")" in
            "$APPCAST_SHA") echo "  already there"; return ;;
            "$LIVE_SHA") ;;
            *) die "the appcast on gh-pages changed while execute was running; run: $0 appcast $VERSION" ;;
        esac
        git rev-parse -q --verify origin/gh-pages >/dev/null \
            || die "there's no gh-pages branch; publish the docs once to create it"

        if [ "$checked" = 0 ]; then
            gh release view "$VERSION" --json body --jq .body > "$body"
            node "$REPO_ROOT/scripts/release/check-appcast.js" \
                --candidate "$APPCAST" \
                --live "$live" \
                --metadata "$METADATA" \
                --signed-notes "$NOTES" \
                --release-notes "$body"
            checked=1
        fi

        # Commit on top of gh-pages without a checkout of the whole site.
        rm -f "$index"
        GIT_INDEX_FILE="$index" git read-tree origin/gh-pages
        blob="$(git hash-object -w "$APPCAST")"
        GIT_INDEX_FILE="$index" git update-index --add --cacheinfo "100644,$blob,$APPCAST_NAME"
        tree="$(GIT_INDEX_FILE="$index" git write-tree)"
        rm -f "$index"
        commit="$(git commit-tree "$tree" -p origin/gh-pages -m "appcast: publish $VERSION")"
        # Not forced, so a gh-pages that moved on is never overwritten.
        git push origin "$commit:refs/heads/gh-pages" && return
        [ "$attempt" -lt 5 ] || break
        warn "gh-pages changed while pushing (probably a docs run); trying again"
        sleep $((attempt * 10))
    done
    die "gh-pages kept changing; wait for https://github.com/$GH_REPO/actions/workflows/publish-docs.yml to finish, then run execute again"
}

step_deploy() {
    log "Deploying www.hammerspoon.org"
    local before run_id="" deadline
    before="$(gh run list -R "$SITE_REPO" --workflow "$PAGES_WORKFLOW" --limit 20 --json databaseId --jq '.[].databaseId')"
    gh workflow run -R "$SITE_REPO" "$PAGES_WORKFLOW" --ref "$(gh repo view "$SITE_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)"
    deadline=$((SECONDS + 120))
    while [ -z "$run_id" ]; do
        [ "$SECONDS" -lt "$deadline" ] || die "the Pages deploy didn't start; check https://github.com/$SITE_REPO/actions"
        sleep 5
        for id in $(gh run list -R "$SITE_REPO" --workflow "$PAGES_WORKFLOW" --limit 20 --json databaseId --jq '.[].databaseId'); do
            grep -qx "$id" <<<"$before" || { run_id="$id"; break; }
        done
    done
    echo "  https://github.com/$SITE_REPO/actions/runs/$run_id"
    gh run watch -R "$SITE_REPO" "$run_id" --exit-status --interval 10 >/dev/null \
        || die "the Pages deploy failed: https://github.com/$SITE_REPO/actions/runs/$run_id"

    # publish-docs.yml carries the newest appcast through when it rewrites
    # gh-pages, but check nothing else replaced it.
    fetch_live_appcast "$WORK/live.xml"
    [ "$(sha256_of "$WORK/live.xml")" = "$APPCAST_SHA" ] \
        || die "gh-pages lost the new appcast while deploying, probably to a docs run"

    echo "  waiting for $FEED_URL to serve it"
    deadline=$((SECONDS + 180))
    until [ "$(served_appcast_sha)" = "$APPCAST_SHA" ]; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            warn "Pages deployed, but $FEED_URL still serves the previous appcast. Its CDN caches for up to ten minutes; run execute again later to confirm."
            return
        fi
        sleep 15
    done
}

# Write the cask on $TAP_REPO's default branch to <output>, and print its blob
# sha, which the update has to name so it can't overwrite a newer commit.
fetch_cask() {
    local json
    json="$(gh api "repos/$TAP_REPO/contents/$CASK_PATH")"
    jq -r .content <<<"$json" | tr -d '\n' | base64 -D > "$1"
    jq -r .sha <<<"$json"
}

# Print the build number that <appcast> gives <version>, or nothing if it
# doesn't list it.
appcast_build_of() {
    awk -v version="$2" '
        /<sparkle:version>/ { build = $0; gsub(/.*<sparkle:version>|<\/sparkle:version>.*/, "", build) }
        /<sparkle:shortVersionString>/ {
            short = $0; gsub(/.*<sparkle:shortVersionString>|<\/sparkle:shortVersionString>.*/, "", short)
            if (short == version) { print build; exit }
        }' "$1"
}

# Whether <cask> already installs this release.
cask_is_current() {
    grep -qx "  version \"$VERSION\"" "$1" && grep -qx "  sha256 \"$ZIP_SHA\"" "$1"
}

step_cask() {
    log "Updating the Homebrew cask in $TAP_REPO"
    local cask="$WORK/cask.rb" updated="$WORK/cask-updated.rb" blob
    blob="$(fetch_cask "$cask")"
    if cask_is_current "$cask"; then
        echo "  already there"
        return
    fi
    sed -E \
        -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
        -e "s/^  sha256 \".*\"$/  sha256 \"$ZIP_SHA\"/" \
        "$cask" > "$updated"
    cask_is_current "$updated" || die "couldn't find the version and sha256 lines in $TAP_REPO's $CASK_PATH"
    gh api -X PUT "repos/$TAP_REPO/contents/$CASK_PATH" \
        -f message="hammerspoon2 $VERSION" \
        -f content="$(base64 -i "$updated")" \
        -f sha="$blob" \
        --jq .commit.html_url
}

# Print the distinct MARKETING_VERSIONs in the project file at <commit>, one
# per line.
project_version_of() {
    git show "$1:$PBXPROJ_PATH" \
        | sed -n -E 's/^[[:space:]]*MARKETING_VERSION = "?([^";]*)"?;$/\1/p' | sort -u
}

# Why main's project file at <commit> mustn't be given this release's version,
# if it mustn't: it doesn't include the release, or it has a newer release's
# version already (a release whose tagged commit has more commits behind it).
version_skip_reason() {
    local version
    git merge-base --is-ancestor "$COMMIT" "$1" || { echo "it doesn't include $COMMIT"; return; }
    version="$(project_version_of "$1")"
    [ "$(wc -l <<<"$version")" -eq 1 ] && [ "$version" != "$VERSION" ] || return 0
    git rev-parse -q --verify "refs/tags/$version^{commit}" >/dev/null || return 0
    [ "$(git rev-list --count "refs/tags/$version")" -le "$(jq -r .build "$MANIFEST")" ] \
        || echo "it has the newer $version"
}

step_version() {
    log "Setting the version on $MAIN_BRANCH to $VERSION"
    local index="$WORK/main.index" pbxproj="$WORK/project.pbxproj" value blob tree commit before attempt skip
    # Quoted only when it has to be, as Xcode writes it, so Xcode doesn't
    # rewrite the line the next time it saves the project.
    value="$VERSION"
    [[ "$VERSION" =~ ^[0-9.]+$ ]] || value="\"$VERSION\""
    for attempt in 1 2 3 4 5; do
        git fetch --quiet --tags origin "$MAIN_BRANCH"
        before="$(git rev-parse "origin/$MAIN_BRANCH")"
        if [ "$(project_version_of "$before")" = "$VERSION" ]; then
            echo "  already there"
            return
        fi
        # Checked again each time, since main (and its version) may have moved.
        skip="$(version_skip_reason "$before")"
        if [ -n "$skip" ]; then
            echo "  skipped: $skip"
            return
        fi
        git show "$before:$PBXPROJ_PATH" \
            | sed -E "s/^([[:space:]]*MARKETING_VERSION = ).*;\$/\1$value;/" > "$pbxproj"
        grep -q "MARKETING_VERSION = $value;" "$pbxproj" \
            || die "couldn't find MARKETING_VERSION in $PBXPROJ_PATH on $MAIN_BRANCH"

        # Commit on top of main without touching the working tree.
        rm -f "$index"
        GIT_INDEX_FILE="$index" git read-tree "$before"
        blob="$(git hash-object -w "$pbxproj")"
        GIT_INDEX_FILE="$index" git update-index --cacheinfo "100644,$blob,$PBXPROJ_PATH"
        tree="$(GIT_INDEX_FILE="$index" git write-tree)"
        rm -f "$index"
        commit="$(git commit-tree "$tree" -p "$before" -m "Set the version to $VERSION" \
            -m "Builds from source now report $VERSION, the last release they include.")"
        # Not forced, so commits that land on main meanwhile are never lost.
        git push origin "$commit:refs/heads/$MAIN_BRANCH" && return
        git fetch --quiet origin "$MAIN_BRANCH"
        [ "$(git rev-parse "origin/$MAIN_BRANCH")" != "$before" ] \
            || die "couldn't push to $MAIN_BRANCH; you need to be allowed to bypass its ruleset (or set MARKETING_VERSION to $VERSION in a pull request, then run execute again)"
        [ "$attempt" -lt 5 ] || break
        warn "$MAIN_BRANCH changed while pushing; trying again"
    done
    die "$MAIN_BRANCH kept changing; run execute again"
}

EXECUTING=0
on_exit() {
    local status=$?
    if [ "$status" -ne 0 ] && [ "$EXECUTING" = 1 ]; then
        printf '\nexecute stopped partway through. Once the problem above is fixed, run it again to carry on:\n  %s execute %s\n(Add --dry-run to see what is done and what is left.)\n' "$0" "$VERSION" >&2
    fi
}

cmd_execute() {
    [ -f "$MANIFEST" ] || die "$VERSION hasn't been prepared (no $MANIFEST); run: $0 prepare $VERSION"
    [ "$(jq -r .version "$MANIFEST")" = "$VERSION" ] || die "$MANIFEST is for a different version"

    log "Checking the prepared release"
    require_tools xcodebuild plutil gh git node jq shasum curl
    check_github
    resolve_packages

    COMMIT="$(jq -r .commit "$MANIFEST")"
    PRERELEASE="$(jq -r .prerelease "$MANIFEST")"
    # The same title as the appcast item, e.g. "Hammerspoon 2 1.0.0 Beta 1".
    RELEASE_TITLE="$APP_NAME $(node -p 'require(process.argv[1]).displayVersion(process.argv[2])' \
        "$REPO_ROOT/scripts/release/update-appcast.js" "$VERSION")"
    FEED_URL="$(jq -r .feedUrl "$MANIFEST")"
    APPCAST_SHA="$(jq -r '.appcastSha256 // ""' "$MANIFEST")"
    LIVE_SHA="$(jq -r '.liveAppcastSha256 // ""' "$MANIFEST")"
    [ -n "$APPCAST_SHA" ] || die "the appcast was never built; run: $0 appcast $VERSION"

    # Everything must be exactly what was prepared and reviewed.
    verify_assets
    [ -f "$NOTES" ] && [ "$(sha256_of "$NOTES")" = "$(jq -r .notesSha256 "$MANIFEST")" ] \
        || die "$NOTES_NAME has changed since the appcast was signed; run: $0 appcast $VERSION"
    [ -f "$APPCAST" ] && [ "$(sha256_of "$APPCAST")" = "$APPCAST_SHA" ] \
        || die "$APPCAST_NAME has changed since it was signed; run: $0 appcast $VERSION"
    "$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$APPCAST" \
        || die "$APPCAST_NAME's signature doesn't verify; run: $0 appcast $VERSION"

    # Work out which steps are already done, and that the rest still can be.
    git fetch --quiet origin
    [ -n "$(git branch -r --contains "$COMMIT" 2>/dev/null)" ] || die "commit $COMMIT is not on origin"

    local tag_state remote_commit
    remote_commit="$(remote_tag_commit)"
    if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
        [ "$(git rev-parse "$VERSION^{commit}")" = "$COMMIT" ] || die "local tag $VERSION doesn't point at $COMMIT"
    fi
    if [ -z "$remote_commit" ]; then
        tag_state="to do"
    elif [ "$remote_commit" = "$COMMIT" ]; then
        tag_state="done"
    else
        die "tag $VERSION on origin points at $remote_commit, not the prepared commit $COMMIT"
    fi

    local release_json="" release_state_text
    RELEASE_STATE=absent
    NOTES_STATE=match
    if release_json="$(gh release view "$VERSION" --json isDraft,body,assets 2>/dev/null)"; then
        if [ "$(jq -r .isDraft <<<"$release_json")" = "true" ]; then
            RELEASE_STATE=draft
        else
            RELEASE_STATE=published
            [ -z "$(release_asset_mismatches "$release_json")" ] \
                || die "the published $VERSION release's assets aren't the prepared ones; it must have been prepared again since"
            [ "$(release_notes_match "$release_json")" = "true" ] || NOTES_STATE=differ
        fi
    fi
    case "$RELEASE_STATE:$NOTES_STATE" in
        absent:*) release_state_text="to do" ;;
        draft:*) release_state_text="to finish (a draft exists)" ;;
        published:differ) release_state_text="done, but its notes need updating" ;;
        published:*) release_state_text="done" ;;
    esac

    local appcast_state live_sha
    fetch_live_appcast "$WORK/live.xml"
    live_sha="$(sha256_of "$WORK/live.xml")"
    if [ "$live_sha" = "$APPCAST_SHA" ]; then
        appcast_state="done"
    elif [ "$live_sha" = "$LIVE_SHA" ]; then
        appcast_state="to do"
    else
        die "the appcast on gh-pages has changed since yours was signed (another release?); rebuild it with: $0 appcast $VERSION"
    fi

    local deploy_state="to do"
    [ "$(served_appcast_sha)" != "$APPCAST_SHA" ] || deploy_state="done"

    # The cask follows the default Sparkle channel, so it skips releases that
    # --channel put somewhere else, and never goes back to an older release
    # (when execute runs again for one after a newer release has gone live).
    local cask_state="to do" cask_version cask_build
    ZIP_SHA="$(jq -r --arg name "$ASSET_BASENAME-$VERSION.zip" '.assets[] | select(.name == $name) | .sha256' "$MANIFEST")"
    [ -n "$ZIP_SHA" ] || die "$MANIFEST doesn't list $ASSET_BASENAME-$VERSION.zip"
    if [ -n "$(jq -r '.channel // ""' "$METADATA")" ]; then
        cask_state="skipped (not in the default channel)"
    else
        fetch_cask "$WORK/cask.rb" >/dev/null
        cask_version="$(sed -n -E 's/^  version "(.*)"$/\1/p' "$WORK/cask.rb")"
        cask_build="$(appcast_build_of "$WORK/live.xml" "$cask_version")"
        if cask_is_current "$WORK/cask.rb"; then
            cask_state="done"
        elif [ -n "$cask_build" ] && [ "$cask_build" -gt "$(jq -r .build "$MANIFEST")" ]; then
            cask_state="skipped (it has the newer $cask_version)"
        fi
    fi

    # main's project file follows the newest release that main includes, so it
    # never goes back to an older one (when execute runs again for one after a
    # newer release), or claims a release made from a branch main doesn't have.
    local version_state="to do" version_skip
    git fetch --quiet --tags origin
    if [ "$(project_version_of "origin/$MAIN_BRANCH")" = "$VERSION" ]; then
        version_state="done"
    else
        version_skip="$(version_skip_reason "origin/$MAIN_BRANCH")"
        [ -z "$version_skip" ] || version_state="skipped ($version_skip)"
    fi

    printf '\nRelease %s (build %s) from %s:\n' "$VERSION" "$(jq -r .build "$MANIFEST")" "$COMMIT"
    printf '  1. %-36s %s\n' "Tag $VERSION and push it:" "$tag_state"
    printf '  2. %-36s %s\n' "Publish the GitHub release:" "$release_state_text"
    printf '  3. %-36s %s\n' "Push $APPCAST_NAME to gh-pages:" "$appcast_state"
    printf '  4. %-36s %s\n' "Deploy Pages and check the feed:" "$deploy_state"
    printf '  5. %-36s %s\n' "Update the Homebrew cask:" "$cask_state"
    printf '  6. %-36s %s\n' "Set the version on $MAIN_BRANCH:" "$version_state"

    if [ "$tag_state:$release_state_text:$appcast_state:$deploy_state" = "done:done:done:done" ] \
        && [ "$cask_state" != "to do" ] && [ "$version_state" != "to do" ]; then
        echo "Nothing left to do."
        return
    fi
    [ "$DRY_RUN" = 0 ] || return 0
    if [ "$ASSUME_YES" = 0 ]; then
        [ -t 0 ] || die "not running interactively; pass --yes to go ahead without confirmation"
        local answer
        read -r -p "Go ahead? [y/N] " answer
        [[ "$answer" =~ ^[Yy] ]] || die "stopped"
    fi

    EXECUTING=1
    [ "$tag_state" = "done" ] || step_tag
    [ "$release_state_text" = "done" ] || step_release
    [ "$appcast_state" = "done" ] || step_appcast
    step_deploy
    [ "$cask_state" != "to do" ] || step_cask
    [ "$version_state" != "to do" ] || step_version
    EXECUTING=0

    log "Released $VERSION"
}

# --- Main -------------------------------------------------------------------

case "$COMMAND" in
    sparkle-bin)
        resolve_packages
        echo "$SPARKLE_BIN"
        exit 0
        ;;
    local)
        cmd_local
        exit 0
        ;;
    prepare|appcast|execute) ;;
    -h|--help) usage; exit 0 ;;
    "") usage >&2; exit 2 ;;
    *) usage >&2; die "unknown command: $COMMAND" ;;
esac

[ -n "$VERSION" ] || { usage >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "version must look like 1.2.3 or 1.2.3-beta.1, got '$VERSION'"

WORK="$WORK_ROOT/$VERSION"
PREPARED="$WORK/prepared"
ASSETS="$PREPARED/assets"
NOTES="$PREPARED/$NOTES_NAME"
APPCAST="$PREPARED/$APPCAST_NAME"
MANIFEST="$PREPARED/manifest.json"
METADATA="$ASSETS/$METADATA_NAME"

case "$COMMAND" in
    prepare) cmd_prepare ;;
    appcast) cmd_appcast ;;
    execute)
        trap on_exit EXIT
        cmd_execute
        ;;
esac
