//
//  hs.serial.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying IOKit watcher on the first listener (for either event) and stops
// it once the last listener (across both events) is removed. See Engine/engine.js for
// LazyWatcherEmitter itself.
hs.serial._watcherEmitter = new LazyWatcherEmitter("hs.serial", function() {
    return hs.serial._addWatcher((eventType, portInfo) => {
        hs.serial._watcherEmitter.emit(eventType, portInfo);
    });
}, function() {
    hs.serial._removeWatcher();
}, hs.serial._eventNames);

/// Register a listener for serial port connection and disconnection events.
/// Parameters:
///  - event: {"added" | "removed"} The event to listen for
///  - listener: {(port: {name: string, path: string}) => void} Called when a matching serial port event occurs
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.serial.on('added', port => console.log("connected: " + port.name))
///     hs.serial.on('removed', port => console.log("removed: " + port.name))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.serial.on = function(event, listener) {
    hs.serial._watcherEmitter.on(event, listener);
};

/// Remove a previously registered serial port event listener.
/// Parameters:
///  - event: {"added" | "removed"} The event the listener was registered for
///  - listener: {(port: object) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onAdded = port => console.log(port.name)
/// hs.serial.on('added', onAdded)
/// // later…
/// hs.serial.off('added', onAdded)
/// ```
hs.serial.off = function(event, listener) {
    hs.serial._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for a serial port event.
/// Parameters:
///  - event: {"added" | "removed"} The event to listen for
///  - listener: {(port: object) => void} Called the next time a matching event occurs, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.serial.once('added', port => console.log("First port seen: " + port.name))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.serial.once = function(event, listener) {
    hs.serial._watcherEmitter.once(event, listener);
};
