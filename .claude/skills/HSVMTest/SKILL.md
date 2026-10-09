---
name: hsvmtest
description: Run Hammerspoon 2 tests, or install and drive a build, inside a headless Tart macOS VM via scripts/vm/hs2vm, instead of on the developer's own Mac — use this by default whenever running tests or poking at the running app
---

# Testing in a VM with hs2vm

Running `xcodebuild test` on the host takes over the developer's screen, keyboard and mouse
(windows open, the pointer moves, keystrokes are synthesized). **Run tests in a VM by default**
with `scripts/vm/hs2vm`; only fall back to a host `xcodebuild test` if the user asks for it or
the VM can't be used (say why).

Everything runs headless: VMs have no window on the host. Screenshots (`screencapture`) and
mouse/keyboard input (the `hs2vm-guest` tool posting CGEvents) happen inside the guest.

## Prerequisites

- `tart` installed (the user installs it: `brew install openai/tools/tart` — never run brew yourself).
- The golden image `hs2-golden` exists (`scripts/vm/hs2vm status`). If not, build it with
  `scripts/vm/hs2vm provision` (~4 minutes; needs the ~41 GB Cirrus Labs base image, pulled
  automatically on first use). Re-provision after an Xcode update so the guest matches the host.

## Running tests

```bash
scripts/vm/hs2vm test                                                       # full suite (~12 min)
scripts/vm/hs2vm test "-only-testing:Hammerspoon 2Tests/HSHashIntegrationTests"
scripts/vm/hs2vm test "-only-testing:Hammerspoon 2Tests/HSHashIntegrationTests/testMD5FromJS()"
scripts/vm/hs2vm test --keep …                                              # keep the VM to investigate
```

Arguments after `test` go straight to `xcodebuild test-without-building`, so the
`-only-testing:` rules in CLAUDE.md apply (target `Hammerspoon 2Tests` with a space, top-level
suite struct name, trailing `()` for a single test).

`test` builds on the host (into `build/vm/DerivedData`, separate from Xcode's), clones
`hs2-golden`, runs the tests, collects results, and deletes the clone. Run the full suite with
`run_in_background` and watch `build/vm/runs/<timestamp>/xcodebuild.log`. Results land in
`build/vm/runs/<timestamp>/`:

| File | Contents |
| --- | --- |
| `summary.md` | Markdown pass/fail/skip summary from `scripts/xcresult-report.js` — read this first |
| `xcodebuild.log` | Full test output |
| `TestResults.xcresult` | Result bundle (`xcrun xcresulttool get test-results tests --path …`) |
| `crash-reports/` | `Hammerspoon 2*.ips` from the guest, if the test host crashed |
| `build.log`, `final.png` | Host build log; screenshot of the guest when the tests finished |

The exit status is xcodebuild's.

### What differs from the host

- Tests can detect the VM: `ProcessInfo.processInfo.environment["HS2_VM"] != nil`
  (set via `TEST_RUNNER_HS2_VM=1`).
- Expected skips: battery, camera, Wi-Fi, Stream Deck, physical MIDI (no such hardware), and
  `hs.ocr` recognizeText (Vision can't load its accurate-recognizer models in a VM).
- TCC is pre-granted to `net.tenshu.Hammerspoon-2` by bundle ID (Accessibility, Screen
  Recording, Input Monitoring, PostEvent, Camera, Microphone, AppleEvents → Finder/System
  Events), so permission-gated tests run rather than skip. Any build is covered; no signing needed.
- One display, 1024x768 points (2048x1536 pixels).

## Installing and driving the app

```bash
scripts/vm/hs2vm up hs2-dev                      # clone hs2-golden as hs2-dev and boot it
scripts/vm/hs2vm build                           # host build (skip if `test` just built)
scripts/vm/hs2vm install hs2-dev [--config my-init.js] [--app path/to/Hammerspoon 2.app]
scripts/vm/hs2vm hs hs2-dev 'hs.application.frontmost().title'
scripts/vm/hs2vm hs hs2-dev < script.js          # multi-line; the last expression's value is printed;
                                                 # Promises are awaited; exit status is hs2's:
                                                 # 65 = the JavaScript threw (or its Promise
                                                 # rejected), 1 = couldn't reach the app
scripts/vm/hs2vm screenshot hs2-dev /tmp/shot.png   # then Read the PNG
scripts/vm/hs2vm down hs2-dev                    # stop and delete it when done
```

`install` writes `~/.config/Hammerspoon2/init.js` as `hs.ipc.start();` followed by `--config`,
skips the first-launch Welcome window, launches the app and waits until it answers.

`hs` runs the app's own `hs2` CLI in the guest, so it exercises the real hs.ipc path (hs2 →
HammerspoonIPCBroker launch agent → app). The broker is registered with `SMAppService`, which
refuses bundles without a sealed signature, so `hs2vm build` ad-hoc signs the app after building;
Debug builds skip hs.ipc's same-team checks. A JavaScript error is printed to stderr as
`err.toString()` (no stack).

### Mouse and keyboard

```bash
scripts/vm/hs2vm click hs2-dev 1341 984          # also doubleclick, rightclick, move
scripts/vm/hs2vm drag hs2-dev 100 100 600 400
scripts/vm/hs2vm key hs2-dev cmd+n               # chords; several per call: key hs2-dev cmd+a delete
scripts/vm/hs2vm type hs2-dev 'Hello, world!'
```

- Coordinates are **screenshot pixels** (2048x1536). When the Read tool shows a downscaled
  image, multiply by the scale factor it reports.
- Modifiers: `cmd`, `shift`, `ctrl`, `alt`/`opt`/`option`, `fn`. Keys: letters, digits and
  US-layout punctuation, `return`, `tab`, `esc`, `space`, `delete` (backspace), `forwarddelete`,
  arrows, `home`/`end`/`pageup`/`pagedown`, `f1`–`f12`.
- `type` sends Unicode text directly, so it's independent of keyboard layout.
- Input is real HID-level CGEvents, so Hammerspoon's own event taps and hotkeys see it.

## Other commands

`hs2vm start|stop <vm>`, `hs2vm exec <vm> <cmd…>` (runs as the auto-logged-in `admin` user in
the GUI session; `sudo` needs no password), `hs2vm status`. VM names must start with `hs2-`
(the user's permission rule allows `tart exec hs2-*`).

## Gotchas

- At most **two** macOS VMs can run at once (Apple's licence, enforced by Virtualization.framework).
- `build`, `test` and `install` share one DerivedData (`build/vm/DerivedData`) and take turns
  on a lock (`build/vm/products.lock`) while building and copying products into a guest, so
  simultaneous runs are safe; a second one logs that it's waiting. A lock left by a dead
  process is reclaimed automatically.
- Call `tart exec` (and `hs2vm`) as standalone commands, not chained with `&&`/`;`, so the
  user's `Bash(tart exec hs2-*)` permission rule matches.
- Don't call `tart list` while a VM is booting (it makes the boot fail with "Internal
  Virtualization error"); `hs2vm start` already avoids this.
- Don't run VMs with `tart run --vnc` / `--vnc-experimental`: Virtualization.framework's VNC
  server asserts while setting up some client connections (and on clients that don't advertise
  the DesktopSize/ExtendedDesktopSize encodings), killing the whole VM. hs2vm never enables it.
- The Cirrus Labs base image posts persistent "App Background Activity" / "Extensions Added"
  banners at boot; `hs2vm start` closes them (`hs2vm-guest dismiss-notifications`). If one shows
  up in a screenshot later, run `scripts/vm/hs2vm exec <vm> /usr/local/bin/hs2vm-guest dismiss-notifications 5`.
