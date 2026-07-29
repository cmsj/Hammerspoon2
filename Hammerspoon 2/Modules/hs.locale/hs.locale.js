"use strict";

class LocaleWatcherEmitter {
    #listeners = []

    #handleChange() {
        const listeners = this.#listeners.slice();
        for (var i = 0; i < listeners.length; i++) {
            listeners[i].call(null);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.locale.addWatcher(): listener must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.locale.addWatcher(): listener is already registered");
            return;
        }
        if (this.#listeners.length === 0) {
            hs.locale._addWatcher(() => {
                this.#handleChange();
            });
        }
        this.#listeners.push(listener);
    }

    removeListener(listener) {
        const idx = this.#listeners.indexOf(listener);
        if (idx > -1) {
            this.#listeners.splice(idx, 1);
            if (this.#listeners.length === 0) {
                hs.locale._removeWatcher();
            }
        }
    }
}

// Store emitter in a Swift-retained property so it is not garbage collected.
hs.locale._watcherEmitter = new LocaleWatcherEmitter();
