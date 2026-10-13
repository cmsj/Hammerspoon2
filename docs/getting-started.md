Hammerspoon 2 runs a JavaScript file of yours inside a real macOS app, and gives that
JavaScript access to a large surface of system APIs — windows, hotkeys, the filesystem,
Wi-Fi, AppleScript, notifications, and a SwiftUI-backed UI toolkit, among others. This guide
gets you from an empty config to a handful of working automations, and flags the handful of
conventions that aren't obvious from the API reference alone — most importantly, how object
lifetime works. If you're arriving from Hammerspoon 1, read the
[migration guide](migration-guide.html) instead — it assumes v1 knowledge; this guide
doesn't.

## Your config file

Your automations live in one JavaScript file, `init.js`, in the config directory you chose
during onboarding (typically `~/.config/Hammerspoon2/`). You can find the exact paths at any
time from the console:

```js
console.log(hs.appinfo.configPath)  // the init.js file itself
console.log(hs.appinfo.configDir)   // the directory it lives in
```

`init.js` is plain JavaScript, evaluated top to bottom, once, when Hammerspoon starts or when
you reload. There's no special config format or entry-point function to implement — top-level
code runs immediately, and anything you want to keep running (hotkeys, watchers, timers, UI)
needs to be set up explicitly, as covered below.

**Reloading:** pick "Reload Config" from the menu bar icon, or call `hs.reload()` yourself
from a hotkey — reloading is itself an ordinary API call, useful for building a "reload
config" hotkey. By default this tears down the JavaScript runtime and re-evaluates `init.js`
from scratch, without a full app relaunch; a "Relaunch on reload" setting exists if you'd
rather have a clean process each time (useful if you suspect native state, not just JS state,
is stuck).

**The console:** `hs.openConsole()` opens the log/REPL window; `console.log()`/`.warn()`/
`.error()`/`.info()`/`.debug()` write to it. Keep it open while you work — most mistakes show
up there first, as a thrown JS exception with a file/line number.

**Offline docs:** `hs.docs.show()` opens the full API reference bundled into the app, in case
you're scripting somewhere without a browser handy.

## Object lifecycle: running things keep running

Almost everything Hammerspoon hands back to you — a hotkey, a timer, a path watcher, a UI
window, a running task — is a JavaScript object backed by a real native resource. The rule for
how long it lives is the same one browsers and Node use for `setTimeout()` or a child process:

**Anything that is running keeps running, with its callbacks, until it finishes or you stop
it — whether or not you keep a reference to it.** A bound hotkey keeps firing, a started timer
keeps ticking, a running task keeps running until it exits, a shown window stays on screen.
So this works, and keeps working:

```js
hs.hotkey.bind(["cmd", "alt"], "h", () => {
    console.log("hello")
}, null, null)
```

"Running" means: a bound or enabled hotkey, a started timer, watcher, event tap, query or
search, a running task, a shown window, canvas, chooser, dialog, alert or menu bar item, a
playing sound, an open serial port, WebSocket or HTTP server, and a ping or share in flight.

**Keep a reference when you want to control it later.** Dropping the reference is *not* how
you stop something — call its `stop()`, `disable()`, `hide()`, `terminate()` or `destroy()`
instead, so you'll want the object around if you might do that:

```js
const ticker = hs.timer.doEvery(60, () => console.log("still here"))
// ... later ...
ticker.stop()
```

The same goes for anything you want to update later, such as a reactive value (`HSString`,
`HSColor`, `HSImage`) feeding a window.

**Things that aren't running are ordinary JavaScript objects.** A timer you created but never
started, a watcher you stopped, a task that has exited, or a window you hid is garbage collected
once nothing references it, like any other JS value. In particular, if you hide a window or
canvas and might show it again later, keep a reference to it.

`hs.reload()` stops everything, and if you've lost track of something you started,
`hs.activeObjects()` lists everything that's currently running:

```js
hs.activeObjects().forEach(obj => console.log(obj.toString()))
```

Modules with `on()`/`off()`/`once()` (`hs.pasteboard`, `hs.application`, `hs.usb`, and
others) take your callback function directly rather than handing back a separate object. You
need to keep a reference to the function only if you ever want to call `off()` with it later,
since removal matches on function identity, not on when/how it was registered:

```js
const onPaste = () => console.log("clipboard changed")
hs.pasteboard.on('change', onPaste)
// ... later ...
hs.pasteboard.off('change', onPaste)  // only works because we kept `onPaste` around
```

Use `once()` instead of `on()` if you only care about the next occurrence of an event — it
removes itself automatically, so there's no listener reference to track for removal at all.

## Hotkeys

`hs.hotkey.bind(mods, key, onPress, onRelease)` is the workhorse. Either callback can be
`null`:

```js
const lockScreen = hs.hotkey.bind(["cmd", "ctrl"], "l", () => {
    hs.power.lockScreen()
}, null, null)
```

The returned object supports `.enable()`, `.disable()`, `.isEnabled()`, and `.destroy()` if
you want to toggle or tear down a hotkey later; keep it in a variable if you might. There's also
`hs.hotkey.bindSpec(spec)`, which takes a single options object (`mods`, `key`, `pressed`,
`released`, `repeat`) instead of positional arguments, plus a `message` field for when you
want to self-document what a hotkey is for:

```js
hs.hotkey.bindSpec({
    mods: ["cmd"], key: "space", message: "Spotlight-like",
    pressed: () => console.log("pressed")
})
```

## Watching for changes

The `on()`/`off()`/`once()` pattern shown above is consistent across most modules that report
ongoing state changes — clipboard contents, application launch/quit, connected hardware, input
source and locale changes, system power/session events, and more (`hs.application`,
`hs.audiodevice`, `hs.camera`, `hs.keycodes`, `hs.locale`, `hs.pasteboard`, `hs.power`,
`hs.screen`, `hs.serial`, `hs.streamdeck`, `hs.usb`, `hs.userdefaults`, `hs.wifi`). For these, the first
argument is always the event name; most modules emit several, so check the API reference for
the exact set a given module supports:

```js
hs.application.on('didLaunch', app => console.log(`launched: ${app.title}`))
```

`hs.ax` uses the same `on()`/`off()`/`once()` names but a different argument order —
`hs.ax.on(element, notification, listener)` — since a listener there is scoped to one specific
accessibility element, not just an event name:

```js
const app = hs.application.frontmost()
hs.ax.on(app.axElement(), hs.ax.notificationTypes.windowCreated, (notification, element) => {
    console.log("New window:", element.title)
})
```

Every one of these `on()`/`once()` functions follows the same rule: if the call returns, your
listener is registered *and* the underlying system watcher is running. If the watcher can't be
started (missing hardware, missing Accessibility permission, an element whose app has quit,
and so on), the call throws an `Error` instead (and logs it to the Console), and nothing is registered,
so it's safe to simply try again later. If your config needs to keep going when a watcher
can't be started, wrap the call in `try`/`catch`:

```js
try {
    hs.usb.on('added', device => console.log(`connected: ${device.productName}`))
} catch (err) {
    console.error(err.message)  // e.g. "hs.usb.on(): failed to start watcher for 'added'"
}
```

A handful of modules instead return a configurable watcher object rather than taking your
callback directly — `hs.location`, `hs.eventtap` (whose `addWatcher()` also takes an event-types
array and a listen-only flag), and `hs.fs`'s path watcher. Once started, these keep running
until you stop them, so keep a reference to the object if you'll want to.

For filesystem changes specifically, `hs.fs.createPathWatcher(path)` returns an object you
configure and start:

```js
const docsWatcher = hs.fs.createPathWatcher("~/Documents")
docsWatcher.setCallback((paths, flags) => {
    paths.forEach((p, i) => console.log(`${flags[i].join(",")}: ${p}`))
}).start()
```

Events batch with roughly a second of latency — don't expect sub-second delivery.

## Talking to the rest of macOS: Promises

Anything that could take a while — running AppleScript/JXA, making an HTTP request, launching
an app — returns a Promise rather than taking a completion-callback argument:

```js
hs.osascript.applescript(`tell application "Finder" to name of every disk`)
    .then((result) => {
        if (result.success) {
            console.log(result.result)
        } else {
            console.error(`osascript failed: ${result.raw}`)
        }
    })
```

Note the shape there: `hs.osascript`'s Promise always *resolves*, even when the script itself
failed — check `result.success` rather than reaching for `.catch()`. Other modules do reject
on failure, so check the API reference for the specific module you're calling.

`hs.application.launchOrFocus(bundleID)` follows the same Promise pattern for the common
"open this app, or bring it to the front if it's already running" case:

```js
hs.application.launchOrFocus("com.apple.Safari").then((ok) => {
    console.log(ok ? "Focused Safari" : "Couldn't launch/focus Safari")
})
```

## Moving windows around

`hs.window` gives you direct queries and single-window actions — there's no persistent
filter/subscription/layout system, so this section is deliberately simple:

```js
const win = hs.window.focusedWindow()
if (win) {
    const screenFrame = win.screen.frame
    win.frame = new HSRect(
        screenFrame.x,
        screenFrame.y,
        screenFrame.w / 2,
        screenFrame.h
    )
}
```

`win.frame` is a settable property — assign it a new `HSRect` to move and resize a window in
one step. `HSPoint`/`HSRect`/`HSSize` (constructed directly with `new HSRect(x, y, w, h)`, and
so on) carry the geometry math you'd want — `centerOnScreen()` on the window itself covers the
common recentering case without any manual math at all.

## Building UI with hs.ui

`hs.ui` is how you put anything on screen — alerts, dialogs, custom windows, live-updating
overlays. It works on two ideas that are worth understanding before you write any code:

1. **You build a declarative tree once, with a chained builder.** Call `hs.ui.window({x, y, w,
   h})` to start, then chain layout containers (`.vstack()`, `.hstack()`, `.zstack()`),
   content (`.text()`, `.image()`, `.button()`, `.rectangle()`, `.circle()`), and styling
   (`.fill()`, `.frame()`, `.font()`, `.foregroundColor()`) or interaction (`.onClick()`,
   `.onHover()`) calls that apply to whatever element preceded them. Containers close with
   `.end()`. Finish with `.show()`. There's no "append an element to an existing window"
   call — to change the *structure* of what's on screen, you build a new tree and show it.
2. **Anything that changes after the window is shown goes through a reactive value, not a
   setter on the window.** Create one with `HSString`/`hs.ui.string(...)`, `HSColor.hex(...)`/
   `.rgb(...)`/`.named(...)`, or an `HSImage`, pass it in where you'd otherwise pass a plain
   value, and later call `.set()` on *that value itself* — from a hotkey callback, a timer, a
   watcher, wherever. The on-screen element updates automatically; you never touch the window
   object again for that update.

The simplest possible case, a self-dismissing alert:

```js
hs.ui.alert("Saved!").duration(2).show()
```

A small window with a couple of elements and a click handler:

```js
const win = hs.ui.window({ x: 100, y: 100, w: 240, h: 120 })
    .windowTitle("Quick Actions")
    .vstack()
        .text("Pick something:")
        .button("Lock screen").onClick(() => hs.power.lockScreen())
        .button("Close").onClick(() => win.hide())
    .end()
    .show()
```

(A shown window stays on screen whether or not you keep `win`, but here the Close button hides
it, and a hidden window nobody references is garbage collected. Keep `win` in a top-level
`const`, as here, if you want to `show()` it again later.)

And a window whose text updates live via a reactive value, driven by a timer:

```js
const clockText = hs.ui.string(new Date().toLocaleTimeString())

const clockWindow = hs.ui.window({ x: 20, y: 20, w: 160, h: 60 })
    .vstack()
        .text(clockText)
    .end()
    .show()

const clockTimer = hs.timer.doEvery(1, () => {
    clockText.set(new Date().toLocaleTimeString())
})
```

`clockText`, `clockWindow`, and `clockTimer` all need to stay reachable — that's three
separate objects this example relies on staying alive, and dropping any one of them (e.g.
building `clockText` inline inside the `.text()` call instead of assigning it first) would
mean losing the ability to update it later, or the timer/window disappearing under GC.

## Splitting a growing config into multiple files

`init.js` doesn't have to hold everything. `require(path)` loads another JS file as its own
module — the same shape as Node's `require()`: give it something to hand back by setting
`module.exports` (or individual properties on `exports`), and that's what the caller gets back.

```js
// window-management.js
const LEFT_HALF = new HSRect(0, 0, 0.5, 1)  // a unit rect: left half of whichever screen it's applied to

function centerFocused() {
    const win = hs.window.focusedWindow()
    if (win) win.centerOnScreen()
}

function snapLeft() {
    const win = hs.window.focusedWindow()
    if (win) win.frame = LEFT_HALF.fromUnitRect(win.screen.frame)
}

module.exports = { centerFocused, snapLeft, LEFT_HALF }
```

```js
// init.js
const { centerFocused, snapLeft } = require("./window-management.js")
hs.hotkey.bind(["cmd", "alt"], "c", centerFocused)
hs.hotkey.bind(["cmd", "alt"], "left", snapLeft)
```

`module.exports` isn't limited to functions — it's a plain object, so export whatever a
caller needs: functions, constants, config objects, `HSRect`/`HSColor` values, anything. The
example above exports two functions and a reusable `HSRect` constant (`LEFT_HALF`) side by
side, and `init.js` picks out only the pieces it wants via destructuring.

A few things worth knowing about how paths resolve:

- **Local files need an explicit `./` or `../` prefix.** `require("foo.js")` — no prefix — is
  not the same as `require("./foo.js")` and won't find a file sitting next to `init.js`.
  Absolute paths and `~/...` paths also work directly.
- **The `.js` extension is optional** — `require("./utils")` and `require("./utils.js")` are
  equivalent.
- **Requiring a directory looks for `index.js`** inside it.
- **`.json` files are parsed automatically** — `require("./settings.json")` returns the parsed
  object, not a string.
- **Modules are cached by resolved path.** Requiring the same file twice from anywhere in your
  config returns the identical `exports` object both times rather than re-evaluating it.

**Scope:** each required file's top-level code runs inside its own private function, not
global scope — a `var`/`let`/`const`/function declared at the top of `window-management.js` is
invisible everywhere else, including `init.js`; `module.exports` is the only way to hand
anything back. `init.js` itself is the one exception — it runs unwrapped at true global scope —
so a required file *can* read whatever `init.js` declared at its own top level, but not the other
way around, and two required files can't see each other's declarations either. Don't lean on
that asymmetry deliberately; pass values between files through `module.exports` instead.

## Where to go from here

The [API reference](index.html) covers every module and type in full, with parameters and
examples for each method — this guide only scratched the surface of what's available. Want to
install someone else's packaged automation, or share your own? See the
[Spoons guide](spoons-guide.html). Prefer writing your config in TypeScript? See the
[TypeScript guide](typescript-guide.html). Coming from Hammerspoon 1? See the
[migration guide](migration-guide.html) for what moved, what changed shape, and what has no v2
equivalent yet.
