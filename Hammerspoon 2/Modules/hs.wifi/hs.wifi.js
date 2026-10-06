//
//  hs.wifi.js
//  Hammerspoon 2
//

"use strict";

// Each of hs.wifi's 8 event types is an independent native CoreWLAN registration - a per-event
// native resource, not one shared stream - so this uses KeyedLazyWatcherEmitter (see
// Engine/engine.js), the same shape as hs.userdefaults. _addWatcher returns false if CoreWLAN
// registration failed (e.g. no Wi-Fi hardware present), in which case on()/once() throw and the
// listener is not recorded.
hs.wifi._watcherEmitter = new KeyedLazyWatcherEmitter("hs.wifi", function(event) {
    return hs.wifi._addWatcher(event, (info) => {
        hs.wifi._watcherEmitter.emit(event, info);
    });
}, function(event) {
    hs.wifi._removeWatcher(event);
}, hs.wifi._eventNames);

/// Register a listener for a Wi-Fi interface event.
/// Info keys by event:
///  - `"ssidChange"`, `"bssidChange"`, `"countryCodeChange"`, `"linkChange"`, `"modeChange"`, `"powerChange"`, `"scanCacheUpdated"`: `interface: string`
///  - `"linkQualityChange"`: `interface: string`, `rssi: number`, `transmitRate: number`
/// Parameters:
///  - event: {"ssidChange" | "bssidChange" | "countryCodeChange" | "linkChange" | "linkQualityChange" | "modeChange" | "powerChange" | "scanCacheUpdated"} The event to listen for
///  - listener: {(info: Record<string, any>) => void} Called with an info dictionary describing the event; see the keys listed above
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.wifi.on('ssidChange', info => console.log("SSID changed on " + info.interface))
///     hs.wifi.on('linkQualityChange', info => console.log(info.interface + ": " + info.rssi + " dBm"))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.wifi.on = function(event, listener) {
    hs.wifi._watcherEmitter.on(event, listener);
};

/// Remove a previously registered Wi-Fi event listener.
/// Parameters:
///  - event: {"ssidChange" | "bssidChange" | "countryCodeChange" | "linkChange" | "linkQualityChange" | "modeChange" | "powerChange" | "scanCacheUpdated"} The event the listener was registered for
///  - listener: {(info: Record<string, any>) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onSsidChange = info => console.log(info)
/// hs.wifi.on('ssidChange', onSsidChange)
/// // later…
/// hs.wifi.off('ssidChange', onSsidChange)
/// ```
hs.wifi.off = function(event, listener) {
    hs.wifi._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for a Wi-Fi interface event.
/// Parameters:
///  - event: {"ssidChange" | "bssidChange" | "countryCodeChange" | "linkChange" | "linkQualityChange" | "modeChange" | "powerChange" | "scanCacheUpdated"} The event to listen for
///  - listener: {(info: Record<string, any>) => void} Called once, then automatically removed
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.wifi.once('ssidChange', info => console.log("First SSID change: " + info.interface))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.wifi.once = function(event, listener) {
    hs.wifi._watcherEmitter.once(event, listener);
};
