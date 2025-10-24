//
//  hs.application.js
//  Hammerspoon 2
//
//  Created by Chris Jones on 23/10/2025.
//

"use strict";

// 1:many event emitter for hs.application events that Swift can only map 1:1.
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

// Place an instance of the Watcher/Emitter class into the hs.application namespace
hs.application._watcherEmitter = new ApplicationModuleWatcherEmitter();

// User facing hs.application API for adding/removing watchers
hs.application.addWatcher = function (event, listener) {
    hs.application._watcherEmitter.on(event, listener);
}
hs.application.removeWatcher = function (event, listener) {
    hs.application._watcherEmitter.removeListener(event, listener);
}

// Example use in a user's init.js:
//
//function eventHandler(eventName, appObject) {
//    console.log("INIT.JS appWatcher eventHandler: " + eventName + " " + appObject.title);
//    if (eventName == "didTerminate") {
//        console.log("App quit")
//    }
//}
//hs.application.addWatcher("willLaunch", eventHandler);
