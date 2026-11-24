Spoons are packaged, reusable pieces of Hammerspoon configuration — a way to install someone
else's automation (or share your own) without copy-pasting code into `init.js`. This guide
covers installing and using a Spoon first, then how to write one, with a complete worked
example. If you haven't read the [Getting Started guide](getting-started.html) yet, especially
its section on [object lifecycle](getting-started.html#object-lifecycle-running-things-keep-running)
and [splitting a config across multiple files](getting-started.html#splitting-a-growing-config-into-multiple-files),
start there — everything below builds on it.

This part of Hammerspoon 2 is newer and smaller in scope than the rest of the app. One piece of
Hammerspoon 1 lifecycle *is* built in - `init()` is called automatically, same as v1's `:init()`
- and so is a generic `bindHotkeys()` for Spoons that export their actions as `bindings`, but
`start()`/`stop()` below are recommended patterns for Spoon authors to follow, not things the
runtime calls for you (unless you ask `hs.spoons.use()` to).

## Finding Spoons

There's no central list of Spoons: authors publish them in their own GitHub repositories, and
you choose where each one comes from. Good places to look:

- **The [`hammerspoon2-spoon` topic on GitHub](https://github.com/topics/hammerspoon2-spoon)**
  lists repositories whose authors have tagged them as containing Hammerspoon 2 Spoons. Each
  repository's README should say which Spoons it holds and how to configure them.
  [Searching for the topic](https://github.com/search?q=topic%3Ahammerspoon2-spoon&type=repositories)
  lets you sort them by stars or by when they were last updated.
- **[r/Hammerspoon](https://www.reddit.com/r/Hammerspoon)** is where people share Spoons and
  configs, and where you can ask whether something that does what you need already exists.

Make sure it's a Hammerspoon 2 Spoon (a `.spoon2` bundle written in JavaScript) and not a
Hammerspoon 1 `.spoon`, which won't load. As with any code you run in your config, read a
Spoon before installing it: it runs with all the permissions you've granted Hammerspoon 2.
Hammerspoon 1 Spoons are listed separately, on the
[Hammerspoon 1 Spoons site](https://www.hammerspoon.org/Spoons/).

## Installing Spoons from GitHub or a URL

Most Spoons are shared through their authors' own GitHub repositories (see
[Finding Spoons](#finding-spoons) above). The easiest way to use one is
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
    fn: (greeter) => greeter.show()
}).catch(err => console.error(`Couldn't use Greeter: ${err.message}`))
```

### `use()`'s options

`hs.spoons.use(name, options)` takes the Spoon's name (its directory name under `Spoons/`, and
the name it's stored under on `hs.spoons`) and an object of options, all of them optional:

| Option | What it does |
|--------|--------------|
| `source` | Where to install the Spoon from if it isn't installed: a GitHub repository or a zip file's URL (see below). Without it, `use()` only uses an installed Spoon, and rejects with `ENOTINSTALLED` if there isn't one. |
| `ref` | The tag, branch or commit to install from a GitHub `source`. |
| `sha256` | The SHA-256 hash a zip file `source` must have. |
| `path` | A directory to load the Spoon from instead, for working on a Spoon (see [Developing a Spoon](#developing-a-spoon)). It takes precedence over `source`, `ref` and `sha256`. |
| `config` | An object whose properties are set on the Spoon. |
| `hotkeys` | Passed to the Spoon's `bindHotkeys()` method. `"default"` passes the Spoon's own `defaultHotkeys` instead. |
| `fn` | A function that's called with the Spoon, for any setup the other options don't cover. |
| `start` | `true` calls the Spoon's `start()` method. |
| `disable` | `true` makes `use()` do nothing at all, which is quicker than commenting the call out. |

Once the Spoon is loaded (which runs its `init()`, if it has one), the options are applied in
the order they're listed: `config`, then `hotkeys`, then `fn`, then `start`. So by the time the
Spoon binds its hotkeys or starts, it's already been configured.

`config` is a shortcut for setting the Spoon's properties yourself. Each of its properties is
copied onto the object the Spoon exports, replacing whatever was there, so these do the same
thing:

```js
hs.spoons.use("Greeter", { config: { message: "Time for a break!", interval: 1800 } })

const Greeter = hs.spoons.load("Greeter")
Greeter.message = "Time for a break!"
Greeter.interval = 1800
```

Which properties mean anything is up to the Spoon, so check its documentation. Nothing checks
the names: a misspelled one just adds a property the Spoon never reads.

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

If you'd rather Hammerspoon 2 didn't install Spoons this way, turn off **Install Spoons when
opened** in the Advanced tab of Settings. Opened `.spoon2` bundles are then passed to your config
like any other opened file (see `hs.onOpenFile`), instead of being installed.

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

If the Spoon exposes `start()`/`stop()` methods (see [Lifecycle](#lifecycle)
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

**`init.js` must set `module.exports` to an object**, and not a function —
`hs.spoons.load()` throws if it doesn't, since that's what the metadata from `spoon.json` is
set on. Keep the top level of `init.js` light: build the object and
return it, but don't start timers, watchers or hotkeys there (see [Lifecycle](#lifecycle)).

What else the object holds is up to you. The next section covers the names that Hammerspoon 2,
`hs.spoons.use()` and your users expect to mean particular things.

## Conventions worth following

Apart from `module.exports` being an object, everything a Spoon exports is optional. But a few
names have a meaning that `hs.spoons.load()` and/or `hs.spoons.use()` can take advantage of, so use them
where they fit, and your Spoon will work the way people expect a Spoon to:

| Export | What it's for | What uses it |
|--------|---------------|--------------|
| `init()` | Setup once the Spoon's object exists | `hs.spoons.load()` calls it, every time |
| `start()` / `stop()` | Starting and stopping anything that keeps running | Users, and `use()`'s `start` option (`start()` only) |
| Settings | Properties that change how the Spoon behaves | Users, and `use()`'s `config` option |
| `bindings` | Actions users can bind hotkeys to | `hs.spoons.load()`, which makes a `bindHotkeys()` and `unbindHotkeys()` for them |
| `defaultHotkeys` | Suggested hotkeys for those actions | `use()`'s `hotkeys: "default"` option |
| `bindHotkeys(mapping)` | Binding hotkeys yourself, when `bindings` isn't enough | Users, and `use()`'s `hotkeys` option |

Don't export `name`, `author`, `description` or `version`: `hs.spoons.load()` sets them from
`spoon.json`, replacing anything of the same name.

### Lifecycle

`hs.spoons.load("Greeter")` does this, in order:

1. Runs `init.js` with `require()`. `require()` caches it, so the
   top level only ever runs once, however many times the Spoon is loaded.
2. Sets `name`, `author`, `description` and `version` on the exported object, from `spoon.json`.
3. Gives the object a `bindHotkeys()` and an `unbindHotkeys()`, if it exports `bindings` (see
   [Hotkeys](#hotkeys)).
4. Calls the object's `init()`, if it has one.
5. Stores the object in `hs.spoons` (as `hs.spoons.Greeter`) and returns it.

`hs.spoons.use()` then applies its options to the loaded Spoon: `config`, then `hotkeys`, then
`fn`, then `start` (see [`use()`'s options](#uses-options)).

**`init()`** is for setup that needs to happen once the object exists, but shouldn't wait for
`start()`: reading a file, working out a value from others, and so on. It's called with `this`
set to the object, which by then has its `spoon.json` fields, and its `bindHotkeys()` and
`unbindHotkeys()` if it exports `bindings`. Hammerspoon 1
called `:init()` the same way.

- **It runs on every `hs.spoons.load()`** of the Spoon, not just the first, since each one
  hands back the same cached object. Write it to be safe to run more than once, or do one-time
  setup at the top level of `init.js` instead.
- **It runs before `use()`'s `config` is applied**, so it only ever sees your settings' defaults
  (see [Configuration](#configuration)).
- **An exception thrown in it fails the load**: `hs.spoons.load()` throws it, and nothing is
  stored on `hs.spoons`.

**`start()` and `stop()`** are for a Spoon that does anything that keeps running: timers,
watchers, hotkeys that are always bound. Build the object and its settings in `init.js`, but
don't start anything until `start()` is called. Nothing in Hammerspoon 2 calls `start()` unless
a user passes `start: true` to `hs.spoons.use()` (which fails if there's no `start()`), and
nothing ever calls `stop()`; both are for users to call when they want to. Anything started
keeps running until it's stopped (see
[object lifecycle](getting-started.html#object-lifecycle-running-things-keep-running)), so keep
a reference to what `start()` starts, for `stop()` to stop. Make both safe to call twice:

```js
let timer = null

function start() {
    if (timer) return          // already started
    timer = hs.timer.doEvery(3600, () => show())
}

function stop() {
    if (timer) { timer.stop(); timer = null }
}
```

A Spoon with nothing to start, such as one whose only job is to provide actions for hotkeys,
doesn't need `start()` or `stop()` at all.

### Configuration

Make your Spoon's settings be properties of the exported object, set to their defaults, so
users can change them by setting them directly, or with `use()`'s `config` option. `config`
copies each of its properties onto your Spoon's object, and that's all it does. It doesn't call
anything to tell you, so:

- **Read a setting from the object whenever you use it**, rather than copying it into a
  variable. A variable in `init.js` can't be reached by `config`, and a copy taken earlier
  won't see the change.
- **Don't use settings in `init()`.** It runs during loading, before `config` is applied, so it
  only ever sees the defaults. `start()`, `bindHotkeys()` and the methods users call all run
  after `config`, so they see the user's values.
- **Document each setting** — its name, type and default — since that's how users find out
  what to put in `config`.

```js
const greeter = module.exports = {
    message: "Hello from Greeter!",  // the notification's text
    interval: 3600,                  // seconds between notifications once started
    show, start, stop
}

function show() {
    hs.notify.show("Greeter", greeter.message)   // not a copy of it taken earlier
}
```

If a setting needs checking, or something has to happen when it changes, make it a property
with a setter: `config` assigns properties, so the setter runs.

### Hotkeys

Don't bind hotkeys to keys of your choosing: let users choose their own. The recommended way is
to export **`bindings`**, the actions a hotkey can trigger, keyed by name, and Hammerspoon 2
does the binding for you:

```js
module.exports = {
    bindings: {
        show,                          // a function, called when the hotkey is pressed
        peek: {                        // or an object, for more control
            pressed: () => showPanel(),
            released: () => hidePanel(),
            repeat: null,              // called repeatedly while the hotkey is held down
            message: "Peek"            // a description users can choose to show (see below)
        }
    },
    // ...
}
```

Any of `pressed`, `released` and `repeat` can be left out, but there must be at least one.

`hs.spoons.load()` gives a Spoon that exports `bindings` a `bindHotkeys(mapping)` method, which
binds the hotkeys in `mapping`, keyed by action name, to those actions. That's also what
`hs.spoons.use()`'s `hotkeys` option calls. A hotkey is `[mods, key, message]` or
`{ mods, key, message }`, where `message` is optional:

```js
// in the user's init.js
const Greeter = hs.spoons.load("Greeter")
Greeter.bindHotkeys({
    show: [["cmd", "alt"], "g"],
    peek: { mods: ["cmd", "alt"], key: "p", message: true }
})
```

- **`message`** is shown when the hotkey is pressed, as for any hotkey (see
  `hs.hotkey`'s `message`). A string is used as it is, and `true` uses the action's own
  `message`, prefixed with the Spoon's name — `"Greeter: Peek"` above. Without one, nothing is
  shown.
- **Binding an action again replaces its hotkey**, and `null` (or `false`) in place of a hotkey
  unbinds it, so `bindHotkeys()` can be called as often as you like.
- **Mistakes throw**, with a `code` of `EINVALIDARG`: an action the Spoon doesn't have
  (so a misspelled name doesn't silently do nothing), or a hotkey of the wrong shape. Nothing in
  that call is bound if one of its hotkeys is wrong. If a key can't be bound (it's not a real key,
  or something else has it), it throws too. The actions before it in that call are bound, and
  the ones from it on have no hotkey, even if they had one before.
- **It returns the Spoon**, so calls can be chained.
- **It's there before `init()` runs**, so `init()` can call it too.

It also gets an **`unbindHotkeys(actions)`** method, which unbinds the hotkeys of the actions
named in `actions`, an array, or of all of them if `actions` is left out. An action without a
hotkey is skipped, and one the Spoon doesn't have throws, as for `bindHotkeys()`. It returns the
Spoon too.

```js
Greeter.unbindHotkeys(["peek"])   // just peek's hotkey
Greeter.unbindHotkeys()           // all of them
```

The hotkeys are the user's, so `stop()` usually shouldn't unbind them: a user may well have
bound a hotkey to start the Spoon again, or to toggle it. `unbindHotkeys()` is for when the
hotkeys should go too, such as a method that tears the Spoon down completely, or a user who
wants them gone. A Spoon that's loaded again keeps its hotkeys, so there's no need to unbind
them first.

If your Spoon has sensible keys to suggest, export them as **`defaultHotkeys`**, in the same
shape as `mapping`. Users can then pass `hotkeys: "default"` to `hs.spoons.use()` to bind them.

**Your own `bindHotkeys(mapping)`** is for when `bindings` can't do what your Spoon needs: say,
hotkeys that are only active while a mode is on, keys made up at runtime rather than chosen
from a fixed set of actions, or a mapping in some other shape. Export a `bindHotkeys()` method
instead of `bindings`, and it's kept as it is: users call it the same way, and `use()`'s
`hotkeys` option (including `"default"`) passes the mapping to it. It's then up to you to check
the mapping, and to unbind a hotkey that's bound again:

```js
let modal = null

module.exports = {
    bindHotkeys(mapping) {
        // The "enter" hotkey starts a mode in which "s" shows a greeting, and escape leaves it
        if (modal) modal.destroy()
        modal = hs.hotkey.createModal(mapping.enter[0], mapping.enter[1])
        modal.bind([], "escape", () => modal.exit())
        modal.bind([], "s", () => show())
        return this
    },
    // ...
}
```

Don't export both: if a Spoon exports both `bindings` and `bindHotkeys()` (or
`unbindHotkeys()`), `hs.spoons.load()` will replace them with the generic ones, and log a warning
to the Console.

### Logging

There's no per-Spoon logger like v1's `hs.logger` — use `console.log()`/`.error()` directly,
optionally prefixing messages with the Spoon's name so they're identifiable in a config that's
loaded several Spoons:

```js
console.log("[Greeter] started")
```

## A complete example

A small Spoon that shows a notification on demand, optionally repeating on a timer, with a
configurable message and interval, and a hotkey to trigger it immediately:

```js
// Greeter/init.js
let timer = null

const greeter = module.exports = {
    // Settings, which users can change with hs.spoons.use()'s config option
    message: "Hello from Greeter!",   // the notification's text
    interval: 3600,                   // seconds between notifications once started

    // Actions users can bind hotkeys to, with Greeter.bindHotkeys() or use()'s hotkeys option
    bindings: {
        show: { pressed: show, message: "Show a greeting" }
    },
    defaultHotkeys: { show: [["cmd", "alt"], "g"] },

    show, init, start, stop
}

function show() {
    hs.notify.show("Greeter", greeter.message)
}

function init() {
    // Called automatically by hs.spoons.load(). author/description/version are already set on
    // `this` by this point - safe to log or read, but this could run more than once, so avoid
    // anything that shouldn't happen twice. Settings still have their defaults here: config is
    // applied after init() runs.
    console.log(`[Greeter] v${this.version} initialized`)
}

function start() {
    if (timer) return
    timer = hs.timer.doEvery(greeter.interval, show)
    console.log("[Greeter] started")
}

function stop() {
    if (timer) { timer.stop(); timer = null }
    console.log("[Greeter] stopped")
}
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
hs.spoons.use("Greeter", {
    config: { message: "Time for a break!", interval: 1800 },
    hotkeys: "default",
    start: true
})
```

or, doing the same thing by hand:

```js
// init.js
const Greeter = hs.spoons.load("Greeter")
Greeter.message = "Time for a break!"
Greeter.interval = 1800
Greeter.bindHotkeys(Greeter.defaultHotkeys)
Greeter.start()

console.log(`Loaded ${Greeter.description} v${Greeter.version} by ${Greeter.author}`)
```

## Developing a Spoon

While you're writing or changing a Spoon, you want your config to run the copy you're editing,
not one installed into `Spoons/`. Give `hs.spoons.load()` or `hs.spoons.use()` a `path`, and
the Spoon is loaded straight from that directory, with nothing installed or copied:

```js
hs.spoons.use("Greeter", {
    source: "jane/hs2-spoons",                 // where everyone else gets it from
    path: "~/src/hs2-spoons/Greeter.spoon2",   // your working copy, which wins while it's here
    config: { message: "Time for a break!" },
    start: true
})
```

`path` takes precedence over `source` (and `ref` and `sha256`), so you can keep the `source`
the rest of the world uses in your config, and add or remove `path` as you start and stop
working on the Spoon. A relative path is relative to your config directory, so a Spoon checked
out next to it is `"../hs2-spoons/Greeter.spoon2"`, and `~` is your home directory. An installed
copy with the same name is ignored while `path` is there, and the Spoon is still stored as
`hs.spoons.Greeter`.

Reload your config to pick up your changes: `require()` only runs a file once per config load,
so edits to `init.js` and anything it requires take effect on the next reload.

A few things to know:

- If there's no directory at `path`, `load()` throws and `use()` rejects with `ENOTFOUND`. It
  doesn't fall back to `source`, so a typo in `path` doesn't quietly run the published version
  instead of yours.
- A warning is logged every time a Spoon is loaded from a `path`, so you'll notice if you forget
  to take it out.
- A Spoon loaded from a `path` isn't installed, so `hs.spoons.installed()`, `update()` and
  `uninstall()` don't know about it.

`hs.spoons.load("Greeter", { path: "..." })` does the same for a Spoon you load yourself.

## Sharing a Spoon

Rename the `Greeter` folder to `Greeter.spoon2` — that's the whole packaging step, since a
`.spoon2` bundle *is* the Spoon's directory, just with a different extension so macOS and
Hammerspoon 2 recognize it as installable. Then either:

- **Push it to a GitHub repository.** Put `Greeter.spoon2` at the top of the repository (or in
  a `Spoons` directory, alongside any others you've written), and people can install it with
  `hs.spoons.use("Greeter", { source: "you/your-repo" })`. There's no build step and nothing to
  generate. Tag your releases, so people can pin a version with `ref`, and add the
  `hammerspoon2-spoon` topic to the repository, so it shows up in the
  [list of Spoons on GitHub](https://github.com/topics/hammerspoon2-spoon). Posting about it on
  [r/Hammerspoon](https://www.reddit.com/r/Hammerspoon) helps people find it too.
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
  every `hs.spoons.load()` call for that Spoon — see [Lifecycle](#lifecycle) for what that
  means for what you put in it.
- **`hs.spoons` has different helpers.** v1's `hs.spoons` had `resourcePath()`, `scriptPath()`,
  and `bindHotkeysToSpec()`. v2's `hs.spoons` has `load()`, the installing functions above, and
  every loaded Spoon by name — use `__dirname` (built into `require()`) in place of
  `resourcePath()`/`scriptPath()`. In place of `bindHotkeysToSpec()`, export your actions as
  [`bindings`](#hotkeys), and `bindHotkeys()` is written for you, with
  `released` and `repeat` callbacks, and default messages, which v1's couldn't have.
- **SpoonInstall is built in**, as `hs.spoons.use()` (v1's `andUse()`) and friends, but there's
  no default repository: each Spoon names its own `source`.
- **JavaScript, not Lua** — `module.exports = {...}` instead of `return obj` at the end of
  `init.lua`.

## Where to go from here

The [Getting Started guide](getting-started.html) covers the rest of the API a Spoon is likely
to use — hotkeys, timers, watchers, and `hs.ui`. Coming from Hammerspoon 1? The
[migration guide](migration-guide.html) covers everything else that changed.
