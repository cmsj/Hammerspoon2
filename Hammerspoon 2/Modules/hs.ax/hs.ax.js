// hs.ax.js
// JavaScript enhancements for the hs.ax module

"use strict";

// One-to-many event emitter for hs.ax events.
// Allows multiple JavaScript listeners for the same element+notification pair
// while Swift manages only a single callback per combination.
class AXModuleWatcherEmitter {
    #events = {}

    #handleEvent(key, notification, element) {
        if (Array.isArray(this.#events[key])) {
            var listeners = this.#events[key].slice();
            const length = listeners.length;

            for (var i = 0; i < length; i++) {
                listeners[i].apply(null, [notification, element]);
            }
        }
    }

    on(element, notification, listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.ax.addWatcher(): The provided handler must be a function");
        }

        const key = `${element._identityKey}:${notification}`;

        if (!Array.isArray(this.#events[key])) {
            const registered = hs.ax._addWatcher(element, notification, (notif, elem) => {
                this.#handleEvent(key, notif, elem);
            });

            if (!registered) {
                // Native registration failed (e.g. permissions, invalid PID, unsupported
                // notification). Don't retain a bucket for a watcher that doesn't actually
                // exist - otherwise a later addWatcher() call would see the bucket, skip
                // _addWatcher entirely, and the listener would silently never fire.
                console.error("hs.ax.addWatcher(): Failed to register watcher for '" + notification + "'.");
                return;
            }

            this.#events[key] = [];
        }

        if (this.#events[key].includes(listener)) {
            console.error("hs.ax.addWatcher(): The provided handler for '" + notification + "' is already registered.");
            return;
        }

        this.#events[key].push(listener);
    }

    removeListener(element, notification, listener) {
        const key = `${element._identityKey}:${notification}`;

        if (Array.isArray(this.#events[key])) {
            const idx = this.#events[key].indexOf(listener);

            if (idx > -1) {
                this.#events[key].splice(idx, 1);
            }

            if (this.#events[key].length === 0) {
                hs.ax._removeWatcher(element, notification);
                delete this.#events[key];
            }
        }
    }
}

// Store in a Swift-retained property so the emitter is not garbage collected.
hs.ax._watcherEmitter = new AXModuleWatcherEmitter();
