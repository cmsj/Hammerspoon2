//
//  hs.spaces.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying active-space-change watcher on the first listener and stops it
// once the last listener is removed. See Engine/engine.js for LazyWatcherEmitter itself.
hs.spaces._watcherEmitter = new LazyWatcherEmitter("hs.spaces", function() {
    return hs.spaces._addWatcher((event) => {
        hs.spaces._watcherEmitter.emit(event);
    });
}, function() {
    hs.spaces._removeWatcher();
}, hs.spaces._eventNames);

/// Register a listener that fires whenever the active space changes, on any display.
/// Parameters:
///  - event: {"change"} The event to listen for (the only event this module emits)
///  - listener: {() => void} Called with no arguments when the active space changes; call focusedSpace()/activeSpaces() inside it to inspect the new state
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.spaces.on('change', () => console.log("Now on space " + hs.spaces.focusedSpace()))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.spaces.on = function(event, listener) {
    hs.spaces._watcherEmitter.on(event, listener);
};

/// Remove a previously registered space change listener.
/// Parameters:
///  - event: {"change"} The event the listener was registered for
///  - listener: {() => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onChange = () => console.log("space changed")
/// hs.spaces.on('change', onChange)
/// // later…
/// hs.spaces.off('change', onChange)
/// ```
hs.spaces.off = function(event, listener) {
    hs.spaces._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once, the next time the active space changes.
/// Parameters:
///  - event: {"change"} The event to listen for
///  - listener: {() => void} Called once, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.spaces.once('change', () => console.log("First space change detected"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.spaces.once = function(event, listener) {
    hs.spaces._watcherEmitter.once(event, listener);
};
