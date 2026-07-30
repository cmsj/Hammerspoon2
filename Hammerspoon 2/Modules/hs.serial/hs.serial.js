//
//  hs.serial.js
//  Hammerspoon 2
//

"use strict";

// One-to-many event emitter for hs.serial device events.
// Lazily starts the underlying IOKit watcher on first listener and stops it when the last one is removed.
class SerialModuleWatcherEmitter {
    #listeners = []

    #handleEvent(eventType, portInfo) {
        var listeners = this.#listeners.slice();
        const length = listeners.length;
        for (var i = 0; i < length; i++) {
            listeners[i].apply(null, [eventType, portInfo]);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.serial.addWatcher(): The provided handler must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.serial.addWatcher(): The provided handler is already registered.");
            return;
        }
        if (this.#listeners.length === 0) {
            const started = hs.serial._addWatcher((eventType, portInfo) => {
                this.#handleEvent(eventType, portInfo);
            });
            if (!started) {
                throw new Error("hs.serial.addWatcher(): Failed to start serial port watcher");
            }
        }
        this.#listeners.push(listener);
    }

    removeListener(listener) {
        const idx = this.#listeners.indexOf(listener);
        if (idx > -1) {
            this.#listeners.splice(idx, 1);
        }
        if (this.#listeners.length === 0) {
            hs.serial._removeWatcher();
        }
    }
}

// Store the emitter in a Swift-retained property so it is not garbage collected.
hs.serial._watcherEmitter = new SerialModuleWatcherEmitter();
