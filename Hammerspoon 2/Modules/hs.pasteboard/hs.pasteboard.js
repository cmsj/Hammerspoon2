// hs.pasteboard.js
// JavaScript enhancements for the hs.pasteboard module

"use strict";

// One-to-many event emitter for pasteboard change events.
// A single Swift timer is shared across all listeners; it starts with the first listener
// and stops automatically when the last listener is removed.
class PasteboardWatcherEmitter {
    #listeners = []

    constructor() {}

    #handleChange(changeCount) {
        var listeners = this.#listeners.slice();
        const length = listeners.length;

        for (var i = 0; i < length; i++) {
            listeners[i].call(null, changeCount);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.pasteboard.addWatcher(): The provided handler must be a function");
        }

        if (this.#listeners.includes(listener)) {
            console.error("hs.pasteboard.addWatcher(): The provided handler is already registered.");
            return;
        }

        if (this.#listeners.length === 0) {
            // Start the Swift polling timer using the currently configured interval
            hs.pasteboard._startWatcher(hs.pasteboard.watcherInterval, (changeCount) => {
                this.#handleChange(changeCount);
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
            hs.pasteboard._stopWatcher();
        }
    }
}

// Store in a Swift-retained property so the emitter is not garbage collected.
hs.pasteboard._watcherEmitter = new PasteboardWatcherEmitter();
