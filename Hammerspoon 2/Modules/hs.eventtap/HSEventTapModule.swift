//
//  HSEventTapModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreGraphics
import AppKit

// MARK: - Module API

/// Monitor and synthesise macOS input events: keyboard, mouse, and scroll wheel.
///
/// All coordinate parameters use **Hammerspoon screen coordinates**: the origin `(0, 0)`
/// is at the top-left of the primary display and `y` increases downward, matching `hs.screen`.
///
/// ## Tapping events
///
/// ```js
/// const tap = hs.eventtap.addWatcher(
///     [hs.eventtap.eventTypes.keyDown],
///     (event) => {
///         console.log("Key pressed: " + event.keyCode)
///         return hs.eventtap.emit   // pass the event through
///     }
/// )
/// tap.start()
/// ```
///
/// ## Suppressing events
///
/// Returning `hs.eventtap.consume` from the callback prevents the event from reaching
/// other applications:
///
/// ```js
/// const blocker = hs.eventtap.addWatcher(
///     [hs.eventtap.eventTypes.leftMouseDown],
///     (event) => hs.eventtap.consume
/// )
/// blocker.start()
/// ```
///
/// ## Sending events
///
/// ```js
/// hs.eventtap.keyStroke(["cmd"], "c")
/// hs.eventtap.leftClick(500, 300)
/// ```
@objc protocol HSEventTapModuleAPI: JSExport {

    // MARK: Constants

    /// A dictionary mapping event type names to their numeric values.
    ///
    /// Pass values from this dictionary to `addWatcher()` to specify which events to monitor.
    /// - Example:
    /// ```js
    /// const types = hs.eventtap.eventTypes
    /// const tap = hs.eventtap.addWatcher([types.keyDown, types.keyUp], (event) => {
    ///     return hs.eventtap.emit
    /// })
    /// ```
    @objc var eventTypes: [String: Int] { get }

    /// A dictionary mapping modifier key names to their bitmask values for use with `rawFlags`.
    ///
    /// Includes generic names (`cmd`, `shift`, `alt`, `ctrl`) and side-specific names
    /// (`leftCmd`, `rightCmd`, `leftShift`, `rightShift`, `leftAlt`, `rightAlt`,
    /// `leftCtrl`, `rightCtrl`) for distinguishing physical keys.
    /// - Example:
    /// ```js
    /// const evt = hs.eventtap.makeKeyEvent("a", true)
    /// evt.rawFlags = hs.eventtap.modifierFlags.cmd | hs.eventtap.modifierFlags.shift
    /// evt.post()
    /// ```
    @objc var modifierFlags: [String: Int] { get }

    /// Return this from an event tap callback to suppress the event (prevent other apps from receiving it).
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
    ///     return hs.eventtap.consume   // block the key from reaching any app
    /// }).start()
    /// ```
    @objc var consume: Bool { get }

    /// Return this from an event tap callback to allow the event to pass through to other applications.
    /// - Example:
    /// ```js
    /// hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
    ///     console.log("Key: " + event.keyCode)
    ///     return hs.eventtap.emit   // let the key reach its destination
    /// }).start()
    /// ```
    @objc var emit: Bool { get }

    // MARK: Watcher management

    /// Create an event tap that calls a function for matching events. Call `.start()` to activate it.
    ///
    /// The callback receives an `HSEventTapEvent`. For modify taps (`listenOnly` omitted or false),
    /// return `hs.eventtap.consume` (false) to suppress the event or `hs.eventtap.emit` (true)
    /// to pass it through. For listen-only taps the callback's return value is ignored — events
    /// are always delivered to other applications. Requires Accessibility permission.
    ///
    /// - Parameters:
    ///   - types: An array of event type integers from `hs.eventtap.eventTypes`
    ///   - callback: {(event: HSEventTapEvent) => boolean | undefined} Function called for each matching event. The return value is only meaningful for modify taps.
    ///   - listenOnly: If true, the tap receives events but cannot modify or suppress them. Omit or pass false for a modify tap (the default).
    /// - Returns: An HSEventTap watcher, or null if the tap could not be created
    /// - Note: event tap watchers will not be automatically destroyed by JavaScript garbage collection. You *MUST* call `removeWatcher()` if you want to dispose of a watcher.
    /// - Example:
    /// ```js
    /// // Modify tap — can suppress events
    /// const tap = hs.eventtap.addWatcher(
    ///     [hs.eventtap.eventTypes.keyDown],
    ///     (event) => {
    ///         console.log("Key: " + event.keyCode)
    ///         return hs.eventtap.emit
    ///     }
    /// )
    /// tap.start()
    ///
    /// // Listen-only tap — events always pass through
    /// const listener = hs.eventtap.addWatcher(
    ///     [hs.eventtap.eventTypes.keyDown],
    ///     (event) => { console.log("Key: " + event.keyCode) },
    ///     true
    /// )
    /// listener.start()
    /// ```
    @objc func addWatcher(_ types: [Int], _ callback: JSFunction, _ listenOnly: Bool) -> HSEventTap?

    /// Stop and remove a previously created watcher
    /// - Parameter tap: The HSEventTap returned by `addWatcher`
    /// - Example:
    /// ```js
    /// hs.eventtap.removeWatcher(tap)
    /// ```
    @objc func removeWatcher(_ tap: HSEventTap)

    // MARK: Event constructors

    /// Create a keyboard event
    /// - Parameters:
    ///   - key: A key name (e.g. "a", "space", "return", "f1") or numeric key code string
    ///   - isDown: true for key down, false for key up
    /// - Returns: An HSEventTapEvent, or null if the key name is unknown
    /// - Example:
    /// ```js
    /// const evt = hs.eventtap.makeKeyEvent("a", true)
    /// evt.rawFlags = hs.eventtap.modifierFlags.cmd
    /// evt.post()
    /// ```
    @objc func makeKeyEvent(_ key: String, _ isDown: Bool) -> HSEventTapEvent?

    /// Create a keyboard event using a raw key code
    /// - Parameters:
    ///   - keyCode: A numeric virtual key code
    ///   - isDown: true for key down, false for key up
    /// - Returns: An HSEventTapEvent
    /// - Example:
    /// ```js
    /// const evt = hs.eventtap.makeKeyEventWithCode(0, true)  // key code 0 = "a"
    /// evt.post()
    /// ```
    @objc func makeKeyEventWithCode(_ keyCode: Int, _ isDown: Bool) -> HSEventTapEvent?

    /// Create a mouse event at the given position.
    ///
    /// Coordinates are in **Hammerspoon screen coordinates** (top-left origin of the primary
    /// display, y increases downward), matching the values returned by `hs.screen`.
    ///
    /// - Parameters:
    ///   - type: An event type integer from hs.eventtap.eventTypes (e.g. leftMouseDown)
    ///   - x: Horizontal position in Hammerspoon screen coordinates
    ///   - y: Vertical position in Hammerspoon screen coordinates
    ///   - button: Mouse button number (0=left, 1=right, 2=middle)
    /// - Returns: An HSEventTapEvent, or null if the event could not be created
    /// - Example:
    /// ```js
    /// const s = hs.screen.primary()
    /// // Click at the centre of the primary screen:
    /// const cx = s.frame.x + s.frame.w / 2
    /// const cy = s.frame.y + s.frame.h / 2
    /// const evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.leftMouseDown, cx, cy, 0)
    /// evt.post()
    /// ```
    @objc func makeMouseEvent(_ type: Int, _ x: Double, _ y: Double, _ button: Int) -> HSEventTapEvent?

    /// Create a scroll wheel event at the given position.
    ///
    /// Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal scroll amount in lines (positive = right)
    ///   - deltaY: Vertical scroll amount in lines (positive = down)
    ///   - x: Horizontal position in Hammerspoon screen coordinates
    ///   - y: Vertical position in Hammerspoon screen coordinates
    /// - Returns: An HSEventTapEvent, or null if the event could not be created
    /// - Example:
    /// ```js
    /// const evt = hs.eventtap.makeScrollWheelEvent(0, 3, 500, 400)
    /// evt.post()
    /// ```
    @objc func makeScrollWheelEvent(_ deltaX: Double, _ deltaY: Double, _ x: Double, _ y: Double) -> HSEventTapEvent?

    // MARK: Convenience senders

    /// Send a key down and key up event with optional modifier keys.
    ///
    /// A 50 ms pause is inserted between the key-down and key-up events to improve
    /// compatibility with applications that miss very fast synthetic keystrokes.
    ///
    /// - Parameters:
    ///   - mods: An array of modifier names (e.g. ["cmd", "shift"])
    ///   - key: A key name or single character (e.g. "a", "space", "return")
    /// - Example:
    /// ```js
    /// hs.eventtap.keyStroke(["cmd"], "c")      // Copy
    /// hs.eventtap.keyStroke(["cmd", "shift"], "4")  // Screenshot selection
    /// ```
    @objc func keyStroke(_ mods: [String], _ key: String)

    /// Type a string of characters as individual key events.
    ///
    /// A 50 ms pause is inserted between each key-down and key-up event.
    ///
    /// - Parameter text: The string to type
    /// - Example:
    /// ```js
    /// hs.eventtap.keyStrokes("Hello, World!")
    /// ```
    @objc func keyStrokes(_ text: String)

    /// Post a left mouse button click at the given position.
    ///
    /// Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
    ///
    /// - Parameters:
    ///   - x: Horizontal position in Hammerspoon screen coordinates
    ///   - y: Vertical position in Hammerspoon screen coordinates
    /// - Example:
    /// ```js
    /// hs.eventtap.leftClick(400, 300)
    /// ```
    @objc func leftClick(_ x: Double, _ y: Double)

    /// Post a right mouse button click at the given position.
    ///
    /// Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
    ///
    /// - Parameters:
    ///   - x: Horizontal position in Hammerspoon screen coordinates
    ///   - y: Vertical position in Hammerspoon screen coordinates
    /// - Example:
    /// ```js
    /// hs.eventtap.rightClick(400, 300)
    /// ```
    @objc func rightClick(_ x: Double, _ y: Double)

    /// Post a left mouse button double-click at the given position.
    ///
    /// Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
    ///
    /// - Parameters:
    ///   - x: Horizontal position in Hammerspoon screen coordinates
    ///   - y: Vertical position in Hammerspoon screen coordinates
    /// - Example:
    /// ```js
    /// hs.eventtap.doubleLeftClick(400, 300)
    /// ```
    @objc func doubleLeftClick(_ x: Double, _ y: Double)

    /// Post a middle mouse button click at the given position.
    ///
    /// Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
    ///
    /// - Parameters:
    ///   - x: Horizontal position in Hammerspoon screen coordinates
    ///   - y: Vertical position in Hammerspoon screen coordinates
    /// - Example:
    /// ```js
    /// hs.eventtap.middleClick(400, 300)
    /// ```
    @objc func middleClick(_ x: Double, _ y: Double)

    /// Post a scroll wheel event at the given position.
    ///
    /// Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal scroll amount in lines (positive = right)
    ///   - deltaY: Vertical scroll amount in lines (positive = down)
    ///   - x: Horizontal position in Hammerspoon screen coordinates
    ///   - y: Vertical position in Hammerspoon screen coordinates
    /// - Example:
    /// ```js
    /// hs.eventtap.scrollWheel(0, 3, 500, 400)  // Scroll down 3 lines
    /// ```
    @objc func scrollWheel(_ deltaX: Double, _ deltaY: Double, _ x: Double, _ y: Double)

    // MARK: System state queries

    /// Returns the currently held modifier keys
    /// - Returns: An array of modifier key names such as ["cmd", "shift"]
    /// - Example:
    /// ```js
    /// const mods = hs.eventtap.currentModifiers()
    /// if (mods.includes("cmd")) console.log("Cmd is held")
    /// ```
    @objc func currentModifiers() -> [String]

    /// Returns the currently pressed mouse buttons
    /// - Returns: A dictionary with keys "left", "right", "middle" mapping to booleans
    /// - Example:
    /// ```js
    /// const buttons = hs.eventtap.checkMouseButtons()
    /// if (buttons.left) console.log("Left button held")
    /// ```
    @objc func checkMouseButtons() -> [String: Bool]

    /// Returns the current mouse cursor position in Hammerspoon screen coordinates
    /// (top-left origin of primary display, y increases downward, matching hs.screen).
    /// - Returns: A dictionary with "x" and "y" keys
    /// - Example:
    /// ```js
    /// const pos = hs.eventtap.mouseLocation()
    /// console.log("Mouse at " + pos.x + ", " + pos.y)
    /// ```
    @objc func mouseLocation() -> [String: Double]

    /// Returns the system double-click interval in seconds
    /// - Returns: The maximum time between clicks that counts as a double-click
    /// - Example:
    /// ```js
    /// console.log("Double-click interval: " + hs.eventtap.doubleClickInterval())
    /// ```
    @objc func doubleClickInterval() -> Double

    /// Returns the system key repeat delay in seconds
    /// - Returns: The delay before key repeat begins
    /// - Example:
    /// ```js
    /// console.log("Key repeat delay: " + hs.eventtap.keyRepeatDelay())
    /// ```
    @objc func keyRepeatDelay() -> Double

    /// Returns the system key repeat interval in seconds
    /// - Returns: The interval between repeated key events
    /// - Example:
    /// ```js
    /// console.log("Key repeat interval: " + hs.eventtap.keyRepeatInterval())
    /// ```
    @objc func keyRepeatInterval() -> Double
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSEventTapModule: NSObject, HSModuleAPI, HSEventTapModuleAPI {
    var name = "hs.eventtap"
    let engineID: UUID
    // Strong references: started taps keep themselves alive via selfRetain, so weak refs
    // would be nil'd after JS GC — shutdown() would never find them to call destroy().
    private var taps: [HSEventTap] = []

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for tap in taps { tap.destroy() }
        taps.removeAll()
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - Constants

    let _eventTypes: [String: Int] = [
        "null": Int(CGEventType.null.rawValue),
        "leftMouseDown": Int(CGEventType.leftMouseDown.rawValue),
        "leftMouseUp": Int(CGEventType.leftMouseUp.rawValue),
        "rightMouseDown": Int(CGEventType.rightMouseDown.rawValue),
        "rightMouseUp": Int(CGEventType.rightMouseUp.rawValue),
        "mouseMoved": Int(CGEventType.mouseMoved.rawValue),
        "leftMouseDragged": Int(CGEventType.leftMouseDragged.rawValue),
        "rightMouseDragged": Int(CGEventType.rightMouseDragged.rawValue),
        "keyDown": Int(CGEventType.keyDown.rawValue),
        "keyUp": Int(CGEventType.keyUp.rawValue),
        "flagsChanged": Int(CGEventType.flagsChanged.rawValue),
        "scrollWheel": Int(CGEventType.scrollWheel.rawValue),
        "tabletPointer": Int(CGEventType.tabletPointer.rawValue),
        "tabletProximity": Int(CGEventType.tabletProximity.rawValue),
        "otherMouseDown": Int(CGEventType.otherMouseDown.rawValue),
        "otherMouseUp": Int(CGEventType.otherMouseUp.rawValue),
        "otherMouseDragged": Int(CGEventType.otherMouseDragged.rawValue),
    ]

    // Device-independent masks (high word of CGEventFlags.rawValue)
    // Device-specific left/right masks (low word, NX_DEVICE*KEYMASK from IOLLEvent.h)
    let _modifierFlags: [String: Int] = [
        "capslock": Int(CGEventFlags.maskAlphaShift.rawValue),
        "shift":    Int(CGEventFlags.maskShift.rawValue),
        "ctrl":     Int(CGEventFlags.maskControl.rawValue),
        "control":  Int(CGEventFlags.maskControl.rawValue),
        "alt":      Int(CGEventFlags.maskAlternate.rawValue),
        "option":   Int(CGEventFlags.maskAlternate.rawValue),
        "cmd":      Int(CGEventFlags.maskCommand.rawValue),
        "command":  Int(CGEventFlags.maskCommand.rawValue),
        "fn":       Int(CGEventFlags.maskSecondaryFn.rawValue),
        "numpad":   Int(CGEventFlags.maskNumericPad.rawValue),
        // Side-specific modifiers (device-specific low-word bits)
        "leftCtrl":   0x00000001,
        "leftShift":  0x00000002,
        "rightShift": 0x00000004,
        "leftCmd":    0x00000008,
        "rightCmd":   0x00000010,
        "leftAlt":    0x00000020,
        "rightAlt":   0x00000040,
        "rightCtrl":  0x00002000,
    ]

    @objc var eventTypes: [String: Int] {
        return _eventTypes
    }

    @objc var modifierFlags: [String: Int] {
        return _modifierFlags
    }

    @objc var consume: Bool { false }
    @objc var emit: Bool { true }

    // MARK: - Watcher management

    @objc func addWatcher(_ types: [Int], _ callback: JSFunction, _ listenOnly: Bool) -> HSEventTap? {
        guard !types.isEmpty else {
            AKError("hs.eventtap.addWatcher: types array must not be empty")
            return nil
        }
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        let tap = HSEventTap(eventMask: mask, listenOnly: listenOnly)
        _ = tap.setCallback(callback)
        taps.append(tap)
        return tap
    }

    @objc func removeWatcher(_ tap: HSEventTap) {
        tap.destroy()
        taps.removeAll { $0 === tap }
    }

    // MARK: - Event constructors

    @objc func makeKeyEvent(_ key: String, _ isDown: Bool) -> HSEventTapEvent? {
        guard let keyCode = KeyCodeResolver.keyCode(for: key) else {
            AKError("hs.eventtap.makeKeyEvent: Unknown key '\(key)'")
            return nil
        }
        return makeKeyEventWithCode(Int(keyCode), isDown)
    }

    @objc func makeKeyEventWithCode(_ keyCode: Int, _ isDown: Bool) -> HSEventTapEvent? {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(keyCode),
                                  keyDown: isDown) else {
            AKError("hs.eventtap.makeKeyEventWithCode: Failed to create event for keyCode \(keyCode)")
            return nil
        }
        return HSEventTapEvent(cgEvent: event)
    }

    @objc func makeMouseEvent(_ type: Int, _ x: Double, _ y: Double, _ button: Int) -> HSEventTapEvent? {
        guard let eventType = CGEventType(rawValue: UInt32(type)) else {
            AKError("hs.eventtap.makeMouseEvent: Unknown event type \(type)")
            return nil
        }
        let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .left
        let source = CGEventSource(stateID: .hidSystemState)
        // Hammerspoon coordinates (top-left origin, y-down) match CGEvent coordinates directly.
        guard let event = CGEvent(mouseEventSource: source,
                                  mouseType: eventType,
                                  mouseCursorPosition: CGPoint(x: x, y: y),
                                  mouseButton: mouseButton) else {
            AKError("hs.eventtap.makeMouseEvent: Failed to create mouse event")
            return nil
        }
        return HSEventTapEvent(cgEvent: event)
    }

    @objc func makeScrollWheelEvent(_ deltaX: Double, _ deltaY: Double, _ x: Double, _ y: Double) -> HSEventTapEvent? {
        let source = CGEventSource(stateID: .hidSystemState)

        // Guard against a number arriving from JS that is larger than Int32.max
        let w1 = Int32(max(Double(Int32.min), min(Double(Int32.max), deltaY)))
        let w2 = Int32(max(Double(Int32.min), min(Double(Int32.max), deltaX)))

        guard let event = CGEvent(scrollWheelEvent2Source: source,
                                  units: .line,
                                  wheelCount: 2,
                                  wheel1: w1,
                                  wheel2: w2,
                                  wheel3: 0) else {
            AKError("hs.eventtap.makeScrollWheelEvent: Failed to create scroll event")
            return nil
        }
        // Hammerspoon coordinates match CGEvent coordinates directly.
        event.location = CGPoint(x: x, y: y)
        return HSEventTapEvent(cgEvent: event)
    }

    // MARK: - Convenience senders

    @objc func keyStroke(_ mods: [String], _ key: String) {
        guard let keyCode = KeyCodeResolver.keyCode(for: key) else {
            AKError("hs.eventtap.keyStroke: Unknown key '\(key)'")
            return
        }
        let flags = CGEventFlags.from(modifierNames: mods)

        Task.detached(name: "keyStroke", priority: .userInitiated) {
            let source = CGEventSource(stateID: .hidSystemState)

            if let downEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                downEvent.flags = flags
                downEvent.post(tap: .cghidEventTap)
            }

            try? await Task.sleep(for: .milliseconds(50))

            if let upEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                upEvent.flags = flags
                upEvent.post(tap: .cghidEventTap)
            }
        }
    }

    @objc func keyStrokes(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        var events: [CGEvent] = []

        // Prepare an array of events we want to post
        for scalar in text.unicodeScalars {
            guard scalar.value <= 0xFFFF else { continue }
            var ch = UniChar(scalar.value)

            // For each event we need to post both a keyDown and a keyUp version.
            for keyPosition in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyPosition) else {
                    AKError("Unable to construct event for \(scalar)")
                    return
                }
                unsafe event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
                events.append(event)
            }
        }

        // Post the events from a separate thread, with a brief pause between them
        Task.detached(name: "keyStrokes", priority: .userInitiated) {
            for event in events {
                event.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    @objc func leftClick(_ x: Double, _ y: Double) {
        postMouseClick(type: .leftMouseDown, upType: .leftMouseUp,
                       button: .left, x: x, y: y, clickState: 1)
    }

    @objc func rightClick(_ x: Double, _ y: Double) {
        postMouseClick(type: .rightMouseDown, upType: .rightMouseUp,
                       button: .right, x: x, y: y, clickState: 1)
    }

    @objc func doubleLeftClick(_ x: Double, _ y: Double) {
        postMouseClick(type: .leftMouseDown, upType: .leftMouseUp,
                       button: .left, x: x, y: y, clickState: 1)
        postMouseClick(type: .leftMouseDown, upType: .leftMouseUp,
                       button: .left, x: x, y: y, clickState: 2)
    }

    @objc func middleClick(_ x: Double, _ y: Double) {
        postMouseClick(type: .otherMouseDown, upType: .otherMouseUp,
                       button: .center, x: x, y: y, clickState: 1)
    }

    @objc func scrollWheel(_ deltaX: Double, _ deltaY: Double, _ x: Double, _ y: Double) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Guard against a number arriving that is larger than Int32.max
        let w1 = Int32(max(Double(Int32.min), min(Double(Int32.max), deltaY)))
        let w2 = Int32(max(Double(Int32.min), min(Double(Int32.max), deltaX)))

        guard let event = CGEvent(scrollWheelEvent2Source: source,
                                  units: .line,
                                  wheelCount: 2,
                                  wheel1: w1,
                                  wheel2: w2,
                                  wheel3: 0) else { return }
        event.location = CGPoint(x: x, y: y)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - System state

    @objc func currentModifiers() -> [String] {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return CGEventFlags.modifierNames(from: flags)
    }

    @objc func checkMouseButtons() -> [String: Bool] {
        let left = CGEventSource.buttonState(.hidSystemState, button: .left)
        let right = CGEventSource.buttonState(.hidSystemState, button: .right)
        let middle = CGEventSource.buttonState(.hidSystemState, button: .center)
        return ["left": left, "right": right, "middle": middle]
    }

    @objc func mouseLocation() -> [String: Double] {
        let loc = NSEvent.mouseLocation
        // NSEvent.mouseLocation uses AppKit coordinates (y=0 at bottom of primary screen, y-up).
        // Convert to Hammerspoon coordinates (y=0 at top of primary screen, y-down).
        // The primary screen is the one whose AppKit frame origin is at (0, 0); its height
        // is the correct flip baseline regardless of which physical screen the cursor is on.
        let primaryHeight = NSScreen.screens
            .first(where: { $0.frame.origin == .zero })?
            .frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        return ["x": Double(loc.x), "y": Double(primaryHeight - loc.y)]
    }

    @objc func doubleClickInterval() -> Double {
        return NSEvent.doubleClickInterval
    }

    @objc func keyRepeatDelay() -> Double {
        return NSEvent.keyRepeatDelay
    }

    @objc func keyRepeatInterval() -> Double {
        return NSEvent.keyRepeatInterval
    }

    // MARK: - Private helpers

    private func postMouseClick(type: CGEventType, upType: CGEventType,
                                button: CGMouseButton, x: Double, y: Double,
                                clickState: Int64) {
        // Hammerspoon coordinates match CGEvent coordinates directly.
        let point = CGPoint(x: x, y: y)
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(mouseEventSource: source, mouseType: type,
                              mouseCursorPosition: point, mouseButton: button) {
            down.setIntegerValueField(.mouseEventClickState, value: clickState)
            down.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.05)
        if let up = CGEvent(mouseEventSource: source, mouseType: upType,
                            mouseCursorPosition: point, mouseButton: button) {
            up.setIntegerValueField(.mouseEventClickState, value: clickState)
            up.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Key name → CGKeyCode mapping

/// Builds a combined lookup table from HSKeycodesModule's static key tables,
/// so the eventtap module does not duplicate the key name definitions.
private enum KeyCodeResolver {
    static let keyMap: [String: CGKeyCode] = {
        var map: [String: CGKeyCode] = [:]
        // Character map loaded first (lower priority — named keys override where names overlap)
        for (name, code) in HSKeycodesModule.ansiUSCharacterMap {
            map[name] = CGKeyCode(code)
        }
        // Named special/function/modifier keys loaded second (higher priority)
        for (name, code) in HSKeycodesModule.namedKeys {
            map[name] = CGKeyCode(code)
        }
        return map
    }()

    static func keyCode(for name: String) -> CGKeyCode? {
        let lower = name.lowercased()
        if let code = keyMap[lower] { return code }
        // Allow raw numeric key codes passed as strings (e.g. "36" for Return)
        if let code = UInt16(name) { return CGKeyCode(code) }
        return nil
    }
}
