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

    // Returns true if `listener` was newly added, false if it was already registered. Throws if
    // the native watcher couldn't be registered, recording nothing.
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
                throw new Error("hs.ax.on(): failed to register watcher for '" + notification + "'");
            }

            this.#buckets.push(bucket);
        }

        if (bucket.listeners.includes(listener)) {
            console.error("hs.ax.on(): The provided listener for '" + notification + "' is already registered.");
            return false;
        }

        bucket.listeners.push(listener);
        return true;
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

    // Returns the wrapper function actually registered, so onceEach() can roll it back.
    once(element, notification, listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.ax.once(): listener must be a function");
        }
        const self = this;
        function wrapped(notif, elem) {
            self.off(element, notification, wrapped);
            listener.apply(null, [notif, elem]);
        }
        this.on(element, notification, wrapped);
        return wrapped;
    }

    // hs.ax.on()/once() accept an array of notification names; these register the listener for
    // each of them all-or-nothing. If any registration throws, those this call already added are
    // removed again before rethrowing, so a throwing hs.ax.on() never leaves a partial
    // registration behind (issue #254).
    onEach(element, notifications, listener) {
        this.#registerAll(element, notifications, (notification) => {
            return this.on(element, notification, listener) ? listener : null;
        });
    }

    onceEach(element, notifications, listener) {
        this.#registerAll(element, notifications, (notification) => {
            return this.once(element, notification, listener);
        });
    }

    #registerAll(element, notifications, register) {
        const added = [];
        try {
            for (const notification of notifications) {
                const registered = register(notification);
                if (registered) {
                    added.push([notification, registered]);
                }
            }
        } catch (err) {
            for (const [notification, registered] of added) {
                this.off(element, notification, registered);
            }
            throw err;
        }
    }
}

// Store in a Swift-retained property so the emitter is not garbage collected.
hs.ax._watcherEmitter = new AXModuleWatcherEmitter();
