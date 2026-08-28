Hammerspoon 2 runs a JavaScript file of yours inside a real macOS app, and gives that
JavaScript access to a large surface of system APIs — windows, hotkeys, the filesystem,
Wi-Fi, AppleScript, notifications, and a SwiftUI-backed UI toolkit, among others. This guide
gets you from an empty config to a handful of working automations, and flags the handful of
conventions that aren't obvious from the API reference alone — most importantly, how object
lifetime works, since it's the single most common source of "this stopped working for no
reason" bug reports. If you're arriving from Hammerspoon 1, read the
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

## Object lifecycle: the one habit that saves you the most debugging time

Almost everything Hammerspoon hands back to you — a hotkey, a timer, a path watcher, a
UI window, a reactive value — is a live JavaScript object backed by a real native resource
underneath. As long as your JavaScript keeps a reference to it, that resource stays alive. The
moment nothing in your JS references it any more, JavaScriptCore's garbage collector is free
to collect it — and Hammerspoon then tears down whatever it was backing: the hotkey stops
firing, the timer stops ticking, the window closes. This is normal JS garbage collection
behavior, not a Hammerspoon bug, but it catches people because the failure is silent and can
take a while to show up (GC doesn't necessarily run the instant the object becomes
unreachable).

Concretely, this is the mistake:

```js
// Nothing keeps a reference to what bind() returns. It works today, and may
// simply stop firing after the next garbage collection.
hs.hotkey.bind(["cmd", "alt"], "h", () => {
    console.log("hello")
})
```

And this is the fix — capture the return value in a variable that lives as long as your
config does, typically a top-level `const` in `init.js`:

```js
const helloHotkey = hs.hotkey.bind(["cmd", "alt"], "h", () => {
    console.log("hello")
})
```

`helloHotkey` never needs to be read again for this to work — its mere existence as a
reachable variable is what keeps the hotkey alive. The same rule applies to anything returned
from a factory-style call: `hs.hotkey.bind()`/`bindSpec()`, `hs.timer.create()`/`doEvery()`/
`doAfter()`, `hs.fs.createPathWatcher()`, `hs.ui.window()`/`alert()`/`dialog()` while it's
still showing, and any reactive value (`HSString`, `HSColor`, `HSImage`) you intend to update
later. If you're building several of these, a single top-level array works well as a catch-all:

```js
const keepAlive = []
keepAlive.push(hs.hotkey.bind(["cmd", "alt"], "h", () => console.log("hello")))
keepAlive.push(hs.timer.doEvery(60, () => console.log("still here")))
```

One family of APIs behaves differently: modules with `addWatcher()`/`removeWatcher()` (
`hs.pasteboard`, `hs.screen`, `hs.wifi`, `hs.application`, and others) take your callback
function directly rather than handing back a separate object — the module itself holds the
reference, so you don't need a variable just to keep it alive. You *do* still need to keep a
reference to the function if you ever want to call `removeWatcher()` with it later, since
removal matches on function identity, not on when/how it was registered:

```js
const onPaste = () => console.log("clipboard changed")
hs.pasteboard.addWatcher(onPaste)
// ... later ...
hs.pasteboard.removeWatcher(onPaste)  // only works because we kept `onPaste` around
```

If a hotkey, timer, or watcher you built mysteriously stops working after your config has been
running a while, this is the first thing to check.

## Hotkeys

`hs.hotkey.bind(mods, key, onPress, onRelease)` is the workhorse. Either callback can be
`null`:

```js
const lockScreen = hs.hotkey.bind(["cmd", "ctrl"], "l", () => {
    hs.power.lockScreen()
}, null)
```

The returned object supports `.enable()`, `.disable()`, `.isEnabled()`, and `.destroy()` if
you want to toggle or tear down a hotkey deliberately, rather than waiting on GC. There's also
`hs.hotkey.bindSpec(mods, key, message, onPress, onRelease)`, identical except for an extra
description string, for when you want to self-document what a hotkey is for.

## Watching for changes

The `addWatcher()`/`removeWatcher()` pattern shown above is consistent across most modules
that report ongoing state changes — clipboard contents, display configuration, application
launch/quit, and more. `hs.screen`'s watcher is a typical example; the callback takes no
arguments, so query current state from inside it:

```js
hs.screen.addWatcher(() => {
    console.log(`Screen layout changed, now ${hs.screen.all().length} screen(s)`)
})
```

A few modules (`hs.wifi`, `hs.fs`'s path watcher) instead return a configurable watcher
object rather than taking your callback directly — the same lifecycle rule from above
applies to those, since the object itself is what needs to stay referenced.

For filesystem changes specifically, `hs.fs.createPathWatcher(path)` returns an object you
configure and start (remember: keep a reference to it):

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

(Note the same lifecycle rule applies here — `win` needs to stay referenced for as long as you
want the window to exist. `hs.ui` windows are also usually kept open indefinitely on purpose,
unlike a hotkey you set up once and forget about, so it's common to see them assigned to a
top-level `const` right alongside your hotkeys.)

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
function centerFocused() {
    const win = hs.window.focusedWindow()
    if (win) win.centerOnScreen()
}

module.exports = { centerFocused }
```

```js
// init.js
const { centerFocused } = require("./window-management.js")
hs.hotkey.bind(["cmd", "alt"], "c", centerFocused)
```

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

## Where to go from here

The [API reference](index.html) covers every module and type in full, with parameters and
examples for each method — this guide only scratched the surface of what's available.
Coming from Hammerspoon 1? See the [migration guide](migration-guide.html) for what moved,
what changed shape, and what has no v2 equivalent yet.
