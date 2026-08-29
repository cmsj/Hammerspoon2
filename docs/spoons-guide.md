Spoons are packaged, reusable pieces of Hammerspoon configuration — a way to install someone
else's automation (or share your own) without copy-pasting code into `init.js`. This guide
covers installing and using a Spoon first, then how to write one, with a complete worked
example. If you haven't read the [Getting Started guide](getting-started.html) yet, especially
its section on [object lifecycle](getting-started.html#object-lifecycle-the-one-habit-that-saves-you-the-most-debugging-time)
and [splitting a config across multiple files](getting-started.html#splitting-a-growing-config-into-multiple-files),
start there — everything below builds on it.

This part of Hammerspoon 2 is newer and smaller in scope than the rest of the app; the
conventions below (`start()`/`stop()`, `bindHotkeys()`) are recommended patterns for Spoon
authors to follow, not things the runtime enforces or calls automatically the way Hammerspoon 1
did for `:init()`.

## Installing a Spoon

A Spoon is distributed as a `.spoon2` bundle — a folder that macOS treats as a single
double-clickable item, the same way it treats `.app`. Double-clicking one (or dragging it onto
the Hammerspoon 2 icon) installs it: Hammerspoon 2 checks that it's well-formed, copies it into
`Spoons/` inside your config directory (typically `~/.config/Hammerspoon2/Spoons/`), and
confirms with a dialog once it's done. If a Spoon with the same name is already installed, you're
asked to confirm before it's replaced — the dialog shows both the currently-installed and the
new version so you can tell what's changing.

Installing a Spoon doesn't load it. Loading is an explicit step in your `init.js`, covered next.

## Using a Spoon

Call `hs.loadSpoon("Name")`, matching the Spoon's directory name under `Spoons/`:

```js
const Greeter = hs.loadSpoon("Greeter")
```

This throws if the Spoon is missing or malformed, so wrap it in a `try`/`catch` if you want your
config to keep going without it rather than fail to load entirely:

```js
try {
    const Greeter = hs.loadSpoon("Greeter")
    Greeter.start()
} catch (e) {
    console.error(`Couldn't load Greeter: ${e.message}`)
}
```

`loadSpoon()` also stores whatever it returns on `hs.spoons`, keyed by name, so anywhere else in
your config can reach an already-loaded Spoon without holding onto the value yourself:

```js
hs.loadSpoon("Greeter")
// ...elsewhere...
hs.spoons.Greeter.show("Hello again")
```

If the Spoon exposes `start()`/`stop()` methods (see [conventions](#conventions-worth-following)
below), call `start()` yourself after loading — nothing calls it for you:

```js
const Greeter = hs.loadSpoon("Greeter")
Greeter.start()
```

## Anatomy of a Spoon

A Spoon is a directory with two required files:

```
Greeter/
  spoon.json
  init.js
```

**`spoon.json`** carries the Spoon's identity. All four fields are required and must be
non-empty, or `hs.loadSpoon()` refuses to load it:

```json
{
    "name": "Greeter",
    "author": "Jane Dev <jane@example.com>",
    "version": "1.0.0",
    "description": "Shows a friendly notification on a hotkey or a timer."
}
```

You never need to repeat this information inside `init.js` — after a successful load,
`hs.loadSpoon()` sets `author`, `description`, and `version` directly on the object your Spoon
returns, reading them from `spoon.json`. This is a deliberate difference from Hammerspoon 1,
where a Spoon's Lua table had to declare `obj.name`/`obj.version`/`obj.author` itself, alongside
whatever else its `init.lua` set up — v2 gives you one source of truth instead of two that can
drift apart.

**`init.js`** is loaded through the same `require()` used for the rest of your config (see
[Splitting a growing config into multiple files](getting-started.html#splitting-a-growing-config-into-multiple-files)
if you haven't read that section), so the same rules apply: it gets its own private scope,
`require('./lib/something.js')` resolves relative to the Spoon's own directory, and `__dirname`
points at that directory too — useful for loading bundled assets:

```js
const iconPath = __dirname + "/icon.png"
```

**`init.js` must set `module.exports` to an object** (or a function — functions are objects in
JS, so this works too) — `hs.loadSpoon()` throws if it doesn't, since that's what the injected
metadata needs to attach itself to. Keep the top level of `init.js` light: build the object and
return it, but avoid starting timers, watchers, or hotkeys until `start()` is called (or, for a
Spoon simple enough not to need a `start()`/`stop()` split at all, until the caller invokes
whatever method actually needs them). This mirrors the [same lifecycle habit](getting-started.html#object-lifecycle-the-one-habit-that-saves-you-the-most-debugging-time)
that applies everywhere else in Hammerspoon 2 — something needs to keep a reference alive for as
long as it should keep running.

## Conventions worth following

Hammerspoon 2 doesn't call any method on your Spoon automatically — no auto-invoked `init()`
the way v1 had. Two conventions are still worth following for consistency with how other Spoons
will likely behave, even though nothing enforces them:

**`start()` / `stop()`** for a Spoon that does anything ongoing (timers, watchers, hotkeys bound
persistently). Build the object and its configuration in `init.js`, but don't activate anything
until `start()` runs:

```js
function start() {
    if (timer) return          // already started
    timer = hs.timer.doEvery(3600, () => show())
}

function stop() {
    if (timer) { timer.stop(); timer = null }
}
```

**`bindHotkeys(mapping)`** for a Spoon whose behavior a user should be able to trigger with a
hotkey, taking an object keyed by action name so the caller chooses their own keys rather than
the Spoon hardcoding them:

```js
function bindHotkeys(mapping) {
    if (mapping.show) {
        hs.hotkey.bind(mapping.show[0], mapping.show[1], () => show())
    }
}
```

```js
// in the user's init.js
const Greeter = hs.loadSpoon("Greeter")
Greeter.bindHotkeys({ show: [["cmd", "alt"], "g"] })
```

**Logging:** there's no per-Spoon logger like v1's `hs.logger` — use `console.log()`/`.error()`
directly, optionally prefixing messages with the Spoon's name so they're identifiable in a
config that's loaded several Spoons:

```js
console.log("[Greeter] started")
```

## A complete example

A small Spoon that shows a notification on demand, optionally repeating on a timer, with a
configurable message and a hotkey to trigger it immediately:

```js
// Greeter/init.js
let message = "Hello from Greeter!"
let timer = null

function show() {
    hs.notify.show("Greeter", message)
}

function setMessage(newMessage) {
    message = newMessage
    return module.exports          // returning `this`-equivalent enables chaining
}

function start() {
    if (timer) return
    timer = hs.timer.doEvery(3600, show)
    console.log("[Greeter] started")
}

function stop() {
    if (timer) { timer.stop(); timer = null }
    console.log("[Greeter] stopped")
}

function bindHotkeys(mapping) {
    if (mapping.show) {
        hs.hotkey.bind(mapping.show[0], mapping.show[1], show)
    }
}

module.exports = { show, setMessage, start, stop, bindHotkeys }
```

```json
// Greeter/spoon.json
{
    "name": "Greeter",
    "author": "Jane Dev <jane@example.com>",
    "version": "1.0.0",
    "description": "Shows a friendly notification on a hotkey or a timer."
}
```

Using it:

```js
// init.js
const Greeter = hs.loadSpoon("Greeter")
Greeter.setMessage("Time for a break!")
Greeter.bindHotkeys({ show: [["cmd", "alt"], "g"] })
Greeter.start()

console.log(`Loaded ${Greeter.description} v${Greeter.version} by ${Greeter.author}`)
```

To share this Spoon, rename the `Greeter` folder to `Greeter.spoon2` — that's the whole
packaging step, since a `.spoon2` bundle *is* the Spoon's directory, just with a different
extension so macOS and Hammerspoon 2 recognize it as installable. Zip it up or hand someone the
folder directly; double-clicking it runs the install flow described above.

## Differences from Hammerspoon 1 Spoons, in brief

If you're coming from v1, the shape is familiar but several specifics changed:

- **`.spoon2`, not `.spoon`** — a deliberate rename so the two aren't confused; v1 and v2 Spoons
  aren't interchangeable, and existing v1 Spoons won't load in v2 unless rewritten in JavaScript.
- **`spoon.json`, not fields on the returned table.** Required fields are `name`, `author`,
  `version`, `description` — v1 required `name`, `author`, `version`, `license` (with
  `homepage` optional). v2 doesn't currently check for a license field at all.
- **No automatic `:init()` call.** v1 called a Spoon's `:init()` method automatically if present;
  v2 calls nothing — `module.exports` is used as-is once `init.js` finishes running.
- **`hs.spoons` is a plain namespace, not a module.** v1's `hs.spoons` was a real module with
  helpers like `resourcePath()`, `scriptPath()`, and `bindHotkeysToSpec()`. v2's `hs.spoons` only
  holds loaded Spoons by name — use `__dirname` (built into `require()`) in place of
  `resourcePath()`/`scriptPath()`, and see [`bindHotkeys()`](#conventions-worth-following) above
  for the closest equivalent to `bindHotkeysToSpec()`.
- **JavaScript, not Lua** — `module.exports = {...}` instead of `return obj` at the end of
  `init.lua`, and no separate Spoons repository or discovery mechanism yet.

## Where to go from here

The [Getting Started guide](getting-started.html) covers the rest of the API a Spoon is likely
to use — hotkeys, timers, watchers, and `hs.ui`. Coming from Hammerspoon 1? The
[migration guide](migration-guide.html) covers everything else that changed.
