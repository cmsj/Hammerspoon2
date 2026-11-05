//
//  hs.spoons.js
//  Hammerspoon 2
//

"use strict";

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
///  - options: {{source?: string, ref?: string, sha256?: string, config?: Record<string, any>, hotkeys?: Record<string, any> | "default", fn?: (spoon: Object) => void, start?: boolean, disable?: boolean}} `source`, `ref` and `sha256` say where to install the Spoon from, as for `hs.spoons.install()`. `config` holds properties to set on the Spoon's object; which ones it reads is up to the Spoon. `hotkeys` is passed to the Spoon's `bindHotkeys()`, or `"default"` passes its `defaultHotkeys`. `fn` is called with the Spoon after it's configured. `start: true` calls its `start()`. `disable: true` does nothing at all, which is easier than commenting the call out.
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
