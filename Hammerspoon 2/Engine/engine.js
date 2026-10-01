//
//  engine.js
//  Hammerspoon 2
//
//  Created by Chris Jones on 21/10/2025.
//

// IMPORTANT NOTE: No code in this file can depend on any of the hs.foo modules, they have not been loaded when this code executes

"use strict";
console.log("engine.js loading...")

// MARK: - EventEmitter
var EventEmitter = function () {
    this.events = {};
};

EventEmitter.prototype.on = function (event, listener) {
    if (typeof this.events[event] !== 'object') {
        this.events[event] = [];
    }

    this.events[event].push(listener);
};

EventEmitter.prototype.removeListener = function (event, listener) {
    var idx;

    if (typeof this.events[event] === 'object') {
        idx = this.events[event].indexOf(listener);

        if (idx > -1) {
            this.events[event].splice(idx, 1);
        }
    }
};

EventEmitter.prototype.emit = function (event) {
    var i, listeners, length, args = [].slice.call(arguments, 1);

    if (typeof this.events[event] === 'object') {
        listeners = this.events[event].slice();
        length = listeners.length;

        for (i = 0; i < length; i++) {
            listeners[i].apply(this, args);
        }
    }
};

// Node-style alias. Calls through `this.removeListener` (rather than being the same function
// reference) so a subclass overriding removeListener - e.g. LazyWatcherEmitter below - is still
// reached when callers use `off`.
EventEmitter.prototype.off = function (event, listener) {
    return this.removeListener(event, listener);
};

// Calls through `this.on`/`this.removeListener` for the same reason as `off` above.
EventEmitter.prototype.once = function (event, listener) {
    var emitter = this;
    function wrapped() {
        emitter.removeListener(event, wrapped);
        listener.apply(this, arguments);
    }
    this.on(event, wrapped);
    return this;
};

// MARK: - LazyWatcherEmitter
//
// One-to-many emitter for "watcher" modules (hs.usb, hs.application, etc.): a single underlying
// native watcher (IOKit, KVO, a poll timer, ...) is started when the first listener for ANY event
// is registered, and stopped once the last listener across ALL events is removed. This is the
// exact lifecycle every watcher module used to reimplement individually - see issue #234.
//
// `start`/`stop` are called with no arguments; native events are fed back in via `emitter.emit(name, ...)`.
class LazyWatcherEmitter extends EventEmitter {
    constructor(label, start, stop) {
        super();
        this._label = label;
        this._start = start;
        this._stop = stop;
        this._listenerCount = 0;
    }

    on(event, listener) {
        if (typeof listener !== 'function') {
            throw new Error(this._label + ".on(): listener must be a function");
        }
        if (Array.isArray(this.events[event]) && this.events[event].includes(listener)) {
            console.error(this._label + ".on(): listener for '" + event + "' is already registered.");
            return this;
        }

        super.on(event, listener);
        this._listenerCount++;
        if (this._listenerCount === 1) {
            this._start();
        }
        return this;
    }

    removeListener(event, listener) {
        if (!Array.isArray(this.events[event]) || !this.events[event].includes(listener)) {
            return this;
        }

        super.removeListener(event, listener);
        this._listenerCount--;
        if (this._listenerCount === 0) {
            this._stop();
        }
        return this;
    }
}

