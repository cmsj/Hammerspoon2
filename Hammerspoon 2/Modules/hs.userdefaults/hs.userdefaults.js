// hs.userdefaults.js
// JavaScript enhancements for the hs.userdefaults module

"use strict";

// Lazily starts a KVO observer for a given key on its first listener, and stops it once the
// last listener for that key is removed. Unlike LazyWatcherEmitter (used by e.g. hs.usb), each
// key's native watcher here is entirely independent of every other key's - see
// Engine/engine.js for KeyedLazyWatcherEmitter.
hs.userdefaults._watcherEmitter = new KeyedLazyWatcherEmitter("hs.userdefaults", function(key) {
    hs.userdefaults._addWatcher(key, (k, newValue) => {
        hs.userdefaults._watcherEmitter.emit(k, newValue);
    });
}, function(key) {
    hs.userdefaults._removeWatcher(key);
});

/// Watch a key for changes.
/// Parameters:
///  - key: {string} The name of the setting to watch
///  - listener: {(newValue: any) => void} Called with the new value whenever this key changes
/// Example:
/// ```js
/// hs.userdefaults.on("username", (newValue) => {
///     console.log("username changed to " + newValue)
/// })
/// ```
hs.userdefaults.on = function(key, listener) {
    hs.userdefaults._watcherEmitter.on(key, listener);
};

/// Remove a previously registered watcher.
/// Parameters:
///  - key: {string} The name of the setting originally passed to `on`
///  - listener: {(newValue: any) => void} The function originally passed to `on`
/// Example:
/// ```js
/// hs.userdefaults.off("username", myHandler)
/// ```
hs.userdefaults.off = function(key, listener) {
    hs.userdefaults._watcherEmitter.off(key, listener);
};

/// Register a listener that fires at most once for changes to a key.
/// Parameters:
///  - key: {string} The name of the setting to watch
///  - listener: {(newValue: any) => void} Called once, then automatically removed
/// Example:
/// ```js
/// hs.userdefaults.once("username", (newValue) => console.log("First change:", newValue))
/// ```
hs.userdefaults.once = function(key, listener) {
    hs.userdefaults._watcherEmitter.once(key, listener);
};
