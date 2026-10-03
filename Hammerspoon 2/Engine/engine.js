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
    // Object.create(null), not {}: a plain object literal inherits Object.prototype, so an
    // event/key name that collides with one of ITS properties (`__proto__`, `constructor`,
    // `toString`, `hasOwnProperty`, ...) would read/write that inherited property instead of a
    // listener array - breaking registration and leaving removeListener() with no way to find
    // it again. hs.userdefaults keys are arbitrary user-chosen strings, so this is reachable in
    // practice (e.g. watching a preference literally named "__proto__"), not just theoretical.
    this.events = Object.create(null);
};

EventEmitter.prototype.on = function (event, listener) {
    if (typeof listener !== 'function') {
        throw new Error("EventEmitter.on(): listener must be a function");
    }

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

// Calls through `this.on`/`this.removeListener` for the same reason as `off` above. Validates
// `listener` itself here, before wrapping it: `this.on(event, wrapped)` below always passes a
// real function (`wrapped`), so `on()`'s own type-check can never see - and therefore can never
// reject - an invalid `listener` smuggled in through once(). Left unchecked, a bad listener would
// register successfully and only throw when `wrapped` is invoked from inside `emit()`, aborting
// delivery to every listener still left in that emit() call.
EventEmitter.prototype.once = function (event, listener) {
    if (typeof listener !== 'function') {
        throw new Error("EventEmitter.once(): listener must be a function");
    }
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
// `start`/`stop` are called with no arguments; native events are fed back in via
// `emitter.emit(name, ...)`. `start` MUST throw if it fails to start the native watcher - that
// exception propagates straight out of `on()`/`once()`, and (precisely because nothing is
// recorded until after `start` returns without throwing) a later call, even with the exact same
// listener, retries `start` cleanly instead of silently never attempting it again.
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

        // Start before recording anything: if `_start` throws, nothing here has been mutated,
        // so the next on() call - even for the same listener - sees _listenerCount still at 0
        // and retries start() instead of treating the never-started watcher as already running.
        if (this._listenerCount === 0) {
            this._start();
        }
        super.on(event, listener);
        this._listenerCount++;
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

// MARK: - KeyedLazyWatcherEmitter
//
// Like LazyWatcherEmitter, but starts/stops the native watcher independently PER EVENT NAME,
// rather than tracking one shared resource across every event. Use this when each named event
// has its own independent native resource - e.g. hs.userdefaults, where each watched key gets
// its own KVO observer - rather than one native stream multiplexing several named events (the
// LazyWatcherEmitter case, e.g. hs.usb's single IOKit watcher covering both 'added'/'removed').
//
// `start(event)` is called when that event's listener count goes 0->1; returning `false` means
// native registration failed, and the listener is not recorded (mirrors how a failed
// registration must not leave a phantom bucket behind). `stop(event)` is called when that
// event's listener count goes 1->0.
class KeyedLazyWatcherEmitter extends EventEmitter {
    constructor(label, start, stop) {
        super();
        this._label = label;
        this._start = start;
        this._stop = stop;
    }

    on(event, listener) {
        if (typeof listener !== 'function') {
            throw new Error(this._label + ".on(): listener must be a function");
        }
        const existing = Array.isArray(this.events[event]) ? this.events[event] : [];
        if (existing.includes(listener)) {
            console.error(this._label + ".on(): listener for '" + event + "' is already registered.");
            return this;
        }

        if (existing.length === 0) {
            if (this._start(event) === false) {
                return this;
            }
        }
        super.on(event, listener);
        return this;
    }

    removeListener(event, listener) {
        if (!Array.isArray(this.events[event]) || !this.events[event].includes(listener)) {
            return this;
        }

        super.removeListener(event, listener);
        if (!Array.isArray(this.events[event]) || this.events[event].length === 0) {
            this._stop(event);
        }
        return this;
    }
}

