//
//  hs.screen.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying display-configuration-change watcher on the first listener and
// stops it once the last listener is removed. See Engine/engine.js for LazyWatcherEmitter itself.
// hs.screen only ever emits one kind of event ("change"), but on/off/once still take an explicit
// event name for consistency with every other hs.* module-level watcher.
hs.screen._watcherEmitter = new LazyWatcherEmitter("hs.screen", function() {
    hs.screen._addWatcher(() => {
        hs.screen._watcherEmitter.emit('change');
    });
}, function() {
    hs.screen._removeWatcher();
});

/// Register a listener that fires whenever the display configuration changes — monitors
/// connected/disconnected displays, resolution or arrangement changes, or the menu bar moving
/// to a different display.
/// Parameters:
///  - event: {"change"} The event to listen for (the only event this module emits)
///  - listener: {() => void} Called with no arguments when the display configuration changes; call all()/main()/primary() inside it to inspect the new configuration
/// Example:
/// ```js
/// hs.screen.on('change', () => console.log("Screens changed, now: " + hs.screen.all().length))
/// ```
hs.screen.on = function(event, listener) {
    hs.screen._watcherEmitter.on(event, listener);
};

/// Remove a previously registered display-configuration listener.
/// Parameters:
///  - event: {"change"} The event the listener was registered for
///  - listener: {() => void} The function originally passed to `on`
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

/// Register a listener that fires at most once, the next time the display configuration changes.
/// Parameters:
///  - event: {"change"} The event to listen for
///  - listener: {() => void} Called once, then automatically removed
/// Example:
/// ```js
/// hs.screen.once('change', () => console.log("First change detected"))
/// ```
hs.screen.once = function(event, listener) {
    hs.screen._watcherEmitter.once(event, listener);
};
