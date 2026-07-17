//
//  hs.usb.js
//  Hammerspoon 2
//

"use strict";

// One-to-many event emitter for hs.usb device events.
// Lazily starts the underlying IOKit watcher on first listener and stops it when the last one is removed.
class UsbModuleWatcherEmitter {
    #listeners = []

    #handleEvent(eventType, deviceInfo) {
        var listeners = this.#listeners.slice();
        const length = listeners.length;
        for (var i = 0; i < length; i++) {
            listeners[i].apply(null, [eventType, deviceInfo]);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.usb.addWatcher(): The provided handler must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.usb.addWatcher(): The provided handler is already registered.");
            return;
        }
        if (this.#listeners.length === 0) {
            hs.usb._addWatcher((eventType, deviceInfo) => {
                this.#handleEvent(eventType, deviceInfo);
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
            hs.usb._removeWatcher();
        }
    }
}

// Store the emitter in a Swift-retained property so it is not garbage collected.
hs.usb._watcherEmitter = new UsbModuleWatcherEmitter();
