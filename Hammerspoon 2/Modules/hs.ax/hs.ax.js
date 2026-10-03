// hs.ax.js
// JavaScript enhancements for the hs.ax module

"use strict";

// One-to-many event emitter for hs.ax events.
// Allows multiple JavaScript listeners for the same element+notification pair
// while Swift manages only a single callback per combination.
//
// Buckets are resolved with isEqualToElement() rather than a hash-derived key:
// Hashable never guarantees uniqueness (only Equatable does), so keying buckets
// off a hash value risks silently merging two distinct elements' listeners if
// their hashes ever collided. This is also why this isn't built on the shared
// EventEmitter/LazyWatcherEmitter classes in Engine/engine.js - those key by plain
// string event names, which an AXElement has no meaningful equivalent of.
class AXModuleWatcherEmitter {
    #buckets = []

    #findBucket(element, notification) {
        return this.#buckets.find((bucket) => {
            return bucket.notification === notification && bucket.element.isEqualToElement(element);
        });
    }

    #handleEvent(bucket, notification, element) {
        var listeners = bucket.listeners.slice();
        const length = listeners.length;

        for (var i = 0; i < length; i++) {
            listeners[i].apply(null, [notification, element]);
        }
    }

    on(element, notification, listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.ax.on(): listener must be a function");
        }

        var bucket = this.#findBucket(element, notification);

        if (!bucket) {
            bucket = { element: element, notification: notification, listeners: [] };

            const registered = hs.ax._addWatcher(element, notification, (notif, elem) => {
                this.#handleEvent(bucket, notif, elem);
            });

            if (!registered) {
                // Native registration failed (e.g. permissions, invalid PID, unsupported
                // notification). Don't retain a bucket for a watcher that doesn't actually
                // exist - otherwise a later on() call would see the bucket, skip
                // _addWatcher entirely, and the listener would silently never fire.
                console.error("hs.ax.on(): Failed to register watcher for '" + notification + "'.");
                return;
            }

            this.#buckets.push(bucket);
        }

        if (bucket.listeners.includes(listener)) {
            console.error("hs.ax.on(): The provided listener for '" + notification + "' is already registered.");
            return;
        }

        bucket.listeners.push(listener);
    }

    off(element, notification, listener) {
        const bucket = this.#findBucket(element, notification);
        if (!bucket) {
            return;
        }

        const idx = bucket.listeners.indexOf(listener);
        if (idx > -1) {
            bucket.listeners.splice(idx, 1);
        }

        if (bucket.listeners.length === 0) {
            hs.ax._removeWatcher(element, notification);
            const bucketIdx = this.#buckets.indexOf(bucket);
            if (bucketIdx > -1) {
                this.#buckets.splice(bucketIdx, 1);
            }
        }
    }

    once(element, notification, listener) {
        const self = this;
        function wrapped(notif, elem) {
            self.off(element, notification, wrapped);
            listener.apply(null, [notif, elem]);
        }
        this.on(element, notification, wrapped);
    }
}

// Store in a Swift-retained property so the emitter is not garbage collected.
hs.ax._watcherEmitter = new AXModuleWatcherEmitter();
