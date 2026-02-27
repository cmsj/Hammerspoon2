//
//  hs.application.js
//  Hammerspoon 2
//
//  Created by Chris Jones on 23/10/2025.
//

"use strict";

// one-to-many event emitter for hs.application events that Swift can only map 1:1.
class ApplicationModuleWatcherEmitter {
    #events = {}

    constructor() {}

    #handleEvent(event, appObject) {
        if (Array.isArray(this.#events[event] )) {
            var listeners = this.#events[event].slice();
            const length = listeners.length;

            for (var i = 0; i < length; i++) {
                listeners[i].apply(null, [event, appObject]);
            }
        }
    }

    on(event, listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.application.addWatcher(): The provided handler must be a function")
        }

        if (!Array.isArray(this.#events[event])) {
            this.#events[event] = [];
            hs.application._addWatcher(event, (event, appObject) => { this.#handleEvent(event, appObject) });
        }

        if (this.#events[event].includes(listener)) {
            console.error("hs.application.addWatcher(): The provided handler for '" + event + "' is already registered.")
            return;
        }

        this.#events[event].push(listener);
    }

    removeListener(event, listener) {
        var idx;

        if (Array.isArray(this.#events[event])) {
            idx = this.#events[event].indexOf(listener);

            if (idx > -1) {
                this.#events[event].splice(idx, 1);
            }

            if (this.#events[event].length == 0) {
                hs.application._removeWatcher(event);
            }
        }
    }
}

// Store an instance of the Watcher/Emitter in a Swift-retained property so it is not garbage collected.
hs.application._watcherEmitter = new ApplicationModuleWatcherEmitter();
