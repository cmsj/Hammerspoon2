//
//  hs.audiodevice.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying CoreAudio listener on the first listener (for any event) and
// stops it once the last listener (across all events) is removed. See Engine/engine.js for
// LazyWatcherEmitter itself.
hs.audiodevice._watcherEmitter = new LazyWatcherEmitter("hs.audiodevice", function() {
    return hs.audiodevice._addWatcher((event) => {
        hs.audiodevice._watcherEmitter.emit(event);
    });
}, function() {
    hs.audiodevice._removeWatcher();
}, hs.audiodevice._eventNames);

/// Register a listener for a named system-level audio configuration event.
/// Parameters:
///  - event: {"dOut" | "dIn" | "dSErr" | "dev+" | "dev-"} The event to listen for
///  - listener: {() => void} Called when the event occurs
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.audiodevice.on('dOut', () => console.log("Default output changed"))
///     hs.audiodevice.on('dev+', () => console.log("A device was added"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.audiodevice.on = function(event, listener) {
    hs.audiodevice._watcherEmitter.on(event, listener);
};

/// Remove a previously registered system-level audio event listener.
/// Parameters:
///  - event: {"dOut" | "dIn" | "dSErr" | "dev+" | "dev-"} The event the listener was registered for
///  - listener: {() => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onDefaultOutChange = () => console.log("changed")
/// hs.audiodevice.on('dOut', onDefaultOutChange)
/// // later…
/// hs.audiodevice.off('dOut', onDefaultOutChange)
/// ```
hs.audiodevice.off = function(event, listener) {
    hs.audiodevice._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for a system-level audio configuration event.
/// Parameters:
///  - event: {"dOut" | "dIn" | "dSErr" | "dev+" | "dev-"} The event to listen for
///  - listener: {() => void} Called the next time a matching event occurs, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.audiodevice.once('dev+', () => console.log("First device-added event seen"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.audiodevice.once = function(event, listener) {
    hs.audiodevice._watcherEmitter.once(event, listener);
};

// Factory for per-device emitters; called lazily from Swift when the first on()/once() call is
// made on a device. `device` is the HSAudioDevice instance; its own on/off/once methods (native
// Swift, not JS-assigned - a per-instance object has no enhancement script to hang them on)
// forward into this emitter.
/// SKIP_DOCS
hs.audiodevice._makeDeviceEmitter = function(device) {
    return new LazyWatcherEmitter("hs.audiodevice device", function() {
        return device._addWatcher((event) => {
            device._watcherEmitter.emit(event);
        });
    }, function() {
        device._removeWatcher();
    }, device._eventNames);
};
