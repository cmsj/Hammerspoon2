Hammerspoon 2 is a from-scratch rewrite: a Swift app running a JavaScriptCore engine, in
place of the original Objective-C/Lua app. There is no automatic config converter — Lua
`init.lua` files cannot be loaded, and no v1 module ships unmodified. This guide is a map,
not an exhaustive method-by-method diff: it tells you where things went, what to expect
conceptually, and where you'll need to build something yourself. Once you know where to
look, the API reference has the exact method signatures for each module.

## The big picture

A handful of changes touch almost every module, so it's worth internalizing these before
diving into specifics:

- **JavaScript, not Lua.** Configs are `.js` files evaluated by JavaScriptCore, not `.lua`
  files evaluated by a bundled Lua runtime. Several v1 modules existed purely to compensate
  for gaps in Lua's standard library and simply aren't needed any more: `JSON.parse`/
  `JSON.stringify` replace `hs.json`, `Math` replaces `hs.math`, native Unicode-aware strings
  replace `hs.utf8`, `console.log`/`JSON.stringify(x, null, 2)` replace `hs.inspect`, and
  array methods (`.map`/`.filter`/`.reduce`/...) replace `hs.fnutils`.
- **`hs.ui` replaces the entire drawing/canvas/webview/dialog family.** `hs.drawing`,
  `hs.canvas`, `hs.webview`, `hs.dialog`, `hs.alert`, and `hs.styledtext` are all gone,
  replaced by one SwiftUI-backed declarative UI module. This is the single biggest
  programming-model change in the whole migration — see [Rebuilding UI with hs.ui](#rebuilding-ui-with-hsui)
  below.
- **There is no Spoon/plugin ecosystem.** `hs.loadSpoon()`, the Spoon object lifecycle, and
  the spoons.hammerspoon.org repository have no v2 counterpart — see
  [Removed with no equivalent](#removed-with-no-equivalent).
- **Watchers are usually `addWatcher()`/`removeWatcher()` on the main module now,** not a
  separate `.watcher` submodule you construct and `:start()`. This pattern is consistent
  across `hs.audiodevice`, `hs.camera`, `hs.eventtap`, `hs.keycodes`, `hs.mouse`, `hs.screen`,
  `hs.serial`, `hs.streamdeck`, `hs.usb`, `hs.wifi`, `hs.pasteboard`, `hs.power`, `hs.fs`, and
  more. If a v1 module you're porting had a `.watcher` submodule and you don't see it
  mentioned below, check for `addWatcher()` on the parent module first.
- **Async is Promise-based, not callback-based.** `hs.http`, `hs.osascript`, `hs.network`,
  `hs.shortcuts`, `hs.application.launchOrFocus()`, and others now return Promises you
  `.then()` rather than taking a completion-callback argument. A few (`hs.osascript`) always
  *resolve*, even on failure — check a `success`/`status` field in the result rather than
  relying on `.catch()`.
- **New macOS permission gates exist that v1 never had to deal with.** `hs.wifi` and
  `hs.location` require `hs.permissions.requestLocation()` before identity-revealing fields
  populate; `hs.notify` requires `hs.permissions.requestNotifications()` before notifications
  can appear. Without authorization, fields silently come back `null`/omitted rather than
  erroring — a config that assumed a field was always present can fail quietly.
- **The URL scheme changed.** `hammerspoon://` is now `hammerspoon2://` — update any external
  scripts, launchers, or Shortcuts that invoke your config via `hs.urlevent`.

## Quick reference

Every v1 module, alphabetically. **Gone** means there is no v2 equivalent at all. **→ hs.x**
means the functionality now lives under that v2 module (in full or in part — see the linked
section for what, if anything, didn't make the trip). **Present** means a same-named v2
module exists; see [Present, but check before you port](#present-but-check-before-you-port)
for what changed within it.

| v1 module | Status | Notes |
|---|---|---|
| `hs` | → `hs`, `hs.appinfo`, `hs.ipc` | [details](#hs-and-hsappinfo) |
| `hs.alert` | → `hs.ui` | [details](#rebuilding-ui-with-hsui) |
| `hs.appfinder` | Gone | superseded in v1 itself; use `hs.application.matchingName()` etc. |
| `hs.applescript` | → `hs.osascript` | [details](#hsosascript) |
| `hs.application` | Present | watcher folded in, see below |
| `hs.application.watcher` | → `hs.application` | `addWatcher()`, different callback shape |
| `hs.audiodevice` | Present | watcher folded in; no `.datasource` equivalent |
| `hs.audiodevice.datasource` | Gone | no separate data-source API found |
| `hs.audiodevice.watcher` | → `hs.audiodevice` | `addWatcher()` |
| `hs.axuielement` (+`.axtextmarker`, `.observer`) | → `hs.ax` | [details](#hsax-accessibility) |
| `hs.base64` | → `hs.hash` | `base64Encode`/`base64Decode` |
| `hs.battery` (+`.watcher`) | → `hs.power` | [details](#hspower) |
| `hs.bonjour` (+`.service`) | Present | `.service` objects returned inline, not a submodule |
| `hs.brightness` | → `hs.screen` | `getBrightness()`/`setBrightness()`, see [details](#hsscreen) |
| `hs.caffeinate` (+`.watcher`) | → `hs.power` | [details](#hspower) |
| `hs.camera` | Present | watcher folded in |
| `hs.canvas` (+`.matrix`) | → `hs.ui` | [details](#rebuilding-ui-with-hsui); matrix/transform math gone |
| `hs.chooser` | Present | construction/callback wiring changed |
| `hs.console` | → `console`, `hs` | [details](#hsconsole) |
| `hs.crash` | Gone | dev-only hooks, not expected to return |
| `hs.deezer` | Gone | drive via `hs.osascript` instead |
| `hs.dialog` (+`.color`) | → `hs.ui` | [details](#rebuilding-ui-with-hsui); no system color-picker panel |
| `hs.distributednotifications` | Gone | no general-purpose NSDistributedNotificationCenter wrapper |
| `hs.doc` (+`.builder`,`.hsdocs`,`.markdown`) | Gone | `hs.docs` is unrelated (read-only bundled-doc viewer) |
| `hs.dockicon` | Gone | no Dock icon control |
| `hs.drawing` (+`.color`) | → `hs.ui` | [details](#rebuilding-ui-with-hsui) |
| `hs.eventtap` (+`.event`) | Present | `.event` folded in; "consume" is now a property |
| `hs.expose` | Gone | no window-overlay/hint-code equivalent |
| `hs.fnutils` | Gone | native JS array methods |
| `hs.fs` (+`.volume`,`.xattr`) | Present | comprehensive; see below |
| `hs.geometry` | → `HSPoint`/`HSRect`/`HSSize` | plain value types, no math helpers — see [details](#hsgeometry) |
| `hs.grid` | Gone | see [Window management](#window-management) |
| `hs.hash` | Present | absorbed base64, gained HMAC variants |
| `hs.hid` (+`.led`) | → `hs.keyboard` | [details](#hshid--hskeyboard) |
| `hs.hints` | Gone | no on-screen hint overlay |
| `hs.host` (+`.locale`) | → several modules | [details](#hshost) |
| `hs.hotkey` (+`.modal`) | Present | modal support present via JS, see below |
| `hs.http` | Present | Promise-based, gained WebSocket client |
| `hs.httpserver` | Present | bare server; see `hsminweb` note below |
| `hs.httpserver.hsminweb` (+`.cgilua*`) | Gone | no CGI/templating framework |
| `hs.image` | → `HSImage` type | see [hs.ui](#rebuilding-ui-with-hsui) |
| `hs.inspect` | Gone | `console.log`/`JSON.stringify` |
| `hs.ipc` | Present | XPC-based now, must be started explicitly |
| `hs.itunes` | Gone | drive via `hs.osascript` instead |
| `hs.javascript` | → `hs.osascript` | [details](#hsosascript) |
| `hs.json` | Gone | native `JSON.parse`/`JSON.stringify` |
| `hs.keycodes` | Present | watcher folded in |
| `hs.layout` | Gone | see [Window management](#window-management) |
| `hs.location` (+`.geocoder`) | Present | geocoding folded in as methods |
| `hs.logger` | Gone | no per-instance/leveled logger, only flat `console.*` |
| `hs.math` | Gone | native `Math` |
| `hs.menubar` | Present | close to a direct port |
| `hs.messages` | Gone | drive via `hs.osascript` instead |
| `hs.midi` | Present | lightly tested; watcher shape differs |
| `hs.milight` | Gone | niche hardware |
| `hs.mjomatic` | Gone | niche ASCII-layout module |
| `hs.mouse` | Present | close to a direct port |
| `hs.network` (+`.configuration`,`.host`,`.ping`,`.reachability`) | Present | consolidated, see below |
| `hs.noises` | Gone | niche |
| `hs.notify` | Present | requires explicit permission request now |
| `hs.osascript` | Present | see [details](#hsosascript) |
| `hs.pasteboard` (+`.watcher`) | Present | watcher folded in |
| `hs.pathwatcher` | → `hs.fs` | `hs.fs.createPathWatcher()`, ~1s batching |
| `hs.plist` | Present | close to a direct port |
| `hs.razer` | Gone | niche hardware |
| `hs.redshift` | Gone | macOS Night Shift covers this now |
| `hs.screen` (+`.watcher`) | Present | watcher folded in, see [details](#hsscreen) |
| `hs.serial` | Present | lightly tested; watcher folded in |
| `hs.settings` | → `hs.userdefaults` | gained a watcher |
| `hs.sharing` | Present | close to a direct port |
| `hs.shortcuts` | Present | close to a direct port |
| `hs.socket` (+`.udp`) | Gone | no raw TCP/UDP; WebSocket via `hs.http`/`hs.httpserver` |
| `hs.sound` | Present | [details](#hssound) |
| `hs.spaces` (+`.watcher`) | Gone | no public macOS API, never was reliable |
| `hs.speech` (+`.listener`) | Gone | no TTS or speech recognition |
| `hs.spoons` | Gone | [details](#hsspoons-and-the-plugin-ecosystem) |
| `hs.spotify` | Gone | drive via `hs.osascript` instead |
| `hs.spotlight` (+`.group`,`.item`) | Present | reshaped to a query-object/builder pattern |
| `hs.sqlite3` | Gone | no embedded database |
| `hs.streamdeck` | Present | watcher folded in |
| `hs.styledtext` | → `hs.ui` text elements | see [hs.ui](#rebuilding-ui-with-hsui) |
| `hs.tabs` | Gone | no native window-tabbing control |
| `hs.tangent` | Gone | niche hardware |
| `hs.task` | Present | gained `parallel()`/`sequence()`/`shell()`/builder |
| `hs.timer` (+`.delayed`) | Present | `.delayed` folded in as `doAfter`/`doEvery` |
| `hs.uielement` (+`.watcher`) | → `hs.ax` | [details](#hsax-accessibility) |
| `hs.urlevent` | Present | scheme renamed to `hammerspoon2://` |
| `hs.usb` (+`.watcher`) | Present | watcher folded in |
| `hs.utf8` | Gone | native Unicode-aware strings |
| `hs.vox` | Gone | drive via `hs.osascript` instead |
| `hs.watchable` | Gone | only per-module watchers remain, no generic pub/sub |
| `hs.webview` (+`.datastore`,`.toolbar`,`.usercontent`) | → `hs.ui` | [details](#rebuilding-ui-with-hsui) |
| `hs.wifi` (+`.watcher`) | Present | watcher folded in, new permission gate |
| `hs.window` (+`.filter`,`.highlight`,`.layout`,`.switcher`,`.tiling`) | Present, ecosystem gone | [details](#window-management) |

## Present, but check before you port

Modules with a same-named v2 counterpart still shifted shape in ways worth knowing before
you port line-by-line.

**`hs.application`** — richer than v1: instance objects now expose a full menu-item API
(`getMenuItems()`, `selectMenuItemByName()`) and `axElement()` to drop straight into `hs.ax`.
Watching launch/quit/activate events moved from `hs.application.watcher` to
`hs.application.addWatcher((event, app) => {...})` on the main module; the callback argument
order differs from v1's `(appName, eventType, appObject)`, so check it before porting.

**`hs.chooser`** — construction changed from `hs.chooser.new(completionFn)` to
`hs.chooser.create()` followed by setting `onSelect`/`onQueryChange`/`onShow`/`onHide`/
`onInvalid` and calling fluent, chainable `setChoices()`/`show()`. Choices gained an optional
per-row `contextMenu`. Check the styling-property list before assuming appearance options
(custom fonts/colors) carried over.

**`hs.eventtap`** — `hs.eventtap.event` folded directly into `hs.eventtap` (build events with
`hs.eventtap.makeKeyEvent()` instead of `hs.eventtap.event.newKeyEvent()`; `.post()` is
unchanged). The tap/watcher pattern also changed: instead of `hs.eventtap.new(types, fn):start()`
returning `true` from the callback to consume an event, v2 uses `hs.eventtap.addWatcher(fn)`
with `consume` as a settable property on the watcher object.

**`hs.http`** — every request method returns a Promise resolving to `{status, body, headers}`;
there's no callback argument any more. A network failure *resolves* with `status: -1`, it
doesn't reject — check `status` rather than relying on `.catch()`. Gained `openWebSocket()`
for WebSocket clients (no dedicated WebSocket story existed in v1's `hs.http`).

**`hs.ipc`** — same purpose (the `hs` CLI talking to the running app), but the transport is
now XPC over a named Mach service rather than a bare process pipe, and you must call
`hs.ipc.start()` explicitly — it doesn't auto-start the way v1's did. In release builds,
connections are restricted to binaries signed with the same Team ID.

**`hs.pasteboard`** — `hs.pasteboard.watcher` is gone as a separate submodule; it's
`hs.pasteboard.addWatcher(handler)`/`removeWatcher(handler)` directly on the main module, and
multiple watchers can be registered independently.

**`hs.spotlight`** — reshaped from a one-shot query call into a builder/query-object pattern:
`hs.spotlight.create()` returns an object configured with `setQuery()`/`setScopes()`/
`setCallback()` then `.start()`. Live-updating queries are now first-class — a query left
running after its `didFinish` event keeps firing `didUpdate` as matching files change. What
were `hs.spotlight.group`/`hs.spotlight.item` are now plain objects returned by
`q.groups()`/`q.results()`, not separate module names.

**`hs.task`** — gained `runAsync()`, `shell(command)` (no manual `/bin/sh -c` wrapping),
`parallel()`, `sequence`, and a `builder()`/`TaskBuilder` fluent API. If your v1 code
hand-tracked multiple concurrent `hs.task` objects and their completion callbacks, check
`parallel()`/`sequence` before porting that orchestration logic by hand.

**`hs.notify`** — you must call `hs.permissions.requestNotifications()` (a Promise) before
notifications will appear; macOS enforces this now where v1 didn't need it. `hs.notify.create({...})`
adds actionable buttons (including text-input replies), thread grouping, and scheduled/calendar
triggers, none of which v1 had.

**`hs.wifi`** — `hs.wifi.watcher` folded into `hs.wifi.addWatcher()`, which returns a watcher
object configured via an `events` array property and `hs.wifi.watcherEventTypes` rather than
one-watcher-per-event-type. `associate()`/`scanNetworks()` are now Promise-based. New and
important: `ssid`, `bssid`, `countryCode`, and scan-result BSSIDs only populate once
`hs.permissions.requestLocation()` has been granted — without it they come back `null`, not
an error, which can silently break configs that assume `ssid` is always present.

**`hs.urlevent`** — the scheme is `hammerspoon2://`, not `hammerspoon://` — update anything
external that invokes your config. `httpCallback`/`mailtoCallback` are now plain assignable
properties instead of a separate registration call.

**`hs.bonjour`**, **`hs.camera`**, **`hs.keycodes`**, **`hs.menubar`**, **`hs.midi`**,
**`hs.mouse`**, **`hs.plist`**, **`hs.serial`**, **`hs.sharing`**, **`hs.shortcuts`**,
**`hs.streamdeck`**, **`hs.usb`** are all close, direct ports — the main adjustment is
watchers moving to `addWatcher()`/`removeWatcher()` on the main module (see
[The big picture](#the-big-picture)) and callbacks becoming JS closures instead of Lua
function references. `hs.midi` and `hs.serial` both carry a doc-comment warning that they
haven't seen much real-world hardware testing yet — treat as lower-confidence if you're
driving real devices.

## Partially recreated — read this if something's missing

These are the "spread across several modules" cases — worth checking closely, since what
you're looking for may exist under a name you wouldn't guess.

### hs.host

v1's `hs.host` was a grab-bag of "info about this Mac." Its pieces landed in different v2
modules, and a few have no home at all:

| v1 `hs.host` function | v2 location |
|---|---|
| `locale` (submodule) | `hs.locale` |
| `addresses()` | `hs.network.addresses()` |
| `names()` | `hs.network.hostnames()` |
| `localizedName()` (machine name) | `hs.appinfo.machineName` |
| `operatingSystemVersion()`/`...String()` | `hs.appinfo.osVersion` / `.osVersionParts` |
| `thermalState()` | `hs.power.thermalState` |
| `volumeInformation()` | `hs.fs.volumes()` |
| `idleTime()` | **No v2 equivalent found.** |
| `cpuUsage()`/`cpuUsageTicks()` | **No v2 equivalent** (`hs.appinfo.cpuCount` is a static core count, not live usage) |
| `vmStat()` | **No v2 equivalent** (`hs.appinfo.ramAmount` is static total RAM, not live pressure/paging) |
| `gpuVRAM()` | **No v2 equivalent found.** |
| `interfaceStyle()` (light/dark mode) | **No v2 equivalent found.** |
| `globallyUniqueString()`/`uuid()` | No dedicated method; JavaScriptCore's `crypto.randomUUID()` likely covers the practical need |

If your config gated automations on idle time, CPU/memory pressure, or light/dark mode, there
is currently nothing in v2 to read that from.

### hs.ax (accessibility)

`hs.axuielement` (+ `.axtextmarker`, `.observer`) and `hs.uielement` (+ `.watcher`) all merge
into **`hs.ax`**, with a much smaller surface than v1's combined AX modules:
`systemWideElement`, `applicationElement`, `windowElement`, `elementAtPoint`,
`focusedElement`, `findByRole`, `findByTitle`, `printHierarchy`, `addWatcher`, `removeWatcher`,
plus an `HSAXElement` type with the common properties/actions (`role`, `title`, `value`,
`frame`, `children()`, `attributeValue()`/`setAttributeValue()`, `performAction()`, etc.).

Two real capability regressions to know about:

- **No AXTextMarker support at all.** If you manipulated text-position markers in editors or
  PDF viewers via `hs.axuielement.axtextmarker`, there's no path forward.
- **Watching is application-scoped only.** `hs.ax.addWatcher(app, notification, listener)`
  watches notifications on a whole app, not on an arbitrary element you've drilled into the
  way v1's generic `hs.axuielement.observer`/`hs.uielement.watcher` could. If you built a
  watcher on one specific, deeply-nested element, restructure around app-level watching plus
  your own filtering in the callback.

### Window management

Core `hs.window` covers direct queries and single-window actions well — `focusedWindow()`,
`allWindows()`, `windowsForApp()`, and instance actions like `focus()`, `raise()`,
`toggleFullscreen()`, `centerOnScreen()`. What's gone is the rest of v1's window ecosystem,
module by module:

- **`hs.window.filter`** — no equivalent. This was one of v1's most-used modules: persistent,
  rule-based window filters with subscriptions to lifecycle events. `hs.window` gives you
  one-shot queries and direct actions only, with no "tell me whenever a window matching X
  changes" subscription system. Reactive window management needs to be hand-built on top of
  `hs.ax`'s app-level `addWatcher` notifications.
- **`hs.window.highlight`** — no equivalent. The animated focus flash/dim effects have nothing
  built-in; approximate it yourself with `hs.ui` if needed.
- **`hs.window.layout`** — no equivalent saved-layout/continuous-enforcement system.
- **`hs.window.switcher`** — no cmd-tab-replacement UI. `hs.chooser` can serve as a basic
  type-to-select switcher, but the hold-a-modifier UX has to be built by hand.
- **`hs.grid`, `hs.layout`, `hs.window.tiling`** — no dedicated modules. `hs.window.js` (the
  JS enhancement layer) ships small `grid`/`tiling` helper objects, but they're stub-quality —
  screen dimensions are hardcoded to 1920×1080 rather than read from `hs.screen`, and there's
  no rule-table or multi-window fitting like v1's `hs.layout`/`tileWindows()` had. Treat them
  as scaffolding to build your own layout system on, not as parity replacements.
- **`hs.expose` / `hs.hints`** — no equivalent. The Exposé-style thumbnail overlay and
  keyboard jump-hints have no built-in replacement; both would need to be built from scratch
  with `hs.window` + `hs.ui`.

If your v1 config's window management was mostly "get the focused window, move/resize/center
it," porting to `hs.window` is straightforward. If it leaned on filters, subscriptions, saved
layouts, or a switcher/highlight/expose UI, expect to rebuild that logic yourself on the
smaller primitive set (`hs.window` + `hs.ax` + `hs.ui` + `hs.screen`).

### hs.power

`hs.battery` (+`.watcher`) and `hs.caffeinate` (+`.watcher`) both merge into **`hs.power`**:
`batteryInfo()` covers nearly all of `hs.battery`'s per-field getters, `addBatteryWatcher()`
replaces `hs.battery.watcher`, and `addEventWatcher()` replaces `hs.caffeinate.watcher` (all
12 of v1's event names carry over: `screensDidSleep`, `systemWillSleep`, etc.).
`preventSleep()`/`allowSleep()`/`declareActivity()` replace the sleep-assertion functions, and
`systemSleep()`/`lockScreen()`/`startScreensaver()` carry over directly.

Not carried over: `fastUserSwitch()`, `logOut()`, `restartSystem()`, `shutdownSystem()` — the
"drastic" session/system control actions have no v2 equivalent anywhere. If your config
triggers a logout/restart/shutdown, there's currently no way to do that. Also missing:
`otherBatteryInfo()`/`privateBluetoothBatteryInfo()` for non-PSU accessory batteries.

### hs.hid / hs.keyboard

There's no module called `hs.hid` in v2, but this isn't a clean removal: v1's `hs.hid`
(CapsLock get/set/toggle) and `hs.hid.led` (LED control) landed as a direct, essentially
complete replacement inside the new **`hs.keyboard`** module — `capsLockState()`,
`setCapsLockState()`, `toggleCapsLockState()`, `setLED()` — which goes further than v1 by also
letting you enumerate individual attached keyboards and address their LEDs/CapsLock state
per-device (`attachedKeyboards()`, `keyboardCapsLockState()`, `setKeyboardLED()`).

### hs.osascript

`hs.applescript`, `hs.javascript`, and `hs.osascript` all collapse into one **`hs.osascript`**
module: `applescript()`/`javascript()` (Promise-based) plus `*Sync` and `*FromFile` variants
for both languages. Scripts now run in a separate XPC helper process, so a crashing or
deadlocking script no longer takes the whole app down with it. Important behavioral change:
the async functions **always resolve**, never reject — check the `success` field of the
resolved `{success, result, raw}` object rather than using `.catch()`.

### hs.geometry

There is no `hs.geometry` module or constructor function. `HSPoint`, `HSRect`, and `HSSize`
are plain value types (used across `hs.screen`, `hs.window`, `hs.ax`, etc.) with simple
`{x, y}` / `{x, y, w, h}` / `{w, h}` shapes, but **no math library** — no `union`,
`intersect`, `inside`, `distance`, `area`, or similar helpers. If your v1 config did rect math
via `hs.geometry`, you'll need to reimplement it by hand against the plain object shape.

### hs.network

`hs.network.configuration`, `.host`, `.ping` (+`.echoRequest`), and `.reachability` all fold
into one **`hs.network`** module — a real consolidation, not a cut-down module. Reachability
monitors, hostname resolution (`resolve()`), network-location configuration access, and real
ICMP ping (`hs.network.ping()`, not a TCP-connect approximation) are all present, just
flattened onto the parent module with longer method names instead of dotted submodules.

### hs.fs

`hs.fs.volume`, `hs.fs.xattr`, and `hs.pathwatcher` all fold into one comprehensive
**`hs.fs`** module (42 methods) — a genuine superset of what the four v1 pieces did.
Volumes are `hs.fs.volumes()`/`ejectVolume()`/`addVolumeWatcher()`; extended attributes are
`xattrGet`/`xattrList`/`xattrSet`/`xattrRemove`; **`hs.pathwatcher` is not gone** — it's
`hs.fs.createPathWatcher(path)`, returning a watcher object you call `.setCallback()` and
`.start()` on (events batch with ~1 second latency, worth checking if your v1 code assumed
near-instant delivery). `hs.fs` also now covers what Lua's built-in `io`/file functions did in
v1 configs, since JS has no built-in filesystem API — raw file I/O needs to move to
`hs.fs.read`/`write`/`append`.

### hs.sound

`hs.sound` is close to feature-complete against v1 despite sounding minimal — `play()`,
`volume`, `loops`, `currentTime` (seeking), `duration`, and completion callbacks are all
present. What's actually missing: **playback device selection** (v1's `device([deviceUID])`
routing a sound to a specific output has no equivalent — `hs.audiodevice` can change the
system-wide default output as a workaround, but not per-sound routing), and
`getAudioEffectNames()`/file-type introspection helpers.

### hs.screen

Display enumeration, mode setting, and screenshots (`snapshot()`, now Promise-based via
ScreenCaptureKit) all carry over, plus new `ambientLight` sensor access. Brightness control
is also back — `getBrightness()`/`setBrightness()` are the same names and same 0.0–1.0 scale
as v1, and cover the same displays v1 did (the built-in panel plus Apple/LG displays that
expose software brightness); v1 never did true DDC/CI brightness control of arbitrary
third-party monitors over I2C either, so there's no loss of scope there, just a swap of
private API underneath (v1's IOKit `IODisplay` calls don't work on Apple Silicon, so v2 talks
to `DisplayServices.framework` instead). `hs.screen.watcher` also carries over: it's
`hs.screen.addWatcher(fn)`/`removeWatcher(fn)` directly on the main module now (no separate
watcher object to construct/`:start()`), and the callback still takes no arguments — call
`all()`/`main()`/`primary()` inside it to inspect the new configuration. There's no v2
equivalent of `newWithActiveScreen()`'s active-display-changed variant (it relied on an
undocumented `NSWorkspace` notification); if your config used that specifically to detect
Mission Control's per-display Spaces switching focus, that distinction isn't available —
only the general "layout changed" event is.

## Rebuilding UI with hs.ui

This is the biggest single change in the whole migration. `hs.alert`, `hs.canvas`
(+`.matrix`), `hs.dialog` (+`.color`), `hs.drawing` (+`.color`), `hs.image`, `hs.styledtext`,
and `hs.webview` (+`.datastore`, `.toolbar`, `.usercontent`) are all gone, replaced by one
new module: **`hs.ui`**.

In v1, this whole family was **imperative**: you created an object
(`hs.drawing.rectangle(rect)`, `hs.canvas.new(rect)`, `hs.webview.new(rect)`), got a handle
back, and mutated it over time with setter calls (`rect:setFillColor(...)`,
`canvas:appendElements(...)`). Each drawing primitive, canvas, dialog, and webview was its
own independently managed screen object.

`hs.ui` replaces all of that with two ideas:

1. **A declarative element tree, built with a fluent/chained builder.** Call
   `hs.ui.window({x, y, w, h})` to get a window builder, then chain elements onto it —
   `.vstack()`/`.hstack()`/`.zstack()` for layout, `.rectangle()`/`.circle()` for shapes,
   `.text()`/`.image()`/`.video()`/`.button()`/`.webview()` for content — with styling
   (`.fill()`, `.cornerRadius()`, `.frame()`, `.font()`, `.foregroundColor()`) and
   interaction (`.onClick()`, `.onHover()`) calls applying to whatever preceded them.
   Containers close with `.end()`. You build the tree once and call `.show()` — there's no
   "append/remove element" API like `hs.canvas` had; to change *structure*, you rebuild and
   re-show.
2. **Reactive values for anything that changes after the window is shown.** Instead of
   calling a setter on a screen object, create a shared reactive value — `HSColor.hex(...)`,
   `hs.ui.string(...)` (an `HSString`), or an `HSImage` — pass it into `.fill()`/`.text()`/
   `.image()` when building the element, and later call `.replaceWithHex()`/`.set()`/
   `.replaceWithImage()` on *that value* from any callback. The UI updates automatically; you
   never touch the element or window object again.

Where each v1 module's job landed:

- **`hs.drawing` / `hs.canvas`** → `.rectangle()`/`.circle()`/`.text()`/`.image()` elements in
  the builder. There's no equivalent of `hs.canvas`'s arbitrary paths, arcs, or
  compositing/blend modes — the shape vocabulary is currently just rectangle and circle.
- **`hs.canvas.matrix`** → gone entirely; no 2D transform/matrix math (rotate/scale/skew)
  exists anywhere in `hs.ui`.
- **`hs.drawing.color` / `hs.dialog.color`** → the shared `HSColor` type
  (`HSColor.hex("#RRGGBB")`) used everywhere a color is accepted. No system color-picker
  panel (`NSColorPanel`) is wrapped.
- **`hs.alert`** → `hs.ui.alert(text).duration(seconds).show()`. Multiple concurrent alerts
  now stack automatically instead of needing manual Y-offset math.
- **`hs.dialog`** → split across three builders: `hs.ui.dialog(text)` for message/button
  dialogs, `hs.ui.textPrompt(text)` for text input, `hs.ui.filePicker()` for file/folder
  selection. The key behavioral change: v1's dialog functions were **blocking** (execution
  paused for a return value); v2's are **callback-driven** (`onButton`/`onSelection`) and
  non-blocking. Code written as `local result = hs.dialog.blockAlert(...)` needs restructuring
  around a callback.
- **`hs.image`** → the `HSImage` reactive type. Loading covers most of v1 (`.fromPath()`,
  `.fromName()`, plus new capabilities like `.fromSymbol()` for SF Symbols), but there's no
  general "draw shapes/text into an image and rasterize" compositing API, since canvas
  rasterization itself doesn't exist.
- **`hs.styledtext`** → styling calls directly on a `.text()` element
  (`.text("Hello").font(HSFont.title()).foregroundColor("#FFFFFF")`) instead of an
  attributed-string object built from a table of runs. There's no way to mix multiple
  styles/colors within one text run — each `.text()` element has one font and one color for
  its whole content; multi-style text needs multiple adjacent `.text()` elements in an
  `.hstack()`.
- **`hs.webview`** → `hs.ui.webview()`, embedded into a window with `.webview(wv)`. Requires
  macOS 26+ (built on SwiftUI's `WebView`, not raw `WKWebView`). `evaluateJavaScript()`
  becomes `.execJS()` (fire-and-forget) or `.evalJSResult()` (callback with a result). A
  built-in `.toolbar([...])` exists, but only for standard nav items and custom buttons.
  **Important:** registering `onLoadChange`/`onNavigate`/`onTitleChange` callbacks disables
  automatic garbage-collection cleanup of the webview — call `.destroy()` explicitly when
  you're done with it.
- **`hs.webview.datastore`** → gone. No cookie/storage isolation exists for `hs.ui.webview()`
  — every webview uses the default shared data store, with no way to isolate or clear it.
- **`hs.webview.toolbar`** → only partially recreated, as `hs.ui.webview().toolbar()` — scoped
  to that one webview's own navigation toolbar, not a general `NSToolbar` attachable to any
  window with arbitrary item types.
- **`hs.webview.usercontent`** → gone. There's no JS→native message-passing bridge
  (`WKUserContentController`/`postMessage`). `hs.ui.webview()` interaction is one-directional
  and host-initiated only — Hammerspoon can push code into the page and read a result, but
  the page can't proactively call back into your config. If you need that, poll page state
  with `.evalJSResult()` instead.

## hs.spoons and the plugin ecosystem

There is no plugin/extension-loading mechanism in v2: no `hs.loadSpoon()`, no `Spoon`
directory convention, no `:init()`/`:start()`/`:bindHotkeys()` object lifecycle, and no
package repository. Spoons were the primary way v1 users packaged and shared reusable
automations — window management add-ons, hotkey bundles, app integrations — and that whole
ecosystem has no v2 counterpart. If your config leans on third-party Spoons, expect to
reimplement that functionality directly as plain JavaScript inside (or alongside) your
`init.js`, rather than look for a drop-in replacement. There's currently no packaging or
discovery mechanism if you want your own code to be reusable by others, either — sharing
plain `.js` snippets is the only option today.

## Removed with no equivalent

Everything below has no v2 module and no meaningful coverage elsewhere. Grouped by theme:

**Documentation, logging, and dev tooling:** `hs.doc` (+`.builder`/`.hsdocs`/`.markdown` — the
doc-generation toolkit that backed Spoon docs and inline help; `hs.docs` is an unrelated
bundled-doc *viewer*), `hs.logger` (no per-instance, leveled loggers — only flat
`console.log`/`error`/`warn`), `hs.crash`, `hs.watchable` (no generic pub/sub — only
per-module watchers), `hs.sqlite3`.

**Window/UI tools with no built-in replacement:** `hs.appfinder` (superseded in v1 itself —
use `hs.application`/`hs.window` directly), `hs.dockicon`, `hs.expose`, `hs.hints`, `hs.grid`,
`hs.layout`, `hs.tabs`, `hs.mjomatic` — see [Window management](#window-management) for what's
salvageable from the JS enhancement layer's stub helpers.

**System monitoring:** idle time, live CPU/memory usage, GPU VRAM, and light/dark-mode
interface style — see [hs.host](#hshost) for the full breakdown of what did and didn't find a
new home.

**Third-party hardware:** `hs.milight`, `hs.razer`, `hs.tangent` — niche peripherals, not
ported.

**Third-party app remote control:** `hs.deezer`, `hs.itunes`, `hs.messages`, `hs.spotify`,
`hs.vox` had dedicated AppleScript-wrapper modules in v1. None exist in v2, but the underlying
capability isn't gone — `hs.osascript.applescript(...)` can send the same AppleScript commands
these modules used internally (e.g. `tell application "Spotify" to playpause`), just without
the convenience method names.

**System/session control:** `fastUserSwitch()`, `logOut()`, `restartSystem()`,
`shutdownSystem()` (previously on `hs.caffeinate`) have no v2 equivalent anywhere — there is
currently no way to trigger a logout, restart, or shutdown from a v2 config.

**Spaces, speech, and misc OS integrations:** `hs.spaces` (+`.watcher` — macOS has never had a
public Spaces API, and v1's implementation was always fragile/private-API-based; v2 doesn't
carry that forward), `hs.speech` (+`.listener` — no text-to-speech or speech recognition of
any kind), `hs.noises`, `hs.redshift` (macOS's native Night Shift covers most of this now).

**Networking:** `hs.socket` (+`.udp` — no raw TCP/UDP module; `hs.http`'s
`openWebSocket()` client and `hs.httpserver`'s WebSocket support cover the common
bidirectional-messaging use case, but arbitrary protocol work has no home), `hs.httpserver.hsminweb`
(+`.cgilua`/`.cgilua.lp`/`.cgilua.urlcode` — the whole CGI-style templating framework; v2's
`hs.httpserver` is a bare HTTP(S) server with a request-handler callback, not a web
framework), `hs.distributednotifications` (no general-purpose observer for arbitrary
distributed notifications — v2 uses `NSDistributedNotificationCenter` internally in a couple
of places, but doesn't expose it to JS).

**From the `hs.ui` rewrite specifically:** `hs.canvas.matrix` (2D transform math),
`hs.webview.datastore` (per-webview cookie/storage isolation), `hs.webview.usercontent`
(page-to-native message passing), and the system color-picker panel previously reachable via
`hs.dialog.color` — see [Rebuilding UI with hs.ui](#rebuilding-ui-with-hsui) for details.

## hs and hs.appinfo

In v1, the bare `hs` table carried a grab-bag of globals — `hs.configdir`, `hs.reload()`,
version info, `hs.autoLaunch()`, `hs.docstrings`, and more. v2 splits this cleanly: `hs` keeps
only runtime-control basics (`hs.reload()`, `hs.collectGarbage()`, `hs.openConsole()`,
`hs.closeConsole()`, `hs.clearConsole()`). App/version/path metadata (`configDir`,
`bundlePath`, `version`, `pid`, `osVersion`, `machineName`, etc.) moved to **`hs.appinfo`** as
properties. Command-line/REPL access moved to explicit **`hs.ipc`**, which must be started
manually (`hs.ipc.start()`) — it no longer auto-starts. Autolaunch-at-login moved to the app's
Settings UI / `hs.userdefaults`. There is no `hs.docstrings` inline-help lookup any more — see
`hs.docs` for the closest equivalent (a documentation *viewer*, not a query API).

## hs.console

v1's `hs.console` was large: it controlled the REPL/log window's fonts, colors, toolbar,
window level, history (`getHistory()`/`setHistory()`), and buffer contents
(`getConsole()`/`setConsole()`). Almost none of that survives. v2 splits what remains in two:
the lowercase **`console`** module gives you `console.log()`/`error()`/`warn()`/`info()`/
`debug()` — plain output, styled after JS's `console.log`, nothing more. Window lifecycle
(`open`/`close`/`clear`) moved to the bare `hs` object (`hs.openConsole()`, `hs.closeConsole()`,
`hs.clearConsole()`). There is currently no v2 API for console window styling, colors, fonts,
history access, or a toolbar — if a v1 config customized the console's appearance or read its
history programmatically, that capability is gone.
