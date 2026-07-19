"use strict";

/// Create a new modal hotkey group, optionally entered via a trigger key combination
/// Parameters:
///  - mods: Modifier keys for the trigger hotkey (e.g. ["cmd", "shift"]), or an empty array for no trigger
///  - key: Key name for the trigger hotkey (e.g. "h"), or an empty string for no trigger
/// Returns: A modal object with bind(), enter(), exit(), destroy() methods, isActive property, and enterFn/exitFn callbacks
/// Example:
/// ```js
/// const m = hs.hotkey.createModal(['cmd'], 'h')
/// m.bind(['shift'], 'j', () => console.log('shift-j pressed'), null)
/// m.enterFn = () => console.log('modal entered')
/// m.exitFn  = () => console.log('modal exited')
/// m.bind([], 'escape', () => m.exit(), null)
/// ```
hs.hotkey.createModal = function(mods, key) {
    const modal = {
        _hotkeys: [],
        _trigger: null,
        enterFn: null,
        exitFn: null,
        isActive: false,

        bind(mods, key, callbackPressed, callbackReleased) {
            const hk = hs.hotkey.create(mods, key, callbackPressed, callbackReleased);
            if (!hk) return this;
            this._hotkeys.push(hk);
            if (this.isActive) hk.enable();
            return this;
        },

        enter() {
            if (this.isActive) return this;
            this.isActive = true;
            if (this._trigger) this._trigger.disable();
            for (const hk of this._hotkeys) hk.enable();
            if (typeof this.enterFn === 'function') this.enterFn();
            console._internal("hs.hotkey modal entered")
            return this;
        },

        exit() {
            if (!this.isActive) return this;
            this.isActive = false;
            for (const hk of this._hotkeys) hk.disable();
            if (this._trigger) this._trigger.enable();
            if (typeof this.exitFn === 'function') this.exitFn();
            console._internal("hs.hotkey modal exited")
            return this;
        },

        destroy() {
            this.isActive = false;
            for (const hk of this._hotkeys) hk.destroy();
            this._hotkeys = [];
            if (this._trigger) {
                this._trigger.destroy();
                this._trigger = null;
            }
        }
    };

    if (key !== '') {
        const trigger = hs.hotkey.bind(mods, key, () => modal.enter(), null);
        if (trigger) modal._trigger = trigger;
    }

    return modal;
};
