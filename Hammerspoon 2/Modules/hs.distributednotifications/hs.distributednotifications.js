// hs.distributednotifications.js
// JavaScript enhancements for the hs.distributednotifications module

"use strict";

// Lazily starts a native observer for a notification name on its first listener, and stops it
// once the last listener for that name is removed. Each name's observer is independent of every
// other name's - see Engine/engine.js for KeyedLazyWatcherEmitter. Notification names are
// arbitrary, so no list of known event names is passed.
hs.distributednotifications._watcherEmitter = new KeyedLazyWatcherEmitter("hs.distributednotifications", function(name) {
    return hs.distributednotifications._addWatcher(name, (n, object, userInfo) => {
        hs.distributednotifications._watcherEmitter.emit(n, object, userInfo);
    });
}, function(name) {
    hs.distributednotifications._removeWatcher(name);
});

/// Listen for a distributed notification.
/// Parameters:
///  - name: {string} The name of the notification to listen for, e.g. `"com.apple.Music.playerInfo"`
///  - listener: {(object: string | null, userInfo: Record<string, any>) => void} Called with the notification's sender string (or null) and its userInfo object (empty if it has none) each time the notification is posted
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.distributednotifications.on("com.apple.Music.playerInfo", (object, userInfo) => {
///         console.log(`Music is now ${userInfo["Player State"]}`)
///     })
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.distributednotifications.on = function(name, listener) {
    hs.distributednotifications._watcherEmitter.on(name, listener);
};

/// Stop listening for a distributed notification.
/// Parameters:
///  - name: {string} The notification name originally passed to `on`
///  - listener: {(object: string | null, userInfo: Record<string, any>) => void} The function originally passed to `on`
/// Example:
/// ```js
/// hs.distributednotifications.off("com.apple.Music.playerInfo", myHandler)
/// ```
hs.distributednotifications.off = function(name, listener) {
    hs.distributednotifications._watcherEmitter.off(name, listener);
};

/// Listen for the next posting of a distributed notification only.
/// Parameters:
///  - name: {string} The name of the notification to listen for
///  - listener: {(object: string | null, userInfo: Record<string, any>) => void} Called once, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.distributednotifications.once("com.apple.screenIsUnlocked", () => console.log("Screen unlocked"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.distributednotifications.once = function(name, listener) {
    hs.distributednotifications._watcherEmitter.once(name, listener);
};
