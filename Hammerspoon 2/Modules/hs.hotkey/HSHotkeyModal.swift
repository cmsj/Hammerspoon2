//
//  HSHotkeyModal.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreGraphics

// MARK: - Modal Protocol

/// A group of hotkeys that are activated and deactivated together.
///
/// Obtain instances via `hs.hotkey.modal.create()` — do not instantiate directly.
///
/// ## Example
///
/// ```js
/// const m = hs.hotkey.modal.create(['cmd', 'shift'], 'h')
/// m.bind([], 'j', () => console.log('j pressed in modal'), null)
/// m.enterFn = () => console.log('modal entered')
/// m.exitFn  = () => console.log('modal exited')
/// // Press Cmd+Shift+H to enter, then J triggers the modal hotkey
/// ```
@objc protocol HSHotkeyModalAPI: HSTypeAPI, JSExport {
    /// Add a hotkey that is active only while this modal is entered
    /// - Parameters:
    ///   - mods: Modifier keys for the hotkey
    ///   - key: Key name for the hotkey
    ///   - callbackPressed: {(() => void) | null} Called when the key is pressed, or null
    ///   - callbackReleased: {(() => void) | null} Called when the key is released, or null
    /// - Returns: This modal, for chaining
    /// - Example:
    /// ```js
    /// m.bind(['shift'], 'a', () => console.log('shift-a'), null)
    ///  .bind([], 'escape', () => m.exit(), null)
    /// ```
    @objc @discardableResult func bind(_ mods: [String], _ key: String, _ callbackPressed: JSFunction, _ callbackReleased: JSFunction) -> HSHotkeyModal

    /// Activate the modal: enable its hotkeys and disable the trigger hotkey
    /// - Returns: This modal, for chaining
    /// - Example:
    /// ```js
    /// m.enter()
    /// ```
    @objc @discardableResult func enter() -> HSHotkeyModal

    /// Deactivate the modal: disable its hotkeys and re-enable the trigger hotkey
    /// - Returns: This modal, for chaining
    /// - Example:
    /// ```js
    /// m.exit()
    /// ```
    @objc @discardableResult func exit() -> HSHotkeyModal

    /// Destroy the modal and all its hotkeys without calling exitFn
    /// - Example:
    /// ```js
    /// m.destroy()
    /// ```
    @objc func destroy()

    /// {(() => void) | null} Called when the modal is entered
    /// - Example:
    /// ```js
    /// m.enterFn = () => console.log('entered')
    /// ```
    @objc var enterFn: JSFunction? { get set }

    /// {(() => void) | null} Called when the modal is exited
    /// - Example:
    /// ```js
    /// m.exitFn = () => console.log('exited')
    /// ```
    @objc var exitFn: JSFunction? { get set }

    /// Whether the modal is currently active
    /// - Example:
    /// ```js
    /// console.log(m.isActive)  // false before enter(), true after
    /// ```
    @objc var isActive: Bool { get }
}

// MARK: - Modal Implementation

@_documentation(visibility: private)
@MainActor
@safe
@objc class HSHotkeyModal: NSObject, HSHotkeyModalAPI {
    @objc var typeName = "HSHotkeyModal"

    private weak var hotkeyModule: HSHotkeyModule?
    private var triggerHotkey: HSHotkey?
    private var modalHotkeys: [HSHotkey] = []
    private var _enterFn: JSCallback?
    private var _exitFn: JSCallback?
    private var _isActive = false

    @objc var isActive: Bool { _isActive }

    @objc var enterFn: JSFunction? {
        get { _enterFn?.value }
        set {
            _enterFn?.detach(from: self)
            _enterFn = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    @objc var exitFn: JSFunction? {
        get { _exitFn?.value }
        set {
            _exitFn?.detach(from: self)
            _exitFn = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    init(mods: [String], key: String, hotkeyModule: HSHotkeyModule) {
        self.hotkeyModule = hotkeyModule
        super.init()
        // JSContext.current() is valid here — called from JS bridge via HSHotkeyModalFactory.create()
        if !key.isEmpty {
            if let trigger = hotkeyModule.makeHotkey(mods: mods, key: key,
                                                      callbackPressed: nil,
                                                      callbackReleased: nil) {
                trigger.swiftCallbackPressed = { [weak self] in
                    guard let self else { return }
                    _ = self.enter()
                }
                _ = trigger.enable()
                triggerHotkey = trigger
            } else {
                AKWarning("hs.hotkey.modal: Failed to create trigger hotkey for key '\(key)'")
            }
        }
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSHotkeyModal")
    }

    // MARK: - HSHotkeyModalAPI

    @discardableResult
    @objc func bind(_ mods: [String], _ key: String, _ callbackPressed: JSFunction, _ callbackReleased: JSFunction) -> HSHotkeyModal {
        guard let module = hotkeyModule else { return self }
        guard let hotkey = module.makeHotkey(
            mods: mods, key: key,
            callbackPressed: callbackPressed.isNull ? nil : callbackPressed,
            callbackReleased: callbackReleased.isNull ? nil : callbackReleased
        ) else {
            AKError("hs.hotkey.modal: Failed to create hotkey for key '\(key)'")
            return self
        }
        modalHotkeys.append(hotkey)
        if _isActive { _ = hotkey.enable() }
        return self
    }

    @discardableResult
    @objc func enter() -> HSHotkeyModal {
        guard !_isActive else { return self }
        _isActive = true
        triggerHotkey?.disable()
        for hk in modalHotkeys { _ = hk.enable() }
        fireCallback(_enterFn, name: "enterFn")
        AKTrace("hs.hotkey.modal: entered")
        return self
    }

    @discardableResult
    @objc func exit() -> HSHotkeyModal {
        guard _isActive else { return self }
        _isActive = false
        for hk in modalHotkeys { hk.disable() }
        _ = triggerHotkey?.enable()
        fireCallback(_exitFn, name: "exitFn")
        AKTrace("hs.hotkey.modal: exited")
        return self
    }

    @objc func destroy() {
        _isActive = false
        for hk in modalHotkeys { hk.destroy() }
        modalHotkeys.removeAll()
        triggerHotkey?.destroy()
        triggerHotkey = nil
        _enterFn?.detach(from: self)
        _enterFn = nil
        _exitFn?.detach(from: self)
        _exitFn = nil
    }

    // MARK: - Private

    private func fireCallback(_ callback: JSCallback?, name: String) {
        guard let fn = callback?.value, !fn.isNull else { return }
        fn.call(withArguments: [])
        if let ctx = fn.context, let exc = ctx.exception, !exc.isUndefined {
            AKError("hs.hotkey.modal: Error in \(name): \(exc.toString() ?? "unknown")")
            ctx.exception = nil
        }
    }
}
