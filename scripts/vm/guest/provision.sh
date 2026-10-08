#!/bin/bash
#
# Runs INSIDE the guest (as the auto-login "admin" user, via `tart exec`) to turn a
# Cirrus Labs macos-*-base image into the Hammerspoon 2 golden test image.
#
# Expects the host to have already streamed its Xcode into /Applications/Xcode.app (virtiofs
# shares can't be used for that: copying from one fails on thousands of SDK symlinks with ELOOP).
#
set -euo pipefail

APP_ID="net.tenshu.Hammerspoon-2"
HELPER_ID="net.tenshu.Hammerspoon-2.HammerspoonOSAScriptHelper"
SYSTEM_TCC="/Library/Application Support/com.apple.TCC/TCC.db"
step() { echo; echo "==> $*"; }

# macOS 27 moved the per-user TCC.db out of ~/Library into a tccd-owned container with a
# per-machine UUID; find it by its container metadata. Older layouts use ~/Library.
user_tcc_db() {
    local meta
    for meta in /private/var/containers/Data/ProtectedSystem/*/.com.apple.containermanagerd.metadata.plist; do
        [[ "$(sudo plutil -extract MCMMetadataIdentifier raw "$meta" 2>/dev/null)" == "com.apple.tccd" ]] || continue
        [[ "$(sudo plutil -extract MCMMetadataOwnership.uid raw "$meta" 2>/dev/null)" == "$(id -u)" ]] || continue
        echo "$(dirname "$meta")/Data/Library/Application Support/com.apple.TCC/TCC.db"
        return
    done
    echo "$HOME/Library/Application Support/com.apple.TCC/TCC.db"
}
USER_TCC="$(user_tcc_db)"

step "Disk"
# tart-guest-agent --run-daemon grows the APFS container to fill the (resized) disk at boot.
df -h /

step "Xcode"
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
sudo DevToolsSecurity -enable
xcodebuild -version

step "Spotlight"
# The base image disables indexing, but the hs.spotlight tests expect a working index.
sudo mdutil -a -i on

step "Quieten the desktop"
defaults -currentHost write com.apple.screensaver idleTime -int 0
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
# Crashing test hosts must not leave "quit unexpectedly" dialogs over the screen.
defaults write com.apple.CrashReporter DialogType -string none
# Desktop widgets and click-to-show-desktop interfere with window/mouse tests.
defaults write com.apple.WindowManager StandardHideWidgets -bool true
defaults write com.apple.WindowManager StageManagerHideWidgets -bool true
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false
defaults write com.apple.loginwindow TALLogoutSavesState -bool false
# (`softwareupdate --schedule off` is ignored on macOS 27 and keeps reporting "on"; the prefs work.)
for key in AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates ConfigDataInstall CriticalUpdateInstall; do
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate "$key" -bool false
done

step "TCC grants"
# Rows keyed by bundle ID with a NULL csreq apply to any build of that bundle ID (verified on
# macOS 27), so unsigned/ad-hoc test builds are covered without re-granting per build.
grant() { # db service client [indirect_object]
    sudo sqlite3 "$1" "insert or replace into access
        (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags, indirect_object_identifier)
        values ('$2', '$3', 0, 2, 4, 1, NULL, 0, '${4:-UNUSED}');"
}
for service in kTCCServiceAccessibility kTCCServiceScreenCapture kTCCServicePostEvent kTCCServiceListenEvent; do
    grant "$SYSTEM_TCC" "$service" "$APP_ID"
done
for target in com.apple.finder com.apple.systemevents; do
    grant "$USER_TCC" kTCCServiceAppleEvents "$APP_ID" "$target"
    grant "$USER_TCC" kTCCServiceAppleEvents "$HELPER_ID" "$target"
done
for service in kTCCServiceCamera kTCCServiceMicrophone; do
    grant "$USER_TCC" "$service" "$APP_ID"
done
# Let osascript run via `tart exec` (whose responsible process is the guest agent) drive System
# Events and Finder without an Automation prompt. Path clients use client_type 1.
AGENT="$(readlink -f /opt/homebrew/bin/tart-guest-agent)"
for target in com.apple.finder com.apple.systemevents; do
    sudo sqlite3 "$USER_TCC" "insert or replace into access
        (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags, indirect_object_identifier)
        values ('kTCCServiceAppleEvents', '$AGENT', 1, 2, 4, 1, NULL, 0, '$target');"
done
echo "system:"; sudo sqlite3 "$SYSTEM_TCC" "select service, client from access where client like 'net.tenshu.%';"
echo "user:";   sudo sqlite3 "$USER_TCC"   "select service, client, indirect_object_identifier from access where client like 'net.tenshu.%' or client like '%tart-guest-agent';"

step "Screen capture approval"
# Separately from TCC, ScreenCaptureKit shows a "bypass the system private window picker" alert
# unless replayd has a recent approval for the client; seed one that never expires.
# Seed the app (bundle ID) and the guest agent (path; `hs2vm screenshot` runs screencapture
# through it).
/usr/bin/python3 - "$APP_ID" "$(readlink -f /opt/homebrew/bin/tart-guest-agent)" <<'EOF'
import datetime, os, plistlib, sys
path = os.path.expanduser("~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist")
approvals = plistlib.load(open(path, "rb")) if os.path.exists(path) else {}
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
for client in sys.argv[1:]:
    approvals[client] = {
        "kScreenCaptureAlertableUsageCount": 1,
        "kScreenCaptureApprovalLastAlerted": now,
        "kScreenCaptureApprovalLastUsed": now,
        "kScreenCapturePrivacyHintDate": datetime.datetime(2100, 1, 1),
        "kScreenCapturePrivacyHintPolicy": 2592000,
    }
os.makedirs(os.path.dirname(path), exist_ok=True)
plistlib.dump(approvals, open(path, "wb"))
print("seeded", ", ".join(sys.argv[1:]))
EOF

step "Stamp"
sudo tee /etc/hs2-golden.json >/dev/null <<EOF
{"provisioned": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "macos": "$(sw_vers -productVersion) ($(sw_vers -buildVersion))", "xcode": "$(xcodebuild -version | tr '\n' ' ' | sed 's/ $//')"}
EOF
cat /etc/hs2-golden.json
