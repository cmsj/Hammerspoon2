//
//  hs.power.js
//  Hammerspoon 2
//

"use strict";

// hs.power has two independent native watcher families, so it gets two LazyWatcherEmitters (see
// Engine/engine.js): the "event" family shares ONE native notification stream across all 12
// named power/session events below, while "change" (battery state) is a second, completely
// independent native IOPS watcher. on/off/once dispatch to whichever emitter owns the event name.

const POWER_BATTERY_EVENTS = new Set(['change']);

hs.power._eventWatcherEmitter = new LazyWatcherEmitter("hs.power", function() {
    hs.power._addEventWatcher((event) => {
        hs.power._eventWatcherEmitter.emit(event);
    });
}, function() {
    hs.power._removeEventWatcher();
});

hs.power._batteryWatcherEmitter = new LazyWatcherEmitter("hs.power", function() {
    const started = hs.power._addBatteryWatcher(() => {
        hs.power._batteryWatcherEmitter.emit('change');
    });
    if (!started) {
        throw new Error("hs.power.on(): Failed to start battery watcher");
    }
}, function() {
    hs.power._removeBatteryWatcher();
});

function hsPowerEmitterFor(event) {
    return POWER_BATTERY_EVENTS.has(event) ? hs.power._batteryWatcherEmitter : hs.power._eventWatcherEmitter;
}

/// Register a listener for system power/session events, or battery state changes.
/// Parameters:
///  - event: {"screensDidSleep" | "screensDidWake" | "screensDidLock" | "screensDidUnlock" | "screensaverDidStart" | "screensaverDidStop" | "screensaverWillStop" | "systemWillSleep" | "systemDidWake" | "systemWillPowerOff" | "sessionDidBecomeActive" | "sessionDidResignActive" | "change"} The event to listen for. `"change"` fires whenever battery state changes; the rest are system power/session events.
///  - listener: {() => void} Called with no arguments when the event occurs; call batteryInfo() inside a "change" listener to inspect the new battery state
/// Example:
/// ```js
/// hs.power.on('systemWillSleep', () => console.log("Going to sleep"))
/// hs.power.on('change', () => console.log("Battery now: " + hs.power.batteryInfo().percentage + "%"))
/// ```
hs.power.on = function(event, listener) {
    hsPowerEmitterFor(event).on(event, listener);
};

/// Remove a previously registered hs.power listener.
/// Parameters:
///  - event: {"screensDidSleep" | "screensDidWake" | "screensDidLock" | "screensDidUnlock" | "screensaverDidStart" | "screensaverDidStop" | "screensaverWillStop" | "systemWillSleep" | "systemDidWake" | "systemWillPowerOff" | "sessionDidBecomeActive" | "sessionDidResignActive" | "change"} The event the listener was registered for
///  - listener: {() => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onSleep = () => console.log("sleeping")
/// hs.power.on('systemWillSleep', onSleep)
/// // later…
/// hs.power.off('systemWillSleep', onSleep)
/// ```
hs.power.off = function(event, listener) {
    hsPowerEmitterFor(event).off(event, listener);
};

/// Register a listener that fires at most once for the given hs.power event.
/// Parameters:
///  - event: {"screensDidSleep" | "screensDidWake" | "screensDidLock" | "screensDidUnlock" | "screensaverDidStart" | "screensaverDidStop" | "screensaverWillStop" | "systemWillSleep" | "systemDidWake" | "systemWillPowerOff" | "sessionDidBecomeActive" | "sessionDidResignActive" | "change"} The event to listen for
///  - listener: {() => void} Called once, then automatically removed
/// Example:
/// ```js
/// hs.power.once('systemDidWake', () => console.log("Welcome back"))
/// ```
hs.power.once = function(event, listener) {
    hsPowerEmitterFor(event).once(event, listener);
};
