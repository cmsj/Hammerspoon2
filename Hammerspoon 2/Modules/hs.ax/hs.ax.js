// hs.ax.js
// JavaScript enhancements for the hs.ax module

"use strict";

// One-to-many event emitter for hs.ax events.
// Allows multiple JavaScript listeners for the same app+notification pair
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

    on(application, notification, listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.ax.addWatcher(): The provided handler must be a function");
        }

        const key = `${application.pid}:${notification}`;

        if (!Array.isArray(this.#events[key])) {
            this.#events[key] = [];
            hs.ax._addWatcher(application, notification, (notif, elem) => {
                this.#handleEvent(key, notif, elem);
            });
        }

        if (this.#events[key].includes(listener)) {
            console.error("hs.ax.addWatcher(): The provided handler for '" + notification + "' is already registered.");
            return;
        }

        this.#events[key].push(listener);
    }

    removeListener(application, notification, listener) {
        const key = `${application.pid}:${notification}`;

        if (Array.isArray(this.#events[key])) {
            const idx = this.#events[key].indexOf(listener);

            if (idx > -1) {
                this.#events[key].splice(idx, 1);
            }

            if (this.#events[key].length === 0) {
                hs.ax._removeWatcher(application, notification);
                delete this.#events[key];
            }
        }
    }
}

// Store in a Swift-retained property so the emitter is not garbage collected.
hs.ax._watcherEmitter = new AXModuleWatcherEmitter();
