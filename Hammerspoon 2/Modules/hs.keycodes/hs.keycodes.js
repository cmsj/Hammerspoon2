//
//  hs.keycodes.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying input-source-change watcher on the first listener and stops it
// once the last listener is removed. See Engine/engine.js for LazyWatcherEmitter itself.
// hs.keycodes only ever emits one kind of event ("change"), but on/off/once still take an
// explicit event name for consistency with every other hs.* module-level watcher.
hs.keycodes._watcherEmitter = new LazyWatcherEmitter("hs.keycodes", function() {
    return hs.keycodes._addWatcher((event) => {
        hs.keycodes._watcherEmitter.emit(event);
    });
}, function() {
    hs.keycodes._removeWatcher();
}, hs.keycodes._eventNames);

/// Register a listener that fires whenever the keyboard input source changes.
/// Read `currentLayout()`, `currentSourceID()`, or `map` inside the listener to inspect the new
/// state.
/// Parameters:
///  - event: {"change"} The event to listen for (the only event this module emits)
///  - listener: {() => void} Called with no arguments when the input source changes
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.keycodes.on('change', () => console.log("Now using: " + hs.keycodes.currentLayout()))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.keycodes.on = function(event, listener) {
    hs.keycodes._watcherEmitter.on(event, listener);
};

/// Remove a previously registered input source change listener.
/// Parameters:
///  - event: {"change"} The event the listener was registered for
///  - listener: {() => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onChange = () => console.log("changed")
/// hs.keycodes.on('change', onChange)
/// // later…
/// hs.keycodes.off('change', onChange)
/// ```
hs.keycodes.off = function(event, listener) {
    hs.keycodes._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once, the next time the keyboard input source changes.
/// Parameters:
///  - event: {"change"} The event to listen for
///  - listener: {() => void} Called once, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.keycodes.once('change', () => console.log("First change detected"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.keycodes.once = function(event, listener) {
    hs.keycodes._watcherEmitter.once(event, listener);
};
