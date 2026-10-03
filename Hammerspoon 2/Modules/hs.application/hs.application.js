//
//  hs.application.js
//  Hammerspoon 2
//
//  Created by Chris Jones on 23/10/2025.
//

"use strict";

// Lazily starts the underlying NSWorkspace notification watcher on the first listener (for any
// event) and stops it once the last listener (across all events) is removed. See
// Engine/engine.js for LazyWatcherEmitter itself.
hs.application._watcherEmitter = new LazyWatcherEmitter("hs.application", function() {
    hs.application._addWatcher((event, appObject) => {
        hs.application._watcherEmitter.emit(event, appObject);
    });
}, function() {
    hs.application._removeWatcher();
});

/// Register a listener for application events.
/// Parameters:
///  - event: {"willLaunch" | "didLaunch" | "didTerminate" | "didHide" | "didUnhide" | "didActivate" | "didDeactivate"} The event to listen for
///  - listener: {(app: HSApplication | null) => void} Called when a matching application event occurs
/// Example:
/// ```js
/// hs.application.on('didLaunch', app => console.log("launched: " + app.title))
/// hs.application.on('didTerminate', app => console.log("terminated: " + (app && app.title)))
/// ```
hs.application.on = function(event, listener) {
    hs.application._watcherEmitter.on(event, listener);
};

/// Remove a previously registered application event listener.
/// Parameters:
///  - event: {"willLaunch" | "didLaunch" | "didTerminate" | "didHide" | "didUnhide" | "didActivate" | "didDeactivate"} The event the listener was registered for
///  - listener: {(app: HSApplication | null) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onLaunch = app => console.log(app.title)
/// hs.application.on('didLaunch', onLaunch)
/// // later…
/// hs.application.off('didLaunch', onLaunch)
/// ```
hs.application.off = function(event, listener) {
    hs.application._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for an application event.
/// Parameters:
///  - event: {"willLaunch" | "didLaunch" | "didTerminate" | "didHide" | "didUnhide" | "didActivate" | "didDeactivate"} The event to listen for
///  - listener: {(app: HSApplication | null) => void} Called the next time a matching event occurs, then automatically removed
/// Example:
/// ```js
/// hs.application.once('didLaunch', app => console.log("First launch seen: " + app.title))
/// ```
hs.application.once = function(event, listener) {
    hs.application._watcherEmitter.once(event, listener);
};
