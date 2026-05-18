"use strict";

class PowerEventWatcherEmitter {
    #listeners = []

    #handleEvent(eventName) {
        const listeners = this.#listeners.slice();
        for (var i = 0; i < listeners.length; i++) {
            listeners[i].call(null, eventName);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.power.addEventWatcher(): listener must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.power.addEventWatcher(): listener is already registered");
            return;
        }
        if (this.#listeners.length === 0) {
            hs.power._addEventWatcher((event) => {
                this.#handleEvent(event);
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
            hs.power._removeEventWatcher();
        }
    }
}

class BatteryWatcherEmitter {
    #listeners = []

    #handleChange() {
        const listeners = this.#listeners.slice();
        for (var i = 0; i < listeners.length; i++) {
            listeners[i].call(null);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.power.addBatteryWatcher(): listener must be a function");
        }
        if (this.#listeners.includes(listener)) {
            console.error("hs.power.addBatteryWatcher(): listener is already registered");
            return;
        }
        if (this.#listeners.length === 0) {
            hs.power._addBatteryWatcher(() => {
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
            hs.power._removeBatteryWatcher();
        }
    }
}

// Store emitters in Swift-retained properties so they are not garbage collected.
hs.power._eventWatcherEmitter = new PowerEventWatcherEmitter();
hs.power._batteryWatcherEmitter = new BatteryWatcherEmitter();
