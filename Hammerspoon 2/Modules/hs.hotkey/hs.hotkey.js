"use strict";

/// Bind a hotkey from a single options object. Like hs.hotkey.bind()/create(), but also
/// accepts a `message` and a `repeat` callback. `message` is available on any hotkey (not
/// just ones created via bindSpec()) by setting `.message` directly on the returned object;
/// see hs.hotkey's message property for exactly when it is shown.
/// Parameters:
///  - spec: An object with the following fields:
///    - mods: {string[]} Modifier keys (e.g. ["cmd", "shift"])
///    - key: {string} Key name or character (e.g. "h")
///    - message: {string} [optional] A description shown as a toast when the hotkey fires
///    - pressed: {(() => void) | null} [optional] Called when the hotkey is pressed
///    - released: {(() => void) | null} [optional] Called when the hotkey is released
///    - repeat: {(() => void) | null} [optional] Called repeatedly while the hotkey is held down
/// Returns: A hotkey object, or null if binding failed
/// Example:
/// ```js
/// hs.hotkey.bindSpec({
///     mods: ["cmd"], key: "space", message: "Spotlight-like",
///     pressed: () => console.log("pressed")
/// })
/// ```
hs.hotkey.bindSpec = function(spec) {
    const { mods = [], key, message, pressed = null, released = null, repeat: repeatfn = null } = spec;
    const hk = hs.hotkey.bind(mods, key, pressed, released);
    if (!hk) return null;
    if (message) hk.message = message;
    if (repeatfn) hk.callbackRepeat = repeatfn;
    return hk;
};

/**
 * A modal hotkey group returned by hs.hotkey.createModal(). Hotkeys bound to the modal
 * via bind() are only enabled while the modal is active (i.e. between enter() and exit()).
 * @property {boolean} isActive - Whether the modal is currently active
 * @property {Function|null} enterFn - Callback invoked when the modal is entered
 * @property {Function|null} exitFn - Callback invoked when the modal is exited
 */
class HSHotkeyModal {
    constructor() {
        this._hotkeys = [];
        this._trigger = null;
        this.enterFn = null;
        this.exitFn = null;
        this.isActive = false;
    }

    /**
     * Bind a hotkey to this modal. The hotkey is only enabled while the modal is active.
     * @param {string[]} mods - Modifier keys for the hotkey (e.g. ["cmd", "shift"])
     * @param {string} key - Key name for the hotkey (e.g. "h")
     * @param {Function|null} callbackPressed - Called when the hotkey is pressed, or null
     * @param {Function|null} callbackReleased - Called when the hotkey is released, or null
     * @param {Function|null} [callbackRepeat] - Called repeatedly while the hotkey is held down, or null
     * @returns {HSHotkeyModal} This modal, for chaining
     */
    bind(mods, key, callbackPressed, callbackReleased, callbackRepeat) {
        const hk = hs.hotkey.create(mods, key, callbackPressed, callbackReleased);
        if (!hk) return this;
        if (callbackRepeat) hk.callbackRepeat = callbackRepeat;
        this._hotkeys.push(hk);
        if (this.isActive) hk.enable();
        return this;
    }

    /**
     * Enter the modal: its trigger (if any) is disabled and its bound hotkeys are enabled.
     * @returns {HSHotkeyModal} This modal, for chaining
     */
    enter() {
        if (this.isActive) return this;
        this.isActive = true;
        if (this._trigger) this._trigger.disable();
        for (const hk of this._hotkeys) hk.enable();
        if (typeof this.enterFn === 'function') {
            try { this.enterFn(); } catch(e) { console.error("hs.hotkey modal enterFn error: " + e); }
        }
        console.debug("hs.hotkey: modal entered")
        return this;
    }

    /**
     * Exit the modal: its bound hotkeys are disabled and its trigger (if any) is re-enabled.
     * @returns {HSHotkeyModal} This modal, for chaining
     */
    exit() {
        if (!this.isActive) return this;
        this.isActive = false;
        for (const hk of this._hotkeys) hk.disable();
        if (this._trigger) this._trigger.enable();
        if (typeof this.exitFn === 'function') {
            try { this.exitFn(); } catch(e) { console.error("hs.hotkey modal exitFn error: " + e); }
        }
        console.debug("hs.hotkey: modal exited")
        return this;
    }

    /**
     * Destroy the modal, along with its trigger and all hotkeys bound to it.
     */
    destroy() {
        this.isActive = false;
        for (const hk of this._hotkeys) hk.destroy();
        this._hotkeys = [];
        if (this._trigger) {
            this._trigger.destroy();
            this._trigger = null;
        }
    }
}

/// Create a new modal hotkey group, optionally entered via a trigger key combination
/// Parameters:
///  - mods: Modifier keys for the trigger hotkey (e.g. ["cmd", "shift"]), or an empty array for no trigger
///  - key: Key name for the trigger hotkey (e.g. "h"), or an empty string for no trigger
/// Returns: {HSHotkeyModal} A modal object with bind(), enter(), exit(), destroy() methods, isActive property, and enterFn/exitFn callbacks
/// Example:
/// ```js
/// const m = hs.hotkey.createModal(['cmd'], 'h')
/// m.bind(['shift'], 'j', () => console.log('shift-j pressed'), null)
/// m.enterFn = () => console.log('modal entered')
/// m.exitFn  = () => console.log('modal exited')
/// m.bind([], 'escape', () => m.exit(), null)
/// ```
hs.hotkey.createModal = function(mods, key) {
    const modal = new HSHotkeyModal();

    if (key !== '') {
        const trigger = hs.hotkey.bind(mods, key, () => modal.enter(), null);
        if (trigger) modal._trigger = trigger;
    }

    return modal;
};

/// Create and enable a hotkey that, while held down, displays a list of all currently
/// enabled hotkeys (and their messages, if any) as an on-screen toast.
/// Parameters:
///  - mods: Modifier keys for the trigger hotkey (e.g. ["cmd", "shift"])
///  - key: Key name for the trigger hotkey (e.g. "/")
/// Returns: A hotkey object
/// Example:
/// ```js
/// hs.hotkey.showHotkeys(["cmd","shift"], "/")
/// ```
hs.hotkey.showHotkeys = function(mods, key) {
    let alert = null;
    return hs.hotkey.bind(mods, key, () => {
        const lines = hs.hotkey.getHotkeys().map(hk => {
            const label = hk.mods.join('+') + (hk.mods.length ? '+' : '') + hk.key;
            return hk.message ? `${label}: ${hk.message}` : label;
        });
        alert = hs.ui.alert(lines.join('\n')).duration(3600).show();
    }, () => {
        if (alert) {
            alert.close();
            alert = null;
        }
    });
};
