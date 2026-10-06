// hs.pasteboard.js
// JavaScript enhancements for the hs.pasteboard module

"use strict";

// Lazily starts the underlying polling timer on the first listener and stops it once the last
// listener is removed. See Engine/engine.js for LazyWatcherEmitter itself. The pasteboard only
// ever emits one kind of event ("change"), but on/off/once still take an explicit event name
// for consistency with every other hs.* module-level watcher.
hs.pasteboard._watcherEmitter = new LazyWatcherEmitter("hs.pasteboard", function() {
    // Start the Swift polling timer using the currently configured interval.
    hs.pasteboard._startWatcher(hs.pasteboard.watcherInterval, (event, changeCount) => {
        hs.pasteboard._watcherEmitter.emit(event, changeCount);
    });
}, function() {
    hs.pasteboard._stopWatcher();
}, hs.pasteboard._eventNames);

/// Register a listener that fires whenever the pasteboard contents change.
/// Because macOS provides no pasteboard change notification API, this is implemented by
/// polling `changeCount` at the interval specified by `watcherInterval`.
/// Parameters:
///  - event: {"change"} The event to listen for (the only event this module emits)
///  - listener: {(changeCount: number) => void} Called with the new changeCount whenever the pasteboard changes
/// Example:
/// ```js
/// hs.pasteboard.on('change', count => console.log("Pasteboard changed:", count))
/// ```
hs.pasteboard.on = function(event, listener) {
    hs.pasteboard._watcherEmitter.on(event, listener);
};

/// Remove a previously registered pasteboard change listener.
/// Parameters:
///  - event: {"change"} The event the listener was registered for
///  - listener: {(changeCount: number) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onChange = count => console.log(count)
/// hs.pasteboard.on('change', onChange)
/// // later…
/// hs.pasteboard.off('change', onChange)
/// ```
hs.pasteboard.off = function(event, listener) {
    hs.pasteboard._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once, the next time the pasteboard contents change.
/// Parameters:
///  - event: {"change"} The event to listen for
///  - listener: {(changeCount: number) => void} Called once, then automatically removed
/// Example:
/// ```js
/// hs.pasteboard.once('change', count => console.log("First change:", count))
/// ```
hs.pasteboard.once = function(event, listener) {
    hs.pasteboard._watcherEmitter.once(event, listener);
};
