//
//  hs.mqtt.js
//  Hammerspoon 2
//

"use strict";

// Factory for the emitters of HSMQTTClient objects; called lazily from Swift on a client's first
// on()/once(). All of a client's events come through one native callback, so this is a plain
// LazyWatcherEmitter.
/// SKIP_DOCS
hs.mqtt._makeClientEmitter = function(client) {
    return new LazyWatcherEmitter("hs.mqtt client", function() {
        return client._addWatcher((event, ...args) => {
            client._watcherEmitter.emit(event, ...args);
        });
    }, function() {
        client._removeWatcher();
    }, client._eventNames);
};
