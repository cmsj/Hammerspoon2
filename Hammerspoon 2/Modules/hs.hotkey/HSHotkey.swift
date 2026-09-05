//
//  HSHotkey.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit
import Carbon

// MARK: - Protocol

/// Object representing a system-wide hotkey. You should not create these objects directly, but rather, use the methods in hs.hotkey to instantiate these.
@objc protocol HSHotkeyAPI: HSTypeAPI, JSExport {
    /// {string[]} The modifier keys this hotkey was bound with, as originally passed to bind()/create()
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// console.log(hk.mods)
    /// ```
    @objc var mods: [String] { get }

    /// {string} The key this hotkey was bound with, as originally passed to bind()/create()
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// console.log(hk.key)
    /// ```
    @objc var key: String { get }

    /// {string | null} An optional description of what this hotkey does, or null if none was set.
    /// When set, it is shown as an on-screen toast via `hs.ui.alert()` (duration controlled by
    /// `hs.hotkey.alertDuration`) just before the hotkey's callback runs: before the pressed
    /// callback if one exists, otherwise before the released callback if one exists.
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// hk.message = "Say hello"
    /// ```
    @objc var message: String? { get set }

    /// {(() => void) | null} The callback function to be called repeatedly while the hotkey is held down, or null to remove it. Repeats at the system keyboard-repeat delay/interval, matching how held-down keys repeat elsewhere in macOS.
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// hk.callbackRepeat = () => console.log("still held")
    /// ```
    @objc var callbackRepeat: JSFunction? { get set }

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

    /// Disable and permanently remove this hotkey, releasing all associated resources
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.bind(["cmd"], "h", () => {})
    /// hk.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@safe
@objc class HSHotkey: NSObject, HSHotkeyAPI {
    @objc var typeName = "HSHotkey"

    @objc func toString() -> String {
        return "<\(typeName): keyCode \(keyCode), modifiers \(modifiers)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }
    private let keyCode: UInt32
    private let modifiers: UInt32
    @objc let mods: [String]
    @objc let key: String
    @objc var message: String?
    private var _callbackPressed: JSCallback?
    private var _callbackReleased: JSCallback?
    private var _callbackRepeat: JSCallback?

    @objc var callbackPressed: JSFunction? {
        get { _callbackPressed?.value }
        set {
            _callbackPressed?.detach(from: self)
            _callbackPressed = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }
    @objc var callbackReleased: JSFunction? {
        get { _callbackReleased?.value }
        set {
            _callbackReleased?.detach(from: self)
            _callbackReleased = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }
    @objc var callbackRepeat: JSFunction? {
        get { _callbackRepeat?.value }
        set {
            _callbackRepeat?.detach(from: self)
            _callbackRepeat = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    nonisolated(unsafe) private var carbonHotKeyRef: EventHotKeyRef?
    private var enabled = false
    private let hotkeyID: UInt32
    private var repeatDelayTimer: Timer?
    private var repeatIntervalTimer: Timer?

    init(keyCode: UInt32, modifiers: UInt32, mods: [String], key: String,
         callbackPressed: JSFunction? = nil, callbackReleased: JSFunction? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.mods = mods
        self.key = key
        self.hotkeyID = HotkeyManager.shared.nextID
        super.init()

        self.callbackPressed = callbackPressed
        self.callbackReleased = callbackReleased
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSHotkey: id=\(hotkeyID)")
    }

    /// Returns true if this hotkey was bound with the given key code and modifier flags.
    func matches(keyCode: UInt32, modifiers: UInt32) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    @objc func destroy() {
        disable()
        _callbackPressed?.detach(from: self)
        _callbackPressed = nil
        _callbackReleased?.detach(from: self)
        _callbackReleased = nil
        _callbackRepeat?.detach(from: self)
        _callbackRepeat = nil
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
        stopRepeating()
        guard enabled, let ref = unsafe carbonHotKeyRef else { return }
        unsafe UnregisterEventHotKey(ref)
        unsafe carbonHotKeyRef = nil
        HotkeyManager.shared.unregister(hotkeyID: hotkeyID)
        enabled = false
    }

    @objc func isEnabled() -> Bool { enabled }

    func trigger(eventKind: UInt32) {
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            // A message is shown before the pressed callback whenever one exists,
            // whether or not a released callback also exists.
            if let context = _callbackPressed?.value?.context {
                showMessageAlert(in: context)
            }
            invoke(_callbackPressed?.value)
            startRepeatingIfNeeded()
        case UInt32(kEventHotKeyReleased):
            // Only shown before the released callback when there's no pressed callback
            // to have already shown it.
            if _callbackPressed == nil, let context = _callbackReleased?.value?.context {
                showMessageAlert(in: context)
            }
            invoke(_callbackReleased?.value)
            stopRepeating()
        default:
            AKError("hs.hotkey: Unknown event kind: \(eventKind)")
        }
    }

    private func invoke(_ callback: JSFunction?) {
        guard let callback, !callback.isNull else { return }
        callback.call(withArguments: [])
        if let context = callback.context,
           let exc = context.exception, !exc.isUndefined {
            AKError("hs.hotkey: Error in callback: \(exc.toString() ?? "unknown")")
            context.exception = nil
        }
    }

    // MARK: - Message alert

    private func showMessageAlert(in context: JSContext) {
        guard let message, !message.isEmpty else { return }
        // message is passed as a JSValue argument (not interpolated into evaluated source)
        // so arbitrary message content can never be interpreted as JavaScript.
        guard let hsUI = context.evaluateScript("hs.ui"), !hsUI.isUndefined else { return }
        guard let alert = hsUI.invokeMethod("alert", withArguments: [message]) else { return }
        let duration = context.evaluateScript("hs.hotkey.alertDuration")?.toDouble() ?? 1.0
        guard let sized = alert.invokeMethod("duration", withArguments: [duration]) else { return }
        sized.invokeMethod("show", withArguments: [])
    }

    // MARK: - Repeat

    private func startRepeatingIfNeeded() {
        guard _callbackRepeat != nil else { return }
        stopRepeating()
        repeatDelayTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.beginRepeating()
            }
        }
    }

    private func beginRepeating() {
        fireRepeatCallback()
        repeatIntervalTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fireRepeatCallback()
            }
        }
    }

    private func fireRepeatCallback() {
        invoke(_callbackRepeat?.value)
    }

    private func stopRepeating() {
        repeatDelayTimer?.invalidate()
        repeatDelayTimer = nil
        repeatIntervalTimer?.invalidate()
        repeatIntervalTimer = nil
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
        unsafe contextPtr?.deinitialize(count: 1)
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

extension NSString {
    var fourCharCode: FourCharCode {
        guard self.length == 4 else { return 0 }
        var result: FourCharCode = 0
        for i in 0..<4 {
            result = (result << 8) + FourCharCode(self.character(at: i))
        }
        return result
    }
}
