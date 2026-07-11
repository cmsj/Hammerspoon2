//
//  HSHotkey.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreGraphics

// MARK: - Coordinator protocol

/// Internal protocol allowing HSHotkey to notify its owning module when started or stopped.
@MainActor
protocol HotkeyCoordinator: AnyObject {
    func hotkeyDidEnable(_ hotkey: HSHotkey)
    func hotkeyDidDisable(_ hotkey: HSHotkey)
}

// MARK: - Protocol

/// Object representing a system-wide hotkey. You should not create these objects directly, but rather, use the methods in hs.hotkey to instantiate these.
@objc protocol HSHotkeyAPI: HSTypeAPI, JSExport {
    /// Enable the hotkey
    /// - Returns: True if the hotkey was enabled, otherwise False
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// hk.enable()
    /// ```
    @objc func enable() -> Bool

    /// Disable the hotkey
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// hk.disable()
    /// ```
    @objc func disable()

    /// Check if the hotkey is currently enabled
    /// - Returns: True if the hotkey is enabled, otherwise False
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// console.log(hk.isEnabled())
    /// ```
    @objc func isEnabled() -> Bool

    /// {(() => void) | null} The callback function to be called when the hotkey is pressed, or null to remove it
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// hk.callbackPressed = () => console.log("new handler")
    /// ```
    @objc var callbackPressed: JSFunction? { get set }

    /// {(() => void) | null} The callback function to be called when the hotkey is released, or null to remove it
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// hk.callbackReleased = () => console.log("released")
    /// ```
    @objc var callbackReleased: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@safe
@objc class HSHotkey: NSObject, HSHotkeyAPI {
    @objc var typeName = "HSHotkey"

    let keyCode: CGKeyCode
    /// Device-independent modifier flags (maskCommand, maskShift, etc.) that must be active.
    let requiredFlags: CGEventFlags
    /// Side-specific NX_DEVICE*KEYMASK bits that must be set (0 if not side-specific).
    let requiredDeviceBits: UInt64

    private var _callbackPressed: JSCallback?
    private var _callbackReleased: JSCallback?
    @objc var callbackPressed: JSFunction? {
        get { _callbackPressed?.value }
        set {
            _callbackPressed?.detach(from: self)
            _callbackPressed = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }
    @objc var callbackReleased: JSFunction? {
        get { _callbackReleased?.value }
        set {
            _callbackReleased?.detach(from: self)
            _callbackReleased = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    private var _isEnabled = false
    weak var coordinator: (any HotkeyCoordinator)?

    // Pre-cast key code stored at init time; avoids a UInt16→Int64 conversion on every event.
    let cachedKeyCode: Int64

    // The flags we compare against: cmd, shift, alt, ctrl, fn. CapsLock and
    // device-specific bits are handled separately so they don't break matching.
    static let significantModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn
    ]

    init(keyCode: CGKeyCode,
         requiredFlags: CGEventFlags,
         requiredDeviceBits: UInt64,
         coordinator: any HotkeyCoordinator,
         callbackPressed: JSFunction? = nil,
         callbackReleased: JSFunction? = nil) {
        self.keyCode = keyCode
        self.cachedKeyCode = Int64(keyCode)
        self.requiredFlags = requiredFlags
        self.requiredDeviceBits = requiredDeviceBits
        self.coordinator = coordinator
        super.init()
        // Phase 2 — JSContext.current() is valid because this init is called from a JS bridge method
        if let cb = callbackPressed { self.callbackPressed = cb }
        if let cb = callbackReleased { self.callbackReleased = cb }
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSHotkey: keyCode=\(keyCode)")
    }

    func destroy() {
        _callbackPressed?.detach(from: self)
        _callbackPressed = nil
        _callbackReleased?.detach(from: self)
        _callbackReleased = nil
        disable()
    }

    @objc func enable() -> Bool {
        guard !_isEnabled else { return true }
        _isEnabled = true
        coordinator?.hotkeyDidEnable(self)
        return true
    }

    @objc func disable() {
        guard _isEnabled else { return }
        _isEnabled = false
        coordinator?.hotkeyDidDisable(self)
    }

    @objc func isEnabled() -> Bool { _isEnabled }

    /// Hot-path matcher called by dispatchKeyEvent with values pre-fetched once per event.
    /// No _isEnabled guard — callers guarantee only enabled hotkeys are passed here.
    @inline(__always)
    func matches(keyCode: Int64, maskedFlags: CGEventFlags, rawFlagsValue: UInt64) -> Bool {
        guard keyCode == cachedKeyCode else { return false }
        guard maskedFlags == requiredFlags else { return false }
        if requiredDeviceBits != 0 {
            return (rawFlagsValue & requiredDeviceBits) == requiredDeviceBits
        }
        return true
    }

    /// Convenience wrapper for tests and external callers. Includes an _isEnabled guard.
    func matches(event: CGEvent, type: CGEventType) -> Bool {
        guard _isEnabled else { return false }
        let eventFlags = event.flags
        return matches(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            maskedFlags: eventFlags.intersection(Self.significantModifiers),
            rawFlagsValue: eventFlags.rawValue
        )
    }

    /// Fire the appropriate JS callback for a keyDown or keyUp event.
    func trigger(type: CGEventType) {
        let callback: JSFunction?
        switch type {
            case .keyDown: callback = _callbackPressed?.value
            case .keyUp:   callback = _callbackReleased?.value
            default:       return
        }
        guard let callback, !callback.isNull else { return }
        callback.call(withArguments: [])
        if let context = callback.context,
           let exc = context.exception, !exc.isUndefined {
            AKError("hs.hotkey: Error in callback: \(exc.toString() ?? "unknown")")
            context.exception = nil
        }
    }
}
