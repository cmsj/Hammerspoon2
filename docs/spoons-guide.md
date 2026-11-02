Spoons are packaged, reusable pieces of Hammerspoon configuration — a way to install someone
else's automation (or share your own) without copy-pasting code into `init.js`. This guide
covers installing and using a Spoon first, then how to write one, with a complete worked
example. If you haven't read the [Getting Started guide](getting-started.html) yet, especially
its section on [object lifecycle](getting-started.html#object-lifecycle-running-things-keep-running)
and [splitting a config across multiple files](getting-started.html#splitting-a-growing-config-into-multiple-files),
start there — everything below builds on it.

This part of Hammerspoon 2 is newer and smaller in scope than the rest of the app. One piece of
Hammerspoon 1 lifecycle *is* built in - `init()` is called automatically, same as v1's `:init()`
- but `start()`/`stop()` and `bindHotkeys()` below are recommended patterns for Spoon authors to
follow, not things the runtime calls for you (unless you ask `hs.spoons.use()` to).

## Installing Spoons from GitHub or a URL

Most Spoons are shared through their authors' own GitHub repositories. There's no central list
of Spoons: you choose where each one comes from. The easiest way to use one is
`hs.spoons.use()`, which installs the Spoon the first time your config runs, and then loads and
configures it:

```js
hs.spoons.use("Greeter", {
    source: "jane/hs2-spoons",           // a GitHub repository
    ref: "v1.2.0",                       // optional: a tag, branch or commit
    config: { message: "Time for a break!" },
    hotkeys: { show: [["cmd", "alt"], "g"] },
    start: true
})
```

If the Spoon is already installed, `use()` loads and configures it straight away, without
touching the network, so `hs.spoons.Greeter` works on the next line. If it isn't, it's
downloaded and installed in the background, and configured once that finishes (with a
notification to say so). `use()` returns a Promise that resolves with the Spoon once it's
ready, so put anything that needs a freshly-installed Spoon in a `.then()`, or in the `fn`
option, which is called with the Spoon after `config` and `hotkeys` are applied and before
`start()`:

```js
hs.spoons.use("Greeter", {
    source: "jane/hs2-spoons",
    fn: (greeter) => greeter.setMessage("Hello!")
}).catch(err => console.error(`Couldn't use Greeter: ${err.message}`))
```

`source` can be:

- a GitHub repository, as `"owner/repo"` or `"https://github.com/owner/repo"`. `ref` picks a
  tag, branch or commit; without it, the repository's default branch is used.
- the `https://` URL of any zip file — a GitHub release download, a GitLab or Codeberg archive,
  or a file on your own web server. Pass `sha256` with the file's SHA-256 hash, and the install
  fails rather than installing anything else.

Hammerspoon 2 finds the Spoons in what it downloads by looking for `*.spoon2` directories at the
top level, or in a `Spoons` directory. A repository or zip file that *is* a single Spoon (with
`spoon.json` and `init.js` at its top level) works too.

The other functions give you finer control:

```js
// What's in a repository?
hs.spoons.available("jane/hs2-spoons")
    .then(spoons => spoons.forEach(s => console.log(`${s.name} ${s.version}: ${s.description}`)))

// Install without loading
hs.spoons.install("Greeter", { source: "jane/hs2-spoons", ref: "v1.2.0" })
    .then(info => console.log(`Installed ${info.name} ${info.version}`))

// What's installed, and where from
hs.spoons.installed().forEach(s => console.log(`${s.name} ${s.version} from ${s.source}`))

// Download again from where it was installed from, and reinstall if its version changed
hs.spoons.update("Greeter").then(updated => console.log(updated ? "Updated" : "Up to date"))

hs.spoons.uninstall("Greeter")
```

Failures reject with an `Error` whose `code` says what went wrong (`ENOTFOUND`, `ENETWORK`,
`EINTEGRITY`, `EEXISTS`, ...), so you can tell them apart in a `.catch()`.

**Only install Spoons from people you trust.** A Spoon is code that runs with all of
Hammerspoon 2's permissions. Pinning a version — a tag or commit with `ref`, or a `sha256` for a
zip file — means you keep running the code you chose, even if the repository changes later.
`use()` never updates a Spoon that's already installed; `update()` is the only thing that
does, and only when you call it. It fetches the Spoon from exactly where it was installed from,
so a Spoon pinned to a tag or commit stays as it is — to move to a newer version, install it
with the new `ref` and `force: true`.

## Installing a Spoon by hand

A Spoon is distributed as a `.spoon2` bundle — a folder that macOS treats as a single
double-clickable item, the same way it treats `.app`. Double-clicking one (or dragging it onto
the Hammerspoon 2 icon) installs it: Hammerspoon 2 checks that it's well-formed, copies it into
`Spoons/` inside your config directory (typically `~/.config/Hammerspoon2/Spoons/`), and
confirms with a dialog once it's done. If a Spoon with the same name is already installed, you're
asked to confirm before it's replaced — the dialog shows both the currently-installed and the
new version so you can tell what's changing.

Installing a Spoon doesn't load it. Loading is an explicit step in your `init.js`, covered next.

## Using a Spoon

Call `hs.spoons.load("Name")`, matching the Spoon's directory name under `Spoons/`:

```js
const Greeter = hs.spoons.load("Greeter")
```

This throws if the Spoon is missing or malformed, so wrap it in a `try`/`catch` if you want your
config to keep going without it rather than fail to load entirely:

```js
try {
    const Greeter = hs.spoons.load("Greeter")
    Greeter.start()
} catch (e) {
    console.error(`Couldn't load Greeter: ${e.message}`)
}
```

`load()` also stores whatever it returns on `hs.spoons`, keyed by name, so anywhere else in
your config can reach an already-loaded Spoon without holding onto the value yourself:

```js
hs.spoons.load("Greeter")
// ...elsewhere...
hs.spoons.Greeter.show("Hello again")
```

If the Spoon exposes `start()`/`stop()` methods (see [conventions](#conventions-worth-following)
below), call `start()` yourself after loading — nothing calls it for you:

```js
const Greeter = hs.spoons.load("Greeter")
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
non-empty, or `hs.spoons.load()` refuses to load it:

```json
{
    "name": "Greeter",
    "author": "Jane Dev <jane@example.com>",
    "version": "1.0.0",
    "description": "Shows a friendly notification on a hotkey or a timer."
}
```

You never need to repeat this information inside `init.js` — after a successful load,
`hs.spoons.load()` sets `author`, `description`, and `version` directly on the object your Spoon
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
JS, so this works too) — `hs.spoons.load()` throws if it doesn't, since that's what the injected
metadata needs to attach itself to. Keep the top level of `init.js` light: build the object and
return it, but avoid starting timers, watchers, or hotkeys until `start()` is called (or, for a
Spoon simple enough not to need a `start()`/`stop()` split at all, until the caller invokes
whatever method actually needs them). Anything started keeps running until it's stopped
(see [object lifecycle](getting-started.html#object-lifecycle-running-things-keep-running)), so
`stop()` needs references to what `start()` started.

**If the returned object has an `init()` method, it's called automatically** — matching
Hammerspoon 1, where `:init()` ran the same way. Use it for setup that needs to happen once the
object exists but shouldn't wait for `start()` — reading a config file, computing a derived
value, and so on. `this` inside `init()` refers to the object itself, and by the time it runs,
`author`/`description`/`version` are already set on `this`, since metadata injection happens
first. A thrown exception inside `init()` fails the whole load: `hs.spoons.load()` throws, and
nothing is stored on `hs.spoons`.

One subtlety worth knowing: `init.js`'s own top level only ever runs once (`require()` caches
the module), but `init()` runs again every time `hs.spoons.load()` is called for that Spoon, since
the same cached object is handed back each time. Write `init()` to be safe to call more than
once — or better, do true one-time setup directly at `init.js`'s top level, and reserve `init()`
for things that are genuinely fine to redo.

## Conventions worth following

Two further conventions are worth following for consistency with how other Spoons will likely
behave, even though — unlike `init()` — nothing in the runtime calls them for you:

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
const Greeter = hs.spoons.load("Greeter")
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

function init() {
    // Called automatically by hs.spoons.load(). author/description/version are already set on
    // `this` by this point - safe to log or read, but this could run more than once, so avoid
    // anything that shouldn't happen twice.
    console.log(`[Greeter] v${this.version} initialized`)
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

module.exports = { show, setMessage, init, start, stop, bindHotkeys }
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
const Greeter = hs.spoons.load("Greeter")
Greeter.setMessage("Time for a break!")
Greeter.bindHotkeys({ show: [["cmd", "alt"], "g"] })
Greeter.start()

console.log(`Loaded ${Greeter.description} v${Greeter.version} by ${Greeter.author}`)
```

## Sharing a Spoon

Rename the `Greeter` folder to `Greeter.spoon2` — that's the whole packaging step, since a
`.spoon2` bundle *is* the Spoon's directory, just with a different extension so macOS and
Hammerspoon 2 recognize it as installable. Then either:

- **Push it to a GitHub repository.** Put `Greeter.spoon2` at the top of the repository (or in
  a `Spoons` directory, alongside any others you've written), and people can install it with
  `hs.spoons.use("Greeter", { source: "you/your-repo" })`. There's no build step and nothing to
  generate. Tag your releases, so people can pin a version with `ref`, and add the
  `hammerspoon2-spoon` topic to the repository, so people can find it by searching GitHub.
- **Hand someone the bundle**, or a zip of it. Double-clicking it runs the install flow
  described above, and `hs.spoons.install()` can install the zip from any `https://` URL.

## Differences from Hammerspoon 1 Spoons, in brief

If you're coming from v1, the shape is familiar but several specifics changed:

- **`.spoon2`, not `.spoon`** — a deliberate rename so the two aren't confused; v1 and v2 Spoons
  aren't interchangeable, and existing v1 Spoons won't load in v2 unless rewritten in JavaScript.
- **`spoon.json`, not fields on the returned table.** Required fields are `name`, `author`,
  `version`, `description` — v1 required `name`, `author`, `version`, `license` (with
  `homepage` optional). v2 doesn't currently check for a license field at all.
- **`init()` is called automatically, same as v1.** One difference worth knowing: v2's `require()`
  caches `init.js`'s top-level code (it only ever runs once), but `init()` itself runs again on
  every `hs.spoons.load()` call for that Spoon — see [above](#anatomy-of-a-spoon) for what that
  means for what you put in it.
- **`hs.spoons` has different helpers.** v1's `hs.spoons` had `resourcePath()`, `scriptPath()`,
  and `bindHotkeysToSpec()`. v2's `hs.spoons` has `load()`, the installing functions above, and
  every loaded Spoon by name — use `__dirname` (built into `require()`) in place of
  `resourcePath()`/`scriptPath()`, and see [`bindHotkeys()`](#conventions-worth-following) above
  for the closest equivalent to `bindHotkeysToSpec()`.
- **SpoonInstall is built in**, as `hs.spoons.use()` (v1's `andUse()`) and friends, but there's
  no default repository: each Spoon names its own `source`.
- **JavaScript, not Lua** — `module.exports = {...}` instead of `return obj` at the end of
  `init.lua`.

## Where to go from here

The [Getting Started guide](getting-started.html) covers the rest of the API a Spoon is likely
to use — hotkeys, timers, watchers, and `hs.ui`. Coming from Hammerspoon 1? The
[migration guide](migration-guide.html) covers everything else that changed.
