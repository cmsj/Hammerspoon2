"use strict";

// Lazily starts the underlying IOKit watcher on the first listener (for either event) and stops
// it once the last listener (across both events) is removed. See Engine/engine.js for
// LazyWatcherEmitter itself.
hs.streamdeck._watcherEmitter = new LazyWatcherEmitter("hs.streamdeck", function() {
    hs.streamdeck._addWatcher((event, device) => {
        hs.streamdeck._watcherEmitter.emit(event, device);
    });
}, function() {
    hs.streamdeck._removeWatcher();
});

/// Register a listener for Stream Deck connect/disconnect events.
/// Parameters:
///  - event: {string} The event to listen for: `"connected"` or `"disconnected"`
///  - listener: {(device: HSStreamDeckDevice) => void} Called with the affected device when a matching event occurs
/// Example:
/// ```js
/// hs.streamdeck.on('connected', device => console.log("connected: " + device.deckType))
/// hs.streamdeck.on('disconnected', device => console.log("disconnected: " + device.deckType))
/// ```
hs.streamdeck.on = function(event, listener) {
    hs.streamdeck._watcherEmitter.on(event, listener);
};

/// Remove a previously registered Stream Deck connect/disconnect listener.
/// Parameters:
///  - event: {string} The event the listener was registered for (`"connected"` or `"disconnected"`)
///  - listener: {(device: HSStreamDeckDevice) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onConnected = device => console.log(device.deckType)
/// hs.streamdeck.on('connected', onConnected)
/// // later…
/// hs.streamdeck.off('connected', onConnected)
/// ```
hs.streamdeck.off = function(event, listener) {
    hs.streamdeck._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for a Stream Deck connect/disconnect event.
/// Parameters:
///  - event: {string} The event to listen for: `"connected"` or `"disconnected"`
///  - listener: {(device: HSStreamDeckDevice) => void} Called the next time a matching event occurs, then automatically removed
/// Example:
/// ```js
/// hs.streamdeck.once('connected', device => console.log("First deck seen: " + device.deckType))
/// ```
hs.streamdeck.once = function(event, listener) {
    hs.streamdeck._watcherEmitter.once(event, listener);
};
