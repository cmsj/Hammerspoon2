"use strict";

// Lazily starts the underlying device connect/disconnect watcher on the first listener (for
// either event) and stops it once the last listener (across both events) is removed. See
// Engine/engine.js for LazyWatcherEmitter itself.
hs.camera._watcherEmitter = new LazyWatcherEmitter("hs.camera", function() {
    hs.camera._addWatcher((event, camera) => {
        hs.camera._watcherEmitter.emit(event, camera);
    });
}, function() {
    hs.camera._removeWatcher();
});

/// Register a listener for camera device connect/disconnect events.
/// Parameters:
///  - event: {"connected" | "disconnected"} The event to listen for
///  - listener: {(camera: HSCamera) => void} Called with the affected camera when a matching event occurs
/// Example:
/// ```js
/// hs.camera.on('connected', camera => console.log("connected: " + camera.name))
/// hs.camera.on('disconnected', camera => console.log("disconnected: " + camera.name))
/// ```
hs.camera.on = function(event, listener) {
    hs.camera._watcherEmitter.on(event, listener);
};

/// Remove a previously registered camera device event listener.
/// Parameters:
///  - event: {"connected" | "disconnected"} The event the listener was registered for
///  - listener: {(camera: HSCamera) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onConnected = camera => console.log(camera.name)
/// hs.camera.on('connected', onConnected)
/// // later…
/// hs.camera.off('connected', onConnected)
/// ```
hs.camera.off = function(event, listener) {
    hs.camera._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for a camera device event.
/// Parameters:
///  - event: {"connected" | "disconnected"} The event to listen for
///  - listener: {(camera: HSCamera) => void} Called the next time a matching event occurs, then automatically removed
/// Example:
/// ```js
/// hs.camera.once('connected', camera => console.log("First camera connected: " + camera.name))
/// ```
hs.camera.once = function(event, listener) {
    hs.camera._watcherEmitter.once(event, listener);
};

// Factory for per-camera emitters; called lazily from Swift when the first on()/once() call is
// made on a camera. A camera only ever has one kind of event (its in-use state changing), so
// the Swift-side HSCamera.on/off/once pass a fixed internal event name - this factory doesn't
// need to know anything about that, it just wires up the generic (event, listener) emitter.
/// SKIP_DOCS
hs.camera._makeCameraEmitter = function(camera) {
    return new LazyWatcherEmitter("hs.camera device", function() {
        const started = camera._addWatcher((isInUse) => {
            camera._watcherEmitter.emit("change", isInUse);
        });
        if (!started) {
            throw new Error("hs.camera device.on(): Failed to start watcher");
        }
    }, function() {
        camera._removeWatcher();
    });
};
