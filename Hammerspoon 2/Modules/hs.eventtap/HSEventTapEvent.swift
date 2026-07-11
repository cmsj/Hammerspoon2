//
//  HSEventTapEvent.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreGraphics

// MARK: - Protocol

/// An input event captured or constructed by hs.eventtap.
///
/// Objects of this type are passed to event tap callbacks and can also be created directly
/// via the factory methods on hs.eventtap. Properties can be inspected and modified before
/// the event is passed through or posted back to the system.
@objc protocol HSEventTapEventAPI: HSTypeAPI, JSExport {
    /// Type name for introspection
    @objc var typeName: String { get }

    /// The numeric event type, matching a value in hs.eventtap.eventTypes
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
    ///     console.log("Event type: " + event.type)
    /// })
    /// ```
    @objc var type: Int { get }

    /// The virtual key code for keyboard events (get/set)
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
    ///     console.log("Key code: " + event.keyCode)
    /// })
    /// ```
    @objc var keyCode: Int { get set }

    /// The raw modifier flags bitmask (get/set). Use values from hs.eventtap.modifierFlags.
    /// - Example:
    /// ```js
    /// const evt = hs.eventtap.makeKeyEvent("a", true)
    /// evt.rawFlags = hs.eventtap.modifierFlags.cmd
    /// evt.post()
    /// ```
    @objc var rawFlags: Int { get set }

    /// An array of active modifier key names (e.g. ["cmd", "shift"]).
    ///
    /// When a device-specific modifier is detected, both the generic and side-specific
    /// names are included — e.g. pressing the left Command key yields ["cmd", "leftCmd"].
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
    ///     if (event.flags.includes("rightCmd")) console.log("Right Cmd held")
    /// })
    /// ```
    @objc var flags: [String] { get }

    /// The event's screen position as {x, y} in Hammerspoon screen coordinates
    /// (top-left origin of primary display, y increases downward, matching hs.screen).
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.mouseMoved], (event) => {
    ///     const loc = event.location
    ///     console.log("Mouse at " + loc.x + ", " + loc.y)
    /// })
    /// ```
    @objc var location: [String: Double] { get set }

    /// The mouse button number for mouse events (0=left, 1=right, 2=middle)
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.otherMouseDown], (event) => {
    ///     console.log("Button: " + event.buttonNumber)
    /// })
    /// ```
    @objc var buttonNumber: Int { get set }

    /// The horizontal scroll delta for scroll wheel events
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.scrollWheel], (event) => {
    ///     console.log("Scroll X: " + event.scrollingDeltaX)
    /// })
    /// ```
    @objc var scrollingDeltaX: Double { get }

    /// The vertical scroll delta for scroll wheel events
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.scrollWheel], (event) => {
    ///     console.log("Scroll Y: " + event.scrollingDeltaY)
    /// })
    /// ```
    @objc var scrollingDeltaY: Double { get }

    /// The Unicode characters produced by this keyboard event, or null for non-keyboard events
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
    ///     console.log("Typed: " + event.characters)
    /// })
    /// ```
    @objc var characters: String? { get }

    /// Create an independent copy of this event
    /// - Returns: A new HSEventTapEvent with the same properties, or null if the copy failed
    /// - Example:
    /// ```js
    /// const copy = event.duplicate()
    /// copy.keyCode = 0  // modify the copy
    /// copy.post()
    /// ```
    @objc func duplicate() -> HSEventTapEvent?

    /// Post this event to the HID event stream, optionally targeting a specific application.
    ///
    /// When `app` is omitted or `null`, the event is posted to the global HID stream and
    /// delivered by the OS as if a real input device generated it. When an application is
    /// provided, the event is delivered directly to that process by PID.
    ///
    /// - Parameter app: {HSApplication | null} The application to target, or null/omit to post globally
    /// - Example:
    /// ```js
    /// const evt = hs.eventtap.makeKeyEvent("a", true)
    /// evt.post()                              // post globally
    ///
    /// const safari = hs.application.find("Safari")
    /// if (safari) evt.post(safari)            // post directly to Safari
    /// ```
    @objc func post(_ app: HSApplication?)
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSEventTapEvent: NSObject, HSEventTapEventAPI {
    @objc var typeName = "HSEventTapEvent"

    // The wrapped CGEvent. Mutable so property setters can update it.
    var cgEvent: CGEvent

    init(cgEvent: CGEvent) {
        self.cgEvent = cgEvent
    }

    isolated deinit {
        AKDebug("deinit of HSEventTapEvent")
    }

    @objc var type: Int {
        return Int(cgEvent.type.rawValue)
    }

    @objc var keyCode: Int {
        get { Int(cgEvent.getIntegerValueField(.keyboardEventKeycode)) }
        set { cgEvent.setIntegerValueField(.keyboardEventKeycode, value: Int64(newValue)) }
    }

    @objc var rawFlags: Int {
        get { Int(bitPattern: UInt(cgEvent.flags.rawValue & UInt64(Int.max))) }
        set { cgEvent.flags = CGEventFlags(rawValue: UInt64(bitPattern: Int64(newValue))) }
    }

    @objc var flags: [String] {
        return CGEventFlags.modifierNames(from: cgEvent.flags)
    }

    @objc var location: [String: Double] {
        get {
            let loc = cgEvent.location
            return ["x": Double(loc.x), "y": Double(loc.y)]
        }
        set {
            let x = newValue["x"] ?? Double(cgEvent.location.x)
            let y = newValue["y"] ?? Double(cgEvent.location.y)
            cgEvent.location = CGPoint(x: x, y: y)
        }
    }

    @objc var buttonNumber: Int {
        get { Int(cgEvent.getIntegerValueField(.mouseEventButtonNumber)) }
        set { cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(newValue)) }
    }

    @objc var scrollingDeltaX: Double {
        return Double(cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis2))
    }

    @objc var scrollingDeltaY: Double {
        return Double(cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1))
    }

    @objc var characters: String? {
        let t = cgEvent.type
        guard t == .keyDown || t == .keyUp else { return nil }
        var length = 0
        unsafe cgEvent.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        var buffer = [UniChar](repeating: 0, count: length)
        unsafe cgEvent.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &buffer)
        return unsafe String(utf16CodeUnits: buffer, count: length)
    }

    @objc func duplicate() -> HSEventTapEvent? {
        guard let copy = cgEvent.copy() else { return nil }
        return HSEventTapEvent(cgEvent: copy)
    }

    @objc func post(_ app: HSApplication?) {
        guard let app = app else {
            cgEvent.post(tap: .cghidEventTap)
            return
        }
        // Deliver directly to a specific application by PID (CGEvent.postToPid, macOS 10.11+).
        cgEvent.postToPid(pid_t(app.pid))
    }
}

// MARK: - CGEventFlags helpers

extension CGEventFlags {
    // Device-specific left/right modifier bits embedded in the low word of CGEventFlags.rawValue.
    // Values from IOKit/hidsystem/IOLLEvent.h (NX_DEVICE*KEYMASK constants).
    private static let leftCtrlMask:   UInt64 = 0x00000001
    private static let leftShiftMask:  UInt64 = 0x00000002
    private static let rightShiftMask: UInt64 = 0x00000004
    private static let leftCmdMask:    UInt64 = 0x00000008
    private static let rightCmdMask:   UInt64 = 0x00000010
    private static let leftAltMask:    UInt64 = 0x00000020
    private static let rightAltMask:   UInt64 = 0x00000040
    private static let rightCtrlMask:  UInt64 = 0x00002000

    static func modifierNames(from flags: CGEventFlags) -> [String] {
        var names: [String] = []
        let raw = flags.rawValue

        if flags.contains(.maskCommand) {
            names.append("cmd")
            if raw & leftCmdMask  != 0 { names.append("leftCmd") }
            if raw & rightCmdMask != 0 { names.append("rightCmd") }
        }
        if flags.contains(.maskShift) {
            names.append("shift")
            if raw & leftShiftMask  != 0 { names.append("leftShift") }
            if raw & rightShiftMask != 0 { names.append("rightShift") }
        }
        if flags.contains(.maskAlternate) {
            names.append("alt")
            if raw & leftAltMask  != 0 { names.append("leftAlt") }
            if raw & rightAltMask != 0 { names.append("rightAlt") }
        }
        if flags.contains(.maskControl) {
            names.append("ctrl")
            if raw & leftCtrlMask  != 0 { names.append("leftCtrl") }
            if raw & rightCtrlMask != 0 { names.append("rightCtrl") }
        }
        if flags.contains(.maskSecondaryFn) { names.append("fn") }
        if flags.contains(.maskAlphaShift)  { names.append("capslock") }
        return names
    }

    static func from(modifierNames names: [String]) -> CGEventFlags {
        var flags = CGEventFlags()
        var raw: UInt64 = 0
        for name in names {
            switch name.lowercased() {
            case "cmd", "command", "⌘":
                flags.insert(.maskCommand)
            case "leftcmd", "leftcommand":
                flags.insert(.maskCommand)
                raw |= leftCmdMask
            case "rightcmd", "rightcommand":
                flags.insert(.maskCommand)
                raw |= rightCmdMask
            case "shift", "⇧":
                flags.insert(.maskShift)
            case "leftshift":
                flags.insert(.maskShift)
                raw |= leftShiftMask
            case "rightshift":
                flags.insert(.maskShift)
                raw |= rightShiftMask
            case "alt", "option", "⌥":
                flags.insert(.maskAlternate)
            case "leftalt", "leftoption":
                flags.insert(.maskAlternate)
                raw |= leftAltMask
            case "rightalt", "rightoption":
                flags.insert(.maskAlternate)
                raw |= rightAltMask
            case "ctrl", "control", "⌃":
                flags.insert(.maskControl)
            case "leftctrl", "leftcontrol":
                flags.insert(.maskControl)
                raw |= leftCtrlMask
            case "rightctrl", "rightcontrol":
                flags.insert(.maskControl)
                raw |= rightCtrlMask
            case "fn": flags.insert(.maskSecondaryFn)
            case "capslock": flags.insert(.maskAlphaShift)
            default: break
            }
        }
        return CGEventFlags(rawValue: flags.rawValue | raw)
    }
}
