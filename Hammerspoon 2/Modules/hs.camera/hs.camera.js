"use strict";

// Module-level one-to-many emitter for device connect/disconnect events.
class CameraModuleWatcherEmitter {
    #listeners = []

    #handleEvent(event, camera) {
        var listeners = this.#listeners.slice();
        for (var i = 0; i < listeners.length; i++) {
            listeners[i].apply(null, [event, camera]);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.camera.addWatcher(): listener must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.camera.addWatcher(): listener is already registered.");
            return;
        }
        if (this.#listeners.length === 0) {
            hs.camera._addWatcher((event, camera) => {
                this.#handleEvent(event, camera);
            });
        }
        this.#listeners.push(listener);
    }

    removeListener(listener) {
        const idx = this.#listeners.indexOf(listener);
        if (idx > -1) {
            this.#listeners.splice(idx, 1);
        }
        if (this.#listeners.length === 0) {
            hs.camera._removeWatcher();
        }
    }
}

// Per-camera one-to-many emitter for in-use state changes.
class CameraWatcherEmitter {
    #camera
    #listeners = []

    constructor(camera) {
        this.#camera = camera;
    }

    #handleEvent(isInUse) {
        var listeners = this.#listeners.slice();
        for (var i = 0; i < listeners.length; i++) {
            listeners[i].apply(null, [isInUse]);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.camera device.addWatcher(): listener must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.camera device.addWatcher(): listener is already registered.");
            return;
        }
        if (this.#listeners.length === 0) {
            this.#camera._addWatcher((isInUse) => {
                this.#handleEvent(isInUse);
            });
        }
        this.#listeners.push(listener);
    }

    removeListener(listener) {
        const idx = this.#listeners.indexOf(listener);
        if (idx > -1) {
            this.#listeners.splice(idx, 1);
        }
        if (this.#listeners.length === 0) {
            this.#camera._removeWatcher();
        }
    }
}

// Store module-level emitter in a Swift-retained property to prevent garbage collection.
hs.camera._watcherEmitter = new CameraModuleWatcherEmitter();

// Factory for per-camera emitters; called lazily from Swift when the first watcher is registered on a camera.
/// SKIP_DOCS
hs.camera._makeCameraEmitter = function(camera) {
    return new CameraWatcherEmitter(camera);
};
