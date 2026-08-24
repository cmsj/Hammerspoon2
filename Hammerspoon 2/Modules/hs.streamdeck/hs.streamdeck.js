"use strict";

// Module-level one-to-many emitter for device connect/disconnect events.
class StreamDeckModuleWatcherEmitter {
    #listeners = []

    #handleEvent(event, device) {
        var listeners = this.#listeners.slice();
        for (var i = 0; i < listeners.length; i++) {
            listeners[i].apply(null, [event, device]);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.streamdeck.addWatcher(): listener must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.streamdeck.addWatcher(): listener is already registered.");
            return;
        }
        if (this.#listeners.length === 0) {
            hs.streamdeck._addWatcher((event, device) => {
                this.#handleEvent(event, device);
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
            hs.streamdeck._removeWatcher();
        }
    }
}

// Store in a Swift-retained property so the emitter is not garbage collected.
hs.streamdeck._watcherEmitter = new StreamDeckModuleWatcherEmitter();
