//
//  hs.spoons.js
//  Hammerspoon 2
//

"use strict";

// The bindHotkeys() functions made by makeHotkeyMethods(), so loading a Spoon again keeps its own
const generatedBindHotkeys = new WeakSet();

// Called by hs.spoons.load() before the Spoon's init(). A Spoon that exports `bindings` gets a
// generic bindHotkeys() and unbindHotkeys() for them, replacing any it exports itself. Otherwise,
// the Spoon's own methods, if any, are left as they are.
/// SKIP_DOCS
hs.spoons._installBindHotkeys = function(spoon, spoonName) {
    const bindings = spoon.bindings;
    if (bindings === null || typeof bindings !== "object") {
        return;
    }
    if (generatedBindHotkeys.has(spoon.bindHotkeys)) {
        return;
    }
    for (const method of ["bindHotkeys", "unbindHotkeys"]) {
        if (typeof spoon[method] === "function") {
            console.warn(`hs.spoons: '${spoonName}' exports both bindings and ${method}(); its ${method}() is replaced by one for its bindings`);
        }
    }
    const { bindHotkeys, unbindHotkeys } = makeHotkeyMethods(spoon, spoonName);
    generatedBindHotkeys.add(bindHotkeys);
    spoon.bindHotkeys = bindHotkeys;
    spoon.unbindHotkeys = unbindHotkeys;
};

// Makes a bindHotkeys() and unbindHotkeys() for a Spoon's `bindings`. See `bindings` in
// docs/spoons-guide.md for the shapes they accept.
function makeHotkeyMethods(spoon, spoonName) {
    // Action name -> the HSHotkey bound for it, so binding an action again replaces its hotkey.
    // No prototype, so an action named e.g. "constructor" isn't mistaken for a bound one.
    const bound = Object.create(null);

    function invalid(message, method = "bindHotkeys") {
        const err = new Error(`${spoonName}.${method}(): ${message}`);
        err.code = "EINVALIDARG";
        return err;
    }

    // A binding is a function (called when pressed), or {pressed?, released?, repeat?, message?}
    function callbacksFor(action) {
        const binding = spoon.bindings[action];
        if (typeof binding === "function") {
            return { pressed: binding, released: null, repeat: null, message: null };
        }
        if (binding !== null && typeof binding === "object") {
            const callbacks = { message: typeof binding.message === "string" ? binding.message : null };
            for (const event of ["pressed", "released", "repeat"]) {
                const fn = binding[event];
                if (fn !== undefined && fn !== null && typeof fn !== "function") {
                    throw invalid(`bindings.${action}.${event} must be a function`);
                }
                callbacks[event] = fn ?? null;
            }
            if (callbacks.pressed || callbacks.released || callbacks.repeat) {
                return callbacks;
            }
        }
        throw invalid(`bindings.${action} must be a function, or an object with a pressed, released or repeat function`);
    }

    // A spec is [mods, key, message?] or {mods, key, message?}. message `true` uses the Spoon's own.
    function hotkeyFor(action, spec) {
        if (typeof spec !== "object") {
            throw invalid(`the hotkey for '${action}' must be [mods, key, message?] or {mods, key, message?}`);
        }
        const [mods, key, message] = Array.isArray(spec) ? spec : [spec.mods, spec.key, spec.message];
        if (!Array.isArray(mods) || !mods.every(m => typeof m === "string")) {
            throw invalid(`the modifiers for '${action}' must be an array of strings`);
        }
        if (typeof key !== "string" && typeof key !== "number") {
            throw invalid(`the key for '${action}' must be a string or a number`);
        }
        if (message !== undefined && message !== null && typeof message !== "string" && typeof message !== "boolean") {
            throw invalid(`the message for '${action}' must be a string or a boolean`);
        }
        return { mods, key, message };
    }

    function bindHotkeys(mapping) {
        if (mapping === null || typeof mapping !== "object" || Array.isArray(mapping)) {
            throw invalid("the mapping must be an object, keyed by action name");
        }
        const bindings = spoon.bindings;
        const actions = bindings !== null && typeof bindings === "object" ? Object.keys(bindings) : [];

        // Check everything before binding anything, so a mistake doesn't leave half of it bound
        const plan = [];
        for (const [action, spec] of Object.entries(mapping)) {
            if (!Object.hasOwn(bindings ?? {}, action)) {
                throw invalid(`'${action}' isn't one of ${spoonName}'s actions (${actions.join(", ") || "it has none"})`);
            }
            const callbacks = callbacksFor(action);
            const hotkey = spec === null || spec === undefined || spec === false ? null : hotkeyFor(action, spec);
            plan.push({ action, callbacks, hotkey });
        }

        // Release every hotkey being replaced before binding any, so actions can swap keys
        for (const { action } of plan) {
            if (bound[action]) {
                bound[action].destroy();
                delete bound[action];
            }
        }

        for (const { action, callbacks, hotkey } of plan) {
            if (!hotkey) {
                continue;
            }
            const hk = hs.hotkey.bind(hotkey.mods, hotkey.key, callbacks.pressed, callbacks.released, callbacks.repeat);
            if (!hk) {
                throw invalid(`couldn't bind '${action}' to ${JSON.stringify([hotkey.mods, hotkey.key])}`);
            }
            if (hotkey.message === true) {
                if (callbacks.message) hk.message = `${spoonName}: ${callbacks.message}`;
            } else if (typeof hotkey.message === "string") {
                hk.message = hotkey.message;
            }
            bound[action] = hk;
        }
        return spoon;
    }

    function unbindHotkeys(actions) {
        if (actions !== undefined && actions !== null && !(Array.isArray(actions) && actions.every(a => typeof a === "string"))) {
            throw invalid("the actions must be an array of action names", "unbindHotkeys");
        }
        const bindings = spoon.bindings;
        for (const action of actions ?? []) {
            if (!Object.hasOwn(bindings ?? {}, action)) {
                throw invalid(`'${action}' isn't one of ${spoonName}'s actions (${Object.keys(bindings ?? {}).join(", ") || "it has none"})`, "unbindHotkeys");
            }
        }
        for (const action of actions ?? Object.keys(bound)) {
            if (bound[action]) {
                bound[action].destroy();
                delete bound[action];
            }
        }
        return spoon;
    }

    return { bindHotkeys, unbindHotkeys };
}

/// Load and configure a Spoon in one step, installing it first if it isn't installed yet - the
/// built-in equivalent of Hammerspoon 1's SpoonInstall:andUse().
///
/// If the Spoon is already installed, it's loaded and configured before `use()` returns, so
/// `hs.spoons.<name>` can be used on the very next line, and nothing is downloaded. If it isn't
/// installed and `source` is given, it's installed in the background (see `hs.spoons.install()`),
/// then loaded and configured, and a notification says so; put anything that needs the Spoon in
/// `fn`, or after the returned Promise resolves. An installed Spoon is never updated by `use()`:
/// call `hs.spoons.update()` for that.
///
/// `path` loads the Spoon from a directory of your own instead, as `hs.spoons.load()` does, for
/// developing a Spoon: nothing is installed, and an installed copy is ignored. It takes precedence
/// over `source`, `ref` and `sha256`, which are ignored while it's given, so a config can keep its
/// `source` for everyone else and add `path` while you work on the Spoon.
///
/// Configuration is applied after the Spoon is loaded (and its `init()` has run), in this order:
/// each property of `config` is set on the Spoon's object, exactly as if you'd assigned it
/// yourself, `hotkeys` is passed to its `bindHotkeys()` method, `fn` is called with the Spoon,
/// and finally `start()` is called if `start` is true.
///
/// The Promise rejects with an `Error` with a `code`, as `hs.spoons.install()`'s does, plus
/// `ENOTINSTALLED` if the Spoon isn't installed and no `source` was given, or the error thrown by
/// loading or configuring the Spoon.
/// Parameters:
///  - name: {string} The name of the Spoon
///  - options?: How to install, load and configure the Spoon
///    - source?: {string} Where to install the Spoon from if it isn't installed, as for `hs.spoons.install()`
///    - ref?: {string} The branch, tag or commit to install from, as for `hs.spoons.install()`
///    - sha256?: {string} The expected SHA-256 of the download, as for `hs.spoons.install()`
///    - path?: {string} A directory to load the Spoon from instead (relative to your config
///      directory), as for `hs.spoons.load()`. Takes precedence over `source`, `ref` and `sha256`
///    - config?: {Record<string, any>} Properties to set on the Spoon's object; which ones it
///      reads is up to the Spoon
///    - hotkeys?: {Record<string, any> | "default"} Passed to the Spoon's `bindHotkeys()`, or
///      `"default"` passes its `defaultHotkeys`
///    - fn?: {(spoon: Object) => void} Called with the Spoon after it's configured
///    - start?: {boolean} `true` calls the Spoon's `start()` last
///    - disable?: {boolean} `true` does nothing at all, which is easier than commenting the call out
/// Returns: {Promise<Object | null>} Resolves with the Spoon once it's loaded and configured, or null if `disable` is true
/// Example:
/// ```js
/// hs.spoons.use("Greeter", {
///     source: "jane/hs2-spoons",
///     ref: "v1.2.0",
///     config: { message: "Time for a break!" },
///     hotkeys: { show: [["cmd", "alt"], "g"] },
///     fn: (greeter) => console.log(`Using Greeter ${greeter.version}`),
///     start: true
/// }).catch(err => console.error(`Couldn't use Greeter: ${err.message}`))
///
/// // While working on Greeter, use your own copy of it. source is ignored until path is removed.
/// hs.spoons.use("Greeter", {
///     source: "jane/hs2-spoons",
///     path: "~/src/hs2-spoons/Greeter.spoon2",
///     start: true
/// })
/// ```
hs.spoons.use = function(name, options) {
    const opts = options ?? {};

    function fail(code, message) {
        const err = new Error(`hs.spoons.use(): ${message}`);
        err.code = code;
        return Promise.reject(err);
    }

    if (typeof name !== "string") {
        return fail("EINVALIDARG", "name must be a string");
    }
    if (typeof opts !== "object") {
        return fail("EINVALIDARG", "options must be an object");
    }
    if (opts.fn !== undefined && typeof opts.fn !== "function") {
        return fail("EINVALIDARG", "fn must be a function");
    }
    if (opts.disable) {
        return Promise.resolve(null);
    }

    // Configures a loaded Spoon, throwing if any step does
    function configure(spoon) {
        if (opts.config) {
            Object.assign(spoon, opts.config);
        }
        if (opts.hotkeys) {
            const mapping = opts.hotkeys === "default" ? spoon.defaultHotkeys : opts.hotkeys;
            if (mapping) {
                if (typeof spoon.bindHotkeys !== "function") {
                    throw new Error(`hs.spoons.use(): '${name}' has no bindHotkeys() method for the hotkeys option`);
                }
                spoon.bindHotkeys(mapping);
            }
        }
        if (opts.fn) {
            opts.fn(spoon);
        }
        if (opts.start) {
            if (typeof spoon.start !== "function") {
                throw new Error(`hs.spoons.use(): '${name}' has no start() method for the start option`);
            }
            spoon.start();
        }
        return spoon;
    }

    if (opts.path !== undefined && opts.path !== null) {
        try {
            return Promise.resolve(configure(hs.spoons.load(name, { path: opts.path })));
        } catch (err) {
            return Promise.reject(err);
        }
    }

    let spoon;
    try {
        spoon = hs.spoons.load(name);
    } catch (err) {
        if (err.code !== "ENOTINSTALLED") {
            return Promise.reject(err);
        }
        if (opts.source === undefined) {
            return fail("ENOTINSTALLED", `No Spoon named '${name}' is installed, and no source was given to install it from`);
        }

        const installOptions = { source: opts.source };
        if (opts.ref !== undefined) installOptions.ref = opts.ref;
        if (opts.sha256 !== undefined) installOptions.sha256 = opts.sha256;

        return hs.spoons.install(name, installOptions).then(info => {
            // The Spoon is installed either way, so a notification that can't be shown mustn't
            // fail the whole thing
            try {
                hs.notify.show("Spoon installed", `${info.name} ${info.version} was installed from ${info.source}`);
            } catch (err) {
                console.error(`hs.spoons.use(): couldn't show a notification: ${err.message}`);
            }
            return configure(hs.spoons.load(name));
        });
    }

    try {
        return Promise.resolve(configure(spoon));
    } catch (err) {
        return Promise.reject(err);
    }
};
