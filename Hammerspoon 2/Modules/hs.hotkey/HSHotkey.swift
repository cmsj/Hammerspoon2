//
//  HSHotkey.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Carbon

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
    private let keyCode: UInt32
    private let modifiers: UInt32
    private var _callbackPressed: JSCallback?
    private var _callbackReleased: JSCallback?

    // Swift-only callback fired on keyDown before the JS callback.
    // Used by HSHotkeyModal for its trigger hotkey. Never exposed to JS.
    var swiftCallbackPressed: (@MainActor () -> Void)?

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

    nonisolated(unsafe) private var carbonHotKeyRef: EventHotKeyRef?
    private var enabled = false
    private let hotkeyID: UInt32

    init(keyCode: UInt32, modifiers: UInt32,
         callbackPressed: JSFunction? = nil, callbackReleased: JSFunction? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.hotkeyID = HotkeyManager.shared.nextID
        super.init()
        // Phase 2 — JSContext.current() is valid because init is called from a JS bridge method
        if let cb = callbackPressed { self.callbackPressed = cb }
        if let cb = callbackReleased { self.callbackReleased = cb }
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSHotkey: id=\(hotkeyID)")
    }

    func destroy() {
        disable()
        _callbackPressed?.detach(from: self)
        _callbackPressed = nil
        _callbackReleased?.detach(from: self)
        _callbackReleased = nil
        swiftCallbackPressed = nil
    }

    @objc func enable() -> Bool {
        guard !enabled else { return true }

        let hotKeyID = EventHotKeyID(
            signature: OSType(("HMSP" as NSString).fourCharCode),
            id: hotkeyID
        )
        let status = unsafe RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetEventDispatcherTarget(), 0, &carbonHotKeyRef
        )

        if status != noErr {
            AKError("hs.hotkey: Failed to register hotkey (error \(status))")
            return false
        }

        enabled = true
        HotkeyManager.shared.register(hotkeyID: hotkeyID, hotkey: self)
        return true
    }

    @objc func disable() {
        guard enabled, let ref = unsafe carbonHotKeyRef else { return }
        unsafe UnregisterEventHotKey(ref)
        unsafe carbonHotKeyRef = nil
        HotkeyManager.shared.unregister(hotkeyID: hotkeyID)
        enabled = false
    }

    @objc func isEnabled() -> Bool { enabled }

    func trigger(eventKind: UInt32) {
        if eventKind == UInt32(kEventHotKeyPressed) {
            swiftCallbackPressed?()
        }

        let callback: JSFunction?
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            callback = _callbackPressed?.value
        case UInt32(kEventHotKeyReleased):
            callback = _callbackReleased?.value
        default:
            AKError("hs.hotkey: Unknown event kind: \(eventKind)")
            return
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

// MARK: - Hotkey Manager

@_documentation(visibility: private)
@safe @MainActor
class HotkeyManager {
    static let shared = HotkeyManager()

    private var _nextID: UInt32 = 1
    var nextID: UInt32 {
        defer { _nextID += 1 }
        return _nextID
    }
    private var hotkeys: [UInt32: HSHotkey] = [:]
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private var contextPtr: UnsafeMutablePointer<HotkeyManager>?

    private init() {
        setupEventHandler()
    }

    isolated deinit {
        if let handler = unsafe eventHandler {
            unsafe RemoveEventHandler(handler)
        }
        unsafe contextPtr?.deallocate()
    }

    private func setupEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let ptr = UnsafeMutablePointer<HotkeyManager>.allocate(capacity: 1)
        unsafe ptr.initialize(to: self)
        unsafe contextPtr = ptr

        let status = unsafe InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, theEvent, userData -> OSStatus in
                guard let userData = unsafe userData else { return OSStatus(eventNotHandledErr) }
                let manager = unsafe userData.assumingMemoryBound(to: HotkeyManager.self).pointee

                var hotKeyID = EventHotKeyID()
                let getStatus = unsafe GetEventParameter(
                    theEvent,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard getStatus == noErr else { return OSStatus(eventNotHandledErr) }

                let eventKind = unsafe GetEventKind(theEvent)
                manager.dispatch(hotkeyID: hotKeyID.id, eventKind: eventKind)
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            ptr,
            &eventHandler
        )

        if status != noErr {
            AKError("hs.hotkey: Failed to install Carbon event handler (error \(status))")
        }
    }

    func register(hotkeyID: UInt32, hotkey: HSHotkey) {
        hotkeys[hotkeyID] = hotkey
    }

    func unregister(hotkeyID: UInt32) {
        hotkeys.removeValue(forKey: hotkeyID)
    }

    private func dispatch(hotkeyID: UInt32, eventKind: UInt32) {
        hotkeys[hotkeyID]?.trigger(eventKind: eventKind)
    }
}

// MARK: - FourCharCode helper

private extension NSString {
    var fourCharCode: FourCharCode {
        guard self.length == 4 else { return 0 }
        var result: FourCharCode = 0
        for i in 0..<4 {
            result = (result << 8) + FourCharCode(self.character(at: i))
        }
        return result
    }
}
