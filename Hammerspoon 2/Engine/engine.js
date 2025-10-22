//
//  engine.js
//  Hammerspoon 2
//
//  Created by Chris Jones on 21/10/2025.
//

// IMPORTANT NOTE: No code in this file can depend on any of the hs.foo modules, they have not been loaded when this code executes

console.log("engine.js loading...")
// FIXME: This is not really useful, it came from https://levelup.gitconnected.com/extend-enum-cases-in-swift-workarounds-and-practical-use-cases-7fcc192f6567
// FIXME: This was here because it might have helped with doing things like injecting all of the AXNotification values as an enum, but we should do that a different way - maybe just a frozen object directly injected from Swift?
class Enum {
    constructor(...properties) {
        let value = 0;
        properties.forEach( function (prop) {
            const newValue = value;
            Object.defineProperty(this, prop, {
                get: function() { return newValue; }
            });
            value++;
        }, this);
        Object.freeze(this);
    }
}

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

EventEmitter.prototype.once = function (event, listener) {
    this.on(event, function g () {
        this.removeListener(event, g);
        listener.apply(this, arguments);
    });
};
