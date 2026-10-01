//
//  hs.usb.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying IOKit watcher on the first listener (for either event) and stops
// it once the last listener (across both events) is removed. See Engine/engine.js for
// LazyWatcherEmitter itself.
hs.usb._watcherEmitter = new LazyWatcherEmitter("hs.usb", function() {
    const started = hs.usb._addWatcher((eventType, deviceInfo) => {
        hs.usb._watcherEmitter.emit(eventType, deviceInfo);
    });
    if (!started) {
        throw new Error("hs.usb.on(): Failed to start USB watcher");
    }
}, function() {
    hs.usb._removeWatcher();
});

/// Register a listener for USB device connection and disconnection events.
/// Parameters:
///  - event: {string} The event to listen for: `"added"` or `"removed"`
///  - listener: {(device: {productName: string, vendorName: string, productID: number, vendorID: number, serialNumber?: string, locationID?: number}) => void} Called when a matching device event occurs
/// Example:
/// ```js
/// hs.usb.on('added', device => console.log(device.vendorName + " " + device.productName + " connected"))
/// hs.usb.on('removed', device => console.log(device.vendorName + " " + device.productName + " removed"))
/// ```
hs.usb.on = function(event, listener) {
    hs.usb._watcherEmitter.on(event, listener);
};

/// Remove a previously registered USB device event listener.
/// Parameters:
///  - event: {string} The event the listener was registered for (`"added"` or `"removed"`)
///  - listener: {(device: object) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onAdded = device => console.log(device.productName)
/// hs.usb.on('added', onAdded)
/// // later…
/// hs.usb.off('added', onAdded)
/// ```
hs.usb.off = function(event, listener) {
    hs.usb._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for a USB device event.
/// Parameters:
///  - event: {string} The event to listen for: `"added"` or `"removed"`
///  - listener: {(device: object) => void} Called the next time a matching device event occurs, then automatically removed
/// Example:
/// ```js
/// hs.usb.once('added', device => console.log("First device seen: " + device.productName))
/// ```
hs.usb.once = function(event, listener) {
    hs.usb._watcherEmitter.once(event, listener);
};
