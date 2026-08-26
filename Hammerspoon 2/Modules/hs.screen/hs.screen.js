//
//  hs.screen.js
//  Hammerspoon 2
//

"use strict";

// One-to-many event emitter for hs.screen display-configuration-change events.
// Lazily starts the underlying watcher on first listener and stops it when the last one is removed.
class ScreenWatcherEmitter {
    #listeners = []

    #handleChange() {
        const listeners = this.#listeners.slice();
        for (var i = 0; i < listeners.length; i++) {
            listeners[i].call(null);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.screen.addWatcher(): listener must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.screen.addWatcher(): listener is already registered");
            return;
        }
        if (this.#listeners.length === 0) {
            hs.screen._addWatcher(() => {
                this.#handleChange();
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
            hs.screen._removeWatcher();
        }
    }
}

// Store the emitter in a Swift-retained property so it is not garbage collected.
hs.screen._watcherEmitter = new ScreenWatcherEmitter();
