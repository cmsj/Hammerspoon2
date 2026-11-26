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

// Lazily starts watching for applications that turn Accessibility off on the first listener,
// and stops once the last listener is removed. See Engine/engine.js for LazyWatcherEmitter.
hs.windowfilter._watcherEmitter = new LazyWatcherEmitter("hs.windowfilter", function() {
    return hs.windowfilter._addWatcher((event, ...args) => {
        hs.windowfilter._watcherEmitter.emit(event, ...args);
    });
}, function() {
    hs.windowfilter._removeWatcher();
}, hs.windowfilter._eventNames);

/// Register a listener for window filter module events.
///
/// `"inaccessibleApplication"` fires when an application is found to have turned the
/// Accessibility API off for itself (e.g. Firefox in kiosk mode), so no window filter can see its
/// windows. It fires once per launch of such an application, for applications found after the
/// listener is registered; `hs.windowfilter.inaccessibleApplications()` lists the ones already
/// known.
/// Parameters:
///  - event: {"inaccessibleApplication"} The event to listen for
///  - listener: {(app: HSApplication) => void} Called with the application
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.windowfilter.on("inaccessibleApplication", app => console.log(app.name + " has turned Accessibility off"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.windowfilter.on = function(event, listener) {
    hs.windowfilter._watcherEmitter.on(event, listener);
};

/// Remove a previously registered window filter module event listener.
/// Parameters:
///  - event: {"inaccessibleApplication"} The event the listener was registered for
///  - listener: {(app: HSApplication) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onInaccessible = app => console.log(app.name + " has turned Accessibility off")
/// hs.windowfilter.on("inaccessibleApplication", onInaccessible)
/// // later…
/// hs.windowfilter.off("inaccessibleApplication", onInaccessible)
/// ```
hs.windowfilter.off = function(event, listener) {
    hs.windowfilter._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once, the next time a window filter module event happens. See `on()` for the events.
/// Parameters:
///  - event: {"inaccessibleApplication"} The event to listen for
///  - listener: {(app: HSApplication) => void} Called once, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.windowfilter.once("inaccessibleApplication", app => console.log(app.name + " has turned Accessibility off"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.windowfilter.once = function(event, listener) {
    hs.windowfilter._watcherEmitter.once(event, listener);
};
