# Contributing to Hammerspoon 2

Please read the [AI policy](AI_POLICY.md) and [code of conduct](CODE_OF_CONDUCT.md) first.

## Changelog entries

Release notes are built from trailers in commit messages. If your change is
something users will notice, add one or more of these to the **last
paragraph** of a commit message (with no blank lines between them and any
`Co-Authored-By:` or `Signed-off-by:` lines):

```
Changelog-Added: hs.foo.bar(), which does a thing
Changelog-Changed: hs.foo.baz() now returns null instead of false
Changelog-Fixed: hs.foo.qux() no longer crashes on an empty string
```

- **Added** is for new API that users can now use.
- **Changed** is for existing API whose behaviour has changed.
- **Fixed** is for bugs that have been fixed.

Each entry is one line of markdown, and a commit can have as many as it
needs. Changes users won't see (refactoring, tests, CI) don't need one. A bot
will comment on your pull request if it can't find any entries, or if some
are malformed. To check your commits locally:

```bash
node scripts/release/changelog.js check --from origin/main
```

## Testing in a VM

Hammerspoon's tests open windows, move the pointer and synthesize keystrokes, so
running them on your own Mac (`xcodebuild test`) takes over your screen,
keyboard and mouse until they finish. `scripts/vm/hs2vm` runs them in a
headless macOS VM instead, using [Tart](https://tart.run). The same tool can
install a build in a VM and drive it by hand: run JavaScript in it, click,
type and take screenshots. All of this works for a person at a terminal or
for an AI coding agent.

The VMs have no window on your Mac. You "see" a VM by taking screenshots, and
you control it with commands that synthesize real mouse and keyboard events
inside the guest. (Tart's VNC option is deliberately unused, because
Virtualization.framework's VNC server can crash the whole VM.)

### One-time setup

1. Install Tart: `brew install openai/tools/tart`.
2. Make sure Xcode is installed and selected (`xcode-select -p`). The VM gets
   a copy of the Xcode you build with, so the guest always matches the host.
3. Build the golden image:

   ```bash
   scripts/vm/hs2vm provision
   ```

   The first run downloads the ~41 GB Cirrus Labs macOS base image, then takes
   a few minutes to make `hs2-golden`. Provisioning copies your Xcode into the
   guest. It also pre-grants every privacy permission the tests need
   (Accessibility, Screen Recording, Input Monitoring, Camera, Microphone,
   Automation) to Hammerspoon 2, and turns on Spotlight indexing. Finally, it
   quietens the desktop (no sleep, crash dialogs, widgets or software updates)
   and installs `hs2vm-guest`, a small tool that posts mouse and keyboard
   events inside the guest.

Run `provision` again whenever you update Xcode. Every VM is a clone of
`hs2-golden`, and nothing else ever changes it.

VMs get 6 CPUs, 16 GB of RAM and a 100 GB disk. To change these, set
`HS2VM_CPUS`, `HS2VM_MEMORY_MB` or `HS2VM_DISK_GB` when you run `provision`.
They're baked into the golden image, so setting them for any other command
does nothing. (To resize the existing image instead:
`tart set hs2-golden --memory 8192`.) A running VM uses roughly its full RAM
allocation on the host within seconds of booting, so budget for that. The
test suite runs just as fast with 8 GB.

`HS2VM_XCODE` picks a different Xcode for `provision`, and `HS2VM_BASE_IMAGE`
a different base image.

### Running the tests

```bash
scripts/vm/hs2vm test                                                   # the full suite
scripts/vm/hs2vm test "-only-testing:Hammerspoon 2Tests/HSHashIntegrationTests"
scripts/vm/hs2vm test "-only-testing:Hammerspoon 2Tests/HSHashIntegrationTests/testMD5FromJS()"
scripts/vm/hs2vm test --keep                                            # keep the VM afterwards
```

`test` builds the app and tests on your Mac (into `build/vm/DerivedData`, so
it doesn't disturb Xcode's own builds). It then clones `hs2-golden` into a
throwaway VM, runs the tests there with `xcodebuild test-without-building`,
collects the results and deletes the VM. The full suite takes about four
minutes. Anything after `test` (or `--keep`) is passed to `xcodebuild`.
`-only-testing:` takes the target name `Hammerspoon 2Tests` (quoted, with the
space), then the top-level test struct, and for a single test, its name with
a trailing `()`. If nothing matches, xcodebuild runs zero tests and still
reports success.

The exit status is xcodebuild's. Results land in `build/vm/runs/<timestamp>/`:

| File | Contents |
| --- | --- |
| `summary.md` | Pass/fail/skip summary; read this first |
| `xcodebuild.log` | The full test output |
| `TestResults.xcresult` | The result bundle (`xcrun xcresulttool get test-results tests --path …`) |
| `crash-reports/` | Crash reports from the guest, if the test host crashed |
| `build.log`, `final.png` | The host build log, and a screenshot of the guest when the tests ended |

Tests can tell they're in a VM: the environment variable `HS2_VM` is set.
Some tests always skip in a VM because it has no such hardware or support:
battery, camera, Wi-Fi, Stream Deck, physical MIDI devices and `hs.ocr` text
recognition.

### Driving a build by hand

To check a change in the real app, start a long-lived VM, install your build
in it, and drive it:

```bash
scripts/vm/hs2vm up hs2-dev          # clone hs2-golden as hs2-dev and boot it (~30s)
scripts/vm/hs2vm build               # build on your Mac
scripts/vm/hs2vm install hs2-dev     # copy the build into the VM and launch it
# ... drive it (below) ...
scripts/vm/hs2vm down hs2-dev        # stop and delete the VM
```

VM names must start with `hs2-`. `up` reuses an existing VM of that name, so
`hs2vm stop hs2-dev` followed later by `hs2vm start hs2-dev` picks up where
you left off. `hs2vm status` lists the VMs.

**Installing.** `install` copies the app to `/Applications/Hammerspoon 2.app`
in the guest. It skips the first-launch Welcome window and writes an
`init.js` that starts `hs.ipc`, followed by your own config if you give one.
It then launches the app and waits until the app answers. `install` only
builds if there's no build yet, so after changing code, run `hs2vm build`
before installing again.

```bash
scripts/vm/hs2vm install hs2-dev --config my-init.js      # append my-init.js to the config
scripts/vm/hs2vm install hs2-dev --app path/to/Hammerspoon\ 2.app
```

**Running JavaScript in the app.** `hs` evaluates JavaScript in the running
app with its own `hs2` command-line tool, through `hs.ipc`, the same way a
user would. It prints the value of the last expression. Multi-line scripts
can come from stdin, and if the result is a Promise, `hs` waits for it.

```bash
scripts/vm/hs2vm hs hs2-dev 'hs.application.frontmost().name'
scripts/vm/hs2vm hs hs2-dev < script.js
```

Its exit status is 0 on success, 65 if the JavaScript threw (or its Promise
rejected), and 1 if it couldn't reach the app. Errors go to stderr.

**Running shell commands in the guest.** `exec` runs any command as the
logged-in `admin` user, in the GUI session. `sudo` needs no password.

```bash
scripts/vm/hs2vm exec hs2-dev sw_vers
scripts/vm/hs2vm exec hs2-dev log show --last 2m --predicate 'process == "Hammerspoon 2"'
```

To copy a file in, pipe it through `tart exec -i`:

```bash
tart exec -i hs2-dev sh -c 'cat > ~/file.txt' < file.txt
```

**Screenshots.**

```bash
scripts/vm/hs2vm screenshot hs2-dev shot.png
```

The display is 1024x768 points, and screenshots are 2048x1536 pixels.

**Mouse and keyboard.** These post real HID-level events in the guest, so
Hammerspoon's own event taps and hotkeys see them.

```bash
scripts/vm/hs2vm click hs2-dev 1341 984        # also doubleclick, rightclick, move
scripts/vm/hs2vm drag hs2-dev 100 100 600 400
scripts/vm/hs2vm key hs2-dev cmd+n             # several chords per call: key hs2-dev cmd+a delete
scripts/vm/hs2vm type hs2-dev 'Hello, world!'
```

- Coordinates are **screenshot pixels**: find the spot in a screenshot and use
  its position as-is. If your image viewer (or agent) shows a scaled-down
  copy, scale the position back up to 2048x1536 first.
- Modifiers are `cmd`, `shift`, `ctrl`, `alt` (or `opt`/`option`) and `fn`.
  Keys are letters, digits, US-layout punctuation, `return`, `tab`, `esc`,
  `space`, `delete` (backspace), `forwarddelete`, the arrows,
  `home`/`end`/`pageup`/`pagedown` and `f1`–`f12`.
- `type` sends Unicode text directly, so it doesn't depend on the keyboard
  layout.

A typical loop: take a screenshot, look at it, click or type, then take
another screenshot to confirm what happened.

### Things to know

- **Two VMs at most.** Apple's licence allows two macOS VMs at once, and
  Virtualization.framework enforces it. A `test` run uses one.
- **Concurrent runs are safe.** `build`, `test` and `install` share one set of
  build products and take turns with a lock. A second run says it's waiting,
  and a lock left by a dead process is reclaimed automatically.
- **Notification banners.** The base image shows "App Background Activity"
  banners at boot, and installing the app adds another. `hs2vm` closes them,
  but if one turns up in a screenshot later, run
  `scripts/vm/hs2vm exec hs2-dev /usr/local/bin/hs2vm-guest dismiss-notifications 5`
  and take the screenshot again.
- **Don't run `tart list` while a VM is booting.** It can make the boot fail
  with "Internal Virtualization error". (`hs2vm start` and `up` avoid this.)
- **Clean up.** Delete VMs you made with `up` (`hs2vm down`), and use `down`
  after `test --keep` too. `down` refuses to delete `hs2-golden`.

### Pointing an AI agent at this

Everything above is a plain command with text output and a meaningful exit
status, plus PNG screenshots. Any agent that can run shell commands and look
at images can therefore use it. Tell it to read this section, and to follow
these rules:

- Run tests with `scripts/vm/hs2vm test` instead of `xcodebuild test` on the
  host, unless you say otherwise. Run the full suite in the background and
  read `summary.md` when it finishes.
- Run each `hs2vm` or `tart exec` command on its own, not chained with `&&`
  or `;`, so that permission rules like `Bash(scripts/vm/hs2vm *)` match.
- To verify UI behaviour, take a screenshot and look at it before claiming it
  works, and again after each action that should change the screen.
- Convert any position read from a scaled-down image back to 2048x1536
  pixels before using it to click.
- Run `hs2vm build` before `install` after every code change.
- Delete every VM it creates.
- Post cropped screenshots on pull requests that change something on screen
  (`gh pr comment <n> --body-file body.md --attach shot.png`).

Claude Code users get this automatically: the `/HSVMTest` skill
(`.claude/skills/HSVMTest/SKILL.md`) covers the same ground.
