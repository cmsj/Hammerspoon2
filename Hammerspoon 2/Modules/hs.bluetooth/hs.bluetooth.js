//
//  hs.bluetooth.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying IOBluetooth notifications on the first listener (for either event)
// and stops them once the last listener (across both events) is removed. See Engine/engine.js for
// LazyWatcherEmitter itself.
hs.bluetooth._watcherEmitter = new LazyWatcherEmitter("hs.bluetooth", function() {
    return hs.bluetooth._addWatcher((eventType, device) => {
        hs.bluetooth._watcherEmitter.emit(eventType, device);
    });
}, function() {
    hs.bluetooth._removeWatcher();
}, hs.bluetooth._eventNames);

/// Register a listener for Bluetooth device connection and disconnection events.
/// Parameters:
///  - event: {"connected" | "disconnected"} The event to listen for
///  - listener: {(device: {name: string, address: string, connected: boolean, paired: boolean, classOfDevice: number, majorClass: number, minorClass: number, serviceClasses: number, rssi?: number}) => void} Called when a device connects or disconnects
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.bluetooth.on('connected', device => console.log(device.name + " connected"))
///     hs.bluetooth.on('disconnected', device => console.log(device.name + " disconnected"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.bluetooth.on = function(event, listener) {
    hs.bluetooth._watcherEmitter.on(event, listener);
};

/// Remove a previously registered Bluetooth device event listener.
/// Parameters:
///  - event: {"connected" | "disconnected"} The event the listener was registered for
///  - listener: {(device: object) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onConnected = device => console.log(device.name)
/// hs.bluetooth.on('connected', onConnected)
/// // later…
/// hs.bluetooth.off('connected', onConnected)
/// ```
hs.bluetooth.off = function(event, listener) {
    hs.bluetooth._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for a Bluetooth device event.
/// Parameters:
///  - event: {"connected" | "disconnected"} The event to listen for
///  - listener: {(device: object) => void} Called the next time a matching device event occurs, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.bluetooth.once('connected', device => console.log("First connection: " + device.name))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.bluetooth.once = function(event, listener) {
    hs.bluetooth._watcherEmitter.once(event, listener);
};
