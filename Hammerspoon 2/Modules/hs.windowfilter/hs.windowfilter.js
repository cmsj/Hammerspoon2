"use strict";

// Makes the emitter behind a window filter's on()/off()/once(). It starts the filter's native
// watcher on the first listener and stops it once the last listener is removed. See
// Engine/engine.js for LazyWatcherEmitter itself.
/// SKIP_DOCS
hs.windowfilter._makeFilterEmitter = function(filter) {
    return new LazyWatcherEmitter("hs.windowfilter filter", function() {
        return filter._addWatcher((event, ...args) => {
            filter._watcherEmitter.emit(event, ...args);
        });
    }, function() {
        filter._removeWatcher();
    }, filter._eventNames);
};
