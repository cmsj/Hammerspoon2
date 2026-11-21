//
//  hs.screen.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying display-configuration and space change watcher on the first
// listener and stops it once the last listener is removed. See Engine/engine.js for
// LazyWatcherEmitter itself.
hs.screen._watcherEmitter = new LazyWatcherEmitter("hs.screen", function() {
    return hs.screen._addWatcher((event, details) => {
        hs.screen._watcherEmitter.emit(event, details);
    });
}, function() {
    hs.screen._removeWatcher();
}, hs.screen._eventNames);

/// Register a listener for screen events.
///
/// `"change"` fires whenever the display configuration changes — monitors connected/disconnected, resolution or arrangement changes, or the menu bar moving to a different display. The listener gets no arguments; call all()/main()/primary() inside it to inspect the new configuration.
///
/// `"spaceChange"` fires whenever a screen switches to a different space. If several screens switch at once, it fires once for each. The listener gets an object with the `screen` that switched (`null` if it has just been disconnected), the space it was showing before (`from`, `null` for a screen that has just been connected), and the space it's showing now (`to`).
/// Parameters:
///  - event: {"change" | "spaceChange"} The event to listen for
///  - listener: {(change?: {screen: HSScreen | null, from: HSSpace | null, to: HSSpace}) => void} Called when the event happens; see above for its argument
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.screen.on('change', () => console.log("Screens changed, now: " + hs.screen.all().length))
///     hs.screen.on('spaceChange', ({ screen, to }) => console.log(screen.name + " is now showing space " + to.id))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.screen.on = function(event, listener) {
    hs.screen._watcherEmitter.on(event, listener);
};

/// Remove a previously registered screen event listener.
/// Parameters:
///  - event: {"change" | "spaceChange"} The event the listener was registered for
///  - listener: {(change?: {screen: HSScreen | null, from: HSSpace | null, to: HSSpace}) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onChange = () => console.log("screens changed")
/// hs.screen.on('change', onChange)
/// // later…
/// hs.screen.off('change', onChange)
/// ```
hs.screen.off = function(event, listener) {
    hs.screen._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once, the next time a screen event happens. See `on()` for the events.
/// Parameters:
///  - event: {"change" | "spaceChange"} The event to listen for
///  - listener: {(change?: {screen: HSScreen | null, from: HSSpace | null, to: HSSpace}) => void} Called once, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.screen.once('change', () => console.log("First change detected"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.screen.once = function(event, listener) {
    hs.screen._watcherEmitter.once(event, listener);
};
