// hs.userdefaults.js
// JavaScript enhancements for the hs.userdefaults module

"use strict";

// One-to-many event emitter for hs.userdefaults key-change events.
// Allows multiple JavaScript listeners for the same key while Swift manages
// only a single KVO observer per key.
class UserDefaultsWatcherEmitter {
    #events = {};

    #handleEvent(key, newValue) {
        if (Array.isArray(this.#events[key])) {
            var listeners = this.#events[key].slice();
            const length = listeners.length;

            for (var i = 0; i < length; i++) {
                listeners[i].apply(null, [key, newValue]);
            }
        }
    }

    on(key, listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.userdefaults.addWatcher(): The provided handler must be a function");
        }

        if (!Array.isArray(this.#events[key])) {
            this.#events[key] = [];
            hs.userdefaults._addWatcher(key, (k, newValue) => {
                this.#handleEvent(k, newValue);
            });
        }

        if (this.#events[key].includes(listener)) {
            console.error("hs.userdefaults.addWatcher(): The provided handler for '" + key + "' is already registered.");
            return;
        }

        this.#events[key].push(listener);
    }

    removeListener(key, listener) {
        if (Array.isArray(this.#events[key])) {
            const idx = this.#events[key].indexOf(listener);

            if (idx > -1) {
                this.#events[key].splice(idx, 1);
            }

            if (this.#events[key].length === 0) {
                hs.userdefaults._removeWatcher(key);
                delete this.#events[key];
            }
        }
    }
}

// Store in a Swift-retained property so the emitter is not garbage collected.
hs.userdefaults._watcherEmitter = new UserDefaultsWatcherEmitter();
