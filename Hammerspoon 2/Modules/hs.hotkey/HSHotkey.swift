//
//  HotkeyObject.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/11/2025.
//

import Foundation
import JavaScriptCore
import Carbon

/// Object representing a system-wide hotkey. You should not create these objects directly, but rather, use the methods in hs.hotkey to instantiate these.
@objc protocol HSHotkeyAPI: HSTypeAPI, JSExport {
    /// Enable the hotkey
    /// - Returns: True if the hotkey was enabled, otherwise False
    @objc func enable() -> Bool

    /// Disable the hotkey
    @objc func disable()

    /// Check if the hotkey is currently enabled
    /// - Returns: True if the hotkey is enabled, otherwise False
    @objc func isEnabled() -> Bool

    /// Delete the hotkey (disables and clears callbacks)
    @objc func delete()
}

@_documentation(visibility: private)
@MainActor
@objc @safe class HSHotkey: NSObject, HSHotkeyAPI {
    @objc var typeName = "HSHotkey"
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let callbackPressed: JSValue?
    private let callbackReleased: JSValue?
    nonisolated(unsafe) private var carbonHotKeyRef: EventHotKeyRef?
    private var enabled = false
    private let hotkeyID: UInt32

    // Generate unique IDs for each hotkey
    private static var nextID: UInt32 = 1

    init(keyCode: UInt32, modifiers: UInt32, callbackPressed: JSValue? = nil, callbackReleased: JSValue? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.callbackPressed = callbackPressed
        self.callbackReleased = callbackReleased

        // Generate unique ID
        self.hotkeyID = Self.nextID
        Self.nextID += 1

        super.init()
    }

    isolated deinit {
        disable()
        HotkeyManager.shared.unregister(hotkeyID: hotkeyID)
        AKTrace("deinit of HSHotkeyObject: id=\(hotkeyID)")
    }

    @objc func enable() -> Bool {
        if enabled {
            return true
        }

        // Create the EventHotKeyID
        let hotKeyID = EventHotKeyID(signature: OSType(("HMSP" as NSString).fourCharCode),
                                      id: hotkeyID)

        // Register the hotkey with Carbon
        let status = unsafe RegisterEventHotKey(keyCode,
                                        modifiers,
                                        hotKeyID,
                                        GetEventDispatcherTarget(),
                                        0, // options
                                        &carbonHotKeyRef)

        if status != noErr {
            AKError("hs.hotkey: Failed to register hotkey (error \(status))")
            return false
        }

        enabled = true

        // Register with the manager so callbacks can be dispatched
        HotkeyManager.shared.register(hotkeyID: hotkeyID, hotkey: self)

        return true
    }

    @objc func disable() {
        guard enabled, let hotKeyRef = unsafe carbonHotKeyRef else {
            return
        }

        unsafe UnregisterEventHotKey(hotKeyRef)
        unsafe carbonHotKeyRef = nil
        enabled = false
    }

    @objc func isEnabled() -> Bool {
        return enabled
    }

    @objc func delete() {
        disable()
        HotkeyManager.shared.unregister(hotkeyID: hotkeyID)
    }

    /// Internal method called by HotkeyManager when the hotkey is triggered
    func trigger(eventKind: UInt32) {
        var callback: JSValue? = nil

        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            if self.callbackPressed != nil && !self.callbackPressed!.isNull {
                callback = self.callbackPressed
            }
        case UInt32(kEventHotKeyReleased):
            if self.callbackReleased != nil && !self.callbackReleased!.isNull{
                callback = self.callbackReleased
            }
        default:
            AKError("Unknown hotkey event kind: \(eventKind)")
            return
        }

        if let callback {
            // Call the callback
            callback.call(withArguments: [])

            // Check for JavaScript errors
            if let context = callback.context,
               let exception = context.exception,
               !exception.isUndefined {
                AKError("hs.hotkey: Error in callback: \(exception.toString() ?? "unknown error")")
                context.exception = nil
            }
        }
    }
}

// MARK: - Hotkey Manager

/// Singleton that manages the Carbon event handler and dispatches hotkey events
@safe @MainActor
class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeys: [UInt32: HSHotkey] = [:]
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    let context = UnsafeMutablePointer<HotkeyManager>.allocate(capacity: 1)

    private init() {
        setupEventHandler()
    }

    isolated deinit {
        if let handler = unsafe eventHandler {
            unsafe RemoveEventHandler(handler)
            unsafe context.deallocate()
        }
    }

    private func setupEventHandler() {
        // Define the event types we want to handle
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                         eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased))
        ]

        // Create a context that holds a reference to self
//        let context = UnsafeMutablePointer<HotkeyManager>.allocate(capacity: 1)
        unsafe context.initialize(to: self)

        // Install the event handler
        let status = unsafe InstallEventHandler(
            GetEventDispatcherTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                // Extract our manager from the context
                guard let userData = unsafe userData else { return OSStatus(eventNotHandledErr) }
                let manager = unsafe userData.assumingMemoryBound(to: HotkeyManager.self).pointee

                // Get the hotkey ID from the event
                var hotKeyID = EventHotKeyID()
                let getIDStatus = unsafe GetEventParameter(
                    theEvent,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard getIDStatus == noErr else {
                    return OSStatus(eventNotHandledErr)
                }

                let eventKind = unsafe GetEventKind(theEvent)

                // Dispatch to the appropriate hotkey
                manager.dispatch(hotkeyID: hotKeyID.id, eventKind: eventKind)

                return noErr
            },
            eventTypes.count,
            &eventTypes,
            context,
            &eventHandler
        )

        if status != noErr {
            AKError("hs.hotkey: Failed to install event handler (error \(status))")
        }
    }

    func register(hotkeyID: UInt32, hotkey: HSHotkey) {
        hotkeys[hotkeyID] = hotkey
    }

    func unregister(hotkeyID: UInt32) {
        hotkeys.removeValue(forKey: hotkeyID)
    }

    nonisolated private func dispatch(hotkeyID: UInt32, eventKind: UInt32) {
        // Dispatch on main thread to access hotkeys dictionary and trigger callback
        Task { @MainActor in
            self.hotkeys[hotkeyID]?.trigger(eventKind: eventKind)
        }
    }
}

// Helper extension for converting strings to FourCharCode
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
