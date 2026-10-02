//
//  hs.locale.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying locale-change watcher on the first listener and stops it once
// the last listener is removed. See Engine/engine.js for LazyWatcherEmitter itself. hs.locale
// only ever emits one kind of event ("change"), but on/off/once still take an explicit event
// name for consistency with every other hs.* module-level watcher.
hs.locale._watcherEmitter = new LazyWatcherEmitter("hs.locale", function() {
    hs.locale._addWatcher(() => {
        hs.locale._watcherEmitter.emit('change');
    });
}, function() {
    hs.locale._removeWatcher();
});

/// Register a listener that fires whenever any of the user's locale settings change.
/// Read `current()` or `details()` inside the listener to inspect the new state.
/// Parameters:
///  - event: {"change"} The event to listen for (the only event this module emits)
///  - listener: {() => void} Called with no arguments when locale settings change
/// Example:
/// ```js
/// hs.locale.on('change', () => console.log("Locale changed to: " + hs.locale.current()))
/// ```
hs.locale.on = function(event, listener) {
    hs.locale._watcherEmitter.on(event, listener);
};

/// Remove a previously registered locale change listener.
/// Parameters:
///  - event: {"change"} The event the listener was registered for
///  - listener: {() => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onChange = () => console.log("changed")
/// hs.locale.on('change', onChange)
/// // later…
/// hs.locale.off('change', onChange)
/// ```
hs.locale.off = function(event, listener) {
    hs.locale._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once, the next time locale settings change.
/// Parameters:
///  - event: {"change"} The event to listen for
///  - listener: {() => void} Called once, then automatically removed
/// Example:
/// ```js
/// hs.locale.once('change', () => console.log("First change detected"))
/// ```
hs.locale.once = function(event, listener) {
    hs.locale._watcherEmitter.once(event, listener);
};
