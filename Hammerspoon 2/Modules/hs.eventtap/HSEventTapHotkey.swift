//
//  HSEventTapHotkey.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreGraphics

// MARK: - Coordinator protocol

/// Internal protocol allowing HSEventTapHotkey to notify its owning module when started or stopped.
@MainActor
protocol EventTapHotkeyCoordinator: AnyObject {
    func tapHotkeyDidEnable(_ hotkey: HSEventTapHotkey) -> Bool
    func tapHotkeyDidDisable(_ hotkey: HSEventTapHotkey)
}

// MARK: - Protocol

/// A keyboard shortcut binding backed by an event tap. Supports fn modifier and left/right modifier
/// key distinction. Obtain instances via `hs.eventtap.bindHotkey()` — do not instantiate directly.
@objc protocol HSEventTapHotkeyAPI: HSTypeAPI, JSExport {
    /// {string | number} The key this hotkey was bound with, as originally passed to bindHotkey()
    /// - Example:
    /// ```js
    /// const hk = hs.eventtap.bindHotkey(["fn"], "f1", () => {}, null)
    /// console.log(hk.key)
    /// ```
    @objc var key: Any { get }

    /// {number} The virtual key code this hotkey currently matches. For a hotkey bound by key name
    /// this follows the keyboard layout (see `hs.eventtap.followsKeyboardLayout`).
    /// - Example:
    /// ```js
    /// const hk = hs.eventtap.bindHotkey(["fn"], "w", () => {}, null)
    /// console.log(hk.keyCode)  // 13 on US, 43 on Dvorak
    /// ```
    @objc var keyCode: Int { get }

    /// Enable the hotkey
    /// - Returns: True if the hotkey was enabled, otherwise False
    /// - Example:
    /// ```js
    /// const hk = hs.eventtap.bindHotkey(["fn"], "f1", () => {}, null)
    /// hk.enable()
    /// ```
    @objc func enable() -> Bool

    /// Disable the hotkey
    /// - Example:
    /// ```js
    /// const hk = hs.eventtap.bindHotkey(["fn"], "f1", () => {}, null)
    /// hk.disable()
    /// ```
    @objc func disable()

    /// Check if the hotkey is currently enabled
    /// - Returns: True if the hotkey is enabled, otherwise False
    /// - Example:
    /// ```js
    /// const hk = hs.eventtap.bindHotkey(["fn"], "f1", () => {}, null)
    /// console.log(hk.isEnabled())
    /// ```
    @objc func isEnabled() -> Bool

    /// {(() => void) | null} The callback function to be called when the hotkey is pressed, or null to remove it
    /// - Example:
    /// ```js
    /// const hk = hs.eventtap.bindHotkey(["fn"], "f1", () => {}, null)
    /// hk.onPressed = () => console.log("new handler")
    /// ```
    @objc var onPressed: JSFunction? { get set }

    /// {(() => void) | null} The callback function to be called when the hotkey is released, or null to remove it
    /// - Example:
    /// ```js
    /// const hk = hs.eventtap.bindHotkey(["fn"], "f1", () => {}, null)
    /// hk.onReleased = () => console.log("released")
    /// ```
    @objc var onReleased: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@safe
@objc class HSEventTapHotkey: NSObject, HSEventTapHotkeyAPI {
    @objc var typeName = "HSEventTapHotkey"

    @objc func toString() -> String {
        return "<\(typeName): keyCode \(keyCode), \(_isEnabled ? "enabled" : "disabled")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    let keyArgument: KeyArgument
    @objc var key: Any { keyArgument.jsValue }
    @objc var keyCode: Int { Int(cachedKeyCode) }
    /// Device-independent modifier flags (maskCommand, maskShift, etc.) that must be active.
    let requiredFlags: CGEventFlags
    /// Side-specific NX_DEVICE*KEYMASK bits that must be set (0 if not side-specific).
    let requiredDeviceBits: UInt64

    private var _onPressed: JSCallback?
    private var _onReleased: JSCallback?

    @objc var onPressed: JSFunction? {
        get { _onPressed?.value }
        set {
            _onPressed?.detach(from: self)
            _onPressed = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }
    @objc var onReleased: JSFunction? {
        get { _onReleased?.value }
        set {
            _onReleased?.detach(from: self)
            _onReleased = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    private var _isEnabled = false
    weak var coordinator: (any EventTapHotkeyCoordinator)?

    // Key code pre-cast to the type events report, to avoid a UInt16→Int64 conversion on every event.
    // Changes only via changeKeyCode(), when the keyboard layout changes.
    private(set) var cachedKeyCode: Int64

    // The flags we compare against: cmd, shift, alt, ctrl, fn. CapsLock and
    // device-specific bits are handled separately so they don't break matching.
    static let significantModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn
    ]

    /// - Parameter key: How the key was specified. Defaults to the fixed key code, which never moves.
    init(keyCode: CGKeyCode,
         key: KeyArgument? = nil,
         requiredFlags: CGEventFlags,
         requiredDeviceBits: UInt64,
         coordinator: any EventTapHotkeyCoordinator,
         onPressed: JSFunction? = nil,
         onReleased: JSFunction? = nil) {
        self.keyArgument = key ?? .keyCode(Int(keyCode))
        self.cachedKeyCode = Int64(keyCode)
        self.requiredFlags = requiredFlags
        self.requiredDeviceBits = requiredDeviceBits
        self.coordinator = coordinator
        super.init()
        // Phase 2 — JSContext.current() is valid because this init is called from a JS bridge method
        if let cb = onPressed { self.onPressed = cb }
        if let cb = onReleased { self.onReleased = cb }
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSEventTapHotkey: keyCode=\(keyCode)")
    }

    func destroy() {
        _onPressed?.detach(from: self)
        _onPressed = nil
        _onReleased?.detach(from: self)
        _onReleased = nil
        disable()
    }

    @objc func enable() -> Bool {
        guard !_isEnabled else { return true }
        _isEnabled = true
        return coordinator?.tapHotkeyDidEnable(self) ?? false
    }

    @objc func disable() {
        guard _isEnabled else { return }
        _isEnabled = false
        coordinator?.tapHotkeyDidDisable(self)
    }

    @objc func isEnabled() -> Bool { _isEnabled }

    /// Changes the key code this hotkey matches. Unlike hs.hotkey, nothing is registered with the
    /// OS (the shared dispatch tap compares key codes itself), so this is safe while enabled.
    func changeKeyCode(_ newKeyCode: CGKeyCode) {
        cachedKeyCode = Int64(newKeyCode)
    }

    /// Hot-path matcher called by dispatchKeyEvent with values pre-fetched once per event.
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

    /// Fire the appropriate callback for a keyDown or keyUp event.
    func trigger(type: CGEventType) {
        let callback: JSFunction?
        switch type {
        case .keyDown: callback = _onPressed?.value
        case .keyUp:   callback = _onReleased?.value
        default:       return
        }
        guard let callback, !callback.isNull else { return }
        callback.call(withArguments: [])
        if let context = callback.context,
           let exc = context.exception, !exc.isUndefined {
            AKError("hs.eventtap.bindHotkey: Error in callback: \(exc.toString() ?? "unknown")")
            context.exception = nil
        }
    }
}
