//
//  hs.bluetooth.js
//  Hammerspoon 2
//

"use strict";

// Each event has its own native source: IOBluetooth's connection notifications for
// 'connected'/'disconnected', CoreBluetooth's power state for 'powerChanged', and scan() for
// 'discovered'. So this uses KeyedLazyWatcherEmitter (see Engine/engine.js), which starts and
// stops each one only while that event has listeners.
hs.bluetooth._watcherEmitter = new KeyedLazyWatcherEmitter("hs.bluetooth", function(event) {
    return hs.bluetooth._addWatcher(event, (arg) => {
        hs.bluetooth._watcherEmitter.emit(event, arg);
    });
}, function(event) {
    hs.bluetooth._removeWatcher(event);
}, hs.bluetooth._eventNames);

/// Register a listener for Bluetooth events.
///
/// Listeners receive:
///  - `"connected"`, `"disconnected"`: the `HSBluetoothDevice` that connected or disconnected. This covers every device macOS connects, and BLE peripherals Hammerspoon connects with `connect()`. macOS doesn't report other apps' BLE connections.
///  - `"powerChanged"`: `true` when Bluetooth is turned on, `false` when it's turned off
///  - `"discovered"`: each `HSBluetoothDevice` found while `hs.bluetooth.scan()` runs
/// Parameters:
///  - event: {"connected" | "disconnected" | "powerChanged" | "discovered"} The event to listen for
///  - listener: {(arg: HSBluetoothDevice | boolean) => void} Called with the event's device, or for `"powerChanged"` the new power state
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.bluetooth.on('connected', device => console.log(device.name + " connected"))
///     hs.bluetooth.on('disconnected', device => console.log(device.name + " disconnected"))
///     hs.bluetooth.on('powerChanged', on => console.log("Bluetooth is " + (on ? "on" : "off")))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.bluetooth.on = function(event, listener) {
    hs.bluetooth._watcherEmitter.on(event, listener);
};

/// Remove a previously registered Bluetooth event listener.
/// Parameters:
///  - event: {"connected" | "disconnected" | "powerChanged" | "discovered"} The event the listener was registered for
///  - listener: {(arg: HSBluetoothDevice | boolean) => void} The function originally passed to `on`
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

/// Register a listener that fires at most once for a Bluetooth event.
/// Parameters:
///  - event: {"connected" | "disconnected" | "powerChanged" | "discovered"} The event to listen for
///  - listener: {(arg: HSBluetoothDevice | boolean) => void} Called the next time the event occurs, then automatically removed
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

// Factory for per-device emitters; called lazily from Swift on a device's first on()/once().
// A device's events all come through one native callback, so this is a plain LazyWatcherEmitter.
/// SKIP_DOCS
hs.bluetooth._makeDeviceEmitter = function(device) {
    return new LazyWatcherEmitter("hs.bluetooth device", function() {
        return device._addWatcher((event, ...args) => {
            device._watcherEmitter.emit(event, ...args);
        });
    }, function() {
        device._removeWatcher();
    }, device._eventNames);
};
