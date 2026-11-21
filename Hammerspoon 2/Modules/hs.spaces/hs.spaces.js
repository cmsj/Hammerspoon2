//
//  hs.spaces.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying active-space-change watcher on the first listener and stops it
// once the last listener is removed. See Engine/engine.js for LazyWatcherEmitter itself.
hs.spaces._watcherEmitter = new LazyWatcherEmitter("hs.spaces", function() {
    return hs.spaces._addWatcher((event, details) => {
        hs.spaces._watcherEmitter.emit(event, details);
    });
}, function() {
    hs.spaces._removeWatcher();
}, hs.spaces._eventNames);

/// Register a listener that fires whenever a display switches to a different space. If several displays switch at once, it fires once for each.
/// Parameters:
///  - event: {"change"} The event to listen for (the only event this module emits)
///  - listener: {(change: {display: HSSpacesDisplay, from: HSSpace | null, to: HSSpace}) => void} Called with the display that switched, the space it was showing before (`null` for a display that has just been connected), and the space it's showing now
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.spaces.on('change', ({ display, to }) => console.log(display.screen.name + " is now showing space " + to.id))
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
///  - listener: {(change: {display: HSSpacesDisplay, from: HSSpace | null, to: HSSpace}) => void} The function originally passed to `on`
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

/// Register a listener that fires at most once, the next time a display switches to a different space.
/// Parameters:
///  - event: {"change"} The event to listen for
///  - listener: {(change: {display: HSSpacesDisplay, from: HSSpace | null, to: HSSpace}) => void} Called once, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.spaces.once('change', ({ to }) => console.log("Switched to space " + to.id))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.spaces.once = function(event, listener) {
    hs.spaces._watcherEmitter.once(event, listener);
};
