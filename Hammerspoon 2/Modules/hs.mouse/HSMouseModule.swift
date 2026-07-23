//
//  HSMouseModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import AppKit
import CoreGraphics
import IOKit

// MARK: - IOKit helpers (file-scope, no actor isolation needed)

/// Enumerate IOHIDDevice services and filter those whose `PrimaryUsagePage` is 1 (Generic Desktop)
/// and `PrimaryUsage` is 2 (Mouse). Uses the same IOService iteration pattern as hs.usb so that
/// CF-type casting issues are avoided entirely — properties are extracted as `[String: Any]`.
///
/// When `includeInternal` is `false`, devices whose `Transport` is `"SPI"` are excluded; those
/// are typically the built-in MacBook trackpad.
private func mouseDeviceInfos(includeInternal: Bool) -> [(name: String, transport: String)] {
    var iterator: io_iterator_t = IO_OBJECT_NULL
    guard unsafe IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else {
        return []
    }
    defer { IOObjectRelease(iterator) }

    var result: [(name: String, transport: String)] = []
    var service = IOIteratorNext(iterator)
    while service != IO_OBJECT_NULL {
        defer {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        guard unsafe IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unsafe propertiesRef?.takeRetainedValue() as? [String: Any] else { continue }

        // Filter to mouse usage class (kHIDPage_GenericDesktop = 1, kHIDUsage_GD_Mouse = 2).
        guard let usagePage = props["PrimaryUsagePage"] as? Int, usagePage == 1,
              let usage = props["PrimaryUsage"] as? Int, usage == 2 else { continue }

        let name = props["Product"] as? String ?? "Unknown"
        let transport = props["Transport"] as? String ?? ""
        if !includeInternal && transport == "SPI" { continue }
        result.append((name: name, transport: transport))
    }
    return result
}

/// Opens a connection to the IOHIDSystem event driver for reading/writing HID parameters.
/// The caller is responsible for calling `IOServiceClose` on the returned handle when done.
/// Returns `IO_OBJECT_NULL` on failure.
private func openHIDEventDriver() -> io_connect_t {
    let service = unsafe IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != IO_OBJECT_NULL else { return IO_OBJECT_NULL }
    defer { IOObjectRelease(service) }
    var connect: io_connect_t = IO_OBJECT_NULL
    // kIOHIDParamConnectType = 1 (IOKit/hidsystem/IOHIDShared.h)
    let kr: kern_return_t = unsafe IOServiceOpen(service, mach_task_self_, 1, &connect)
    guard kr == KERN_SUCCESS else {
        return IO_OBJECT_NULL
    }
    return connect
}

// MARK: - Module API

/// Control and inspect the mouse pointer and attached mouse devices.
///
/// ## Position
///
/// All coordinates use **Hammerspoon screen coordinates**: `(0, 0)` is at the top-left
/// of the primary display and `y` increases downward.
///
/// ```js
/// const pos = hs.mouse.absolutePosition()
/// console.log("Mouse at " + pos.x + ", " + pos.y)
///
/// hs.mouse.setAbsolutePosition(100, 200)
/// ```
///
/// ## Device info
///
/// ```js
/// console.log("Mice: " + hs.mouse.count())
/// hs.mouse.names().forEach(n => console.log(n))
/// ```
///
/// ## Cursor
///
/// ```js
/// console.log(hs.mouse.currentCursorType())   // e.g. "arrow"
/// console.log(hs.mouse.scrollDirection())      // "natural" or "normal"
/// ```
@objc protocol HSMouseModuleAPI: JSExport {

    // MARK: - Position

    /// Returns the current mouse pointer position in Hammerspoon screen coordinates.
    ///
    /// Hammerspoon coordinates have `(0, 0)` at the top-left of the primary display,
    /// with `y` increasing downward.
    /// - Returns: An object with `x` and `y` number properties.
    /// - Example:
    /// ```js
    /// const pos = hs.mouse.absolutePosition()
    /// console.log("x=" + pos.x + " y=" + pos.y)
    /// ```
    @objc func absolutePosition() -> [String: Double]

    /// Moves the mouse pointer to the specified absolute position in Hammerspoon screen coordinates.
    ///
    /// - Parameter x: Horizontal position; `0` is the left edge of the primary display.
    /// - Parameter y: Vertical position; `0` is the top edge of the primary display.
    /// - Example:
    /// ```js
    /// hs.mouse.setAbsolutePosition(100, 200)
    /// ```
    @objc func setAbsolutePosition(_ x: Double, _ y: Double)

    /// Returns the mouse pointer position relative to the screen it is currently on.
    ///
    /// The returned coordinates have `(0, 0)` at the top-left corner of the screen
    /// that the cursor is on.
    /// - Returns: An object with `x` and `y` number properties, or `null` if no screen can be determined.
    /// - Example:
    /// ```js
    /// const rel = hs.mouse.getRelativePosition()
    /// if (rel) console.log("x=" + rel.x + " y=" + rel.y)
    /// ```
    @objc func getRelativePosition() -> [String: Double]?

    /// Moves the mouse pointer to a position relative to the screen it is currently on.
    ///
    /// - Parameter x: Horizontal offset from the current screen's left edge.
    /// - Parameter y: Vertical offset from the current screen's top edge.
    /// - Example:
    /// ```js
    /// hs.mouse.setRelativePosition(0, 0)  // move to top-left of current screen
    /// ```
    @objc func setRelativePosition(_ x: Double, _ y: Double)

    // MARK: - Screen

    /// Returns the screen that the mouse pointer is currently on.
    ///
    /// - Returns: An HSScreen object for the display containing the cursor, or `null` if none can be determined.
    /// - Example:
    /// ```js
    /// const s = hs.mouse.getCurrentScreen()
    /// if (s) console.log("Mouse is on: " + s.name)
    /// ```
    @objc func getCurrentScreen() -> HSScreen?

    // MARK: - Devices

    /// Returns the number of mouse devices currently attached to the system.
    ///
    /// - Parameter includeInternal: When `true`, built-in pointing devices (e.g. the MacBook built-in trackpad) are included. Defaults to `false`.
    /// - Returns: The number of attached mouse devices.
    /// - Example:
    /// ```js
    /// console.log("External mice: " + hs.mouse.count())
    /// console.log("All pointing devices: " + hs.mouse.count(true))
    /// ```
    @objc func count(_ includeInternal: Bool) -> Int

    /// Returns the product names of all mouse devices currently attached to the system.
    ///
    /// - Parameter includeInternal: When `true`, built-in pointing devices are included. Defaults to `false`.
    /// - Returns: An array of product name strings.
    /// - Example:
    /// ```js
    /// hs.mouse.names().forEach(n => console.log(n))
    /// ```
    @objc func names(_ includeInternal: Bool) -> [String]

    // MARK: - Settings

    /// Returns the current mouse tracking speed (acceleration level).
    ///
    /// Values range from `-1.0` (system default, acceleration disabled) to `3.0` (maximum acceleration).
    /// Returns `-1.0` if the value cannot be read.
    /// - Returns: The current tracking speed as a number.
    /// - Example:
    /// ```js
    /// console.log("Tracking speed: " + hs.mouse.trackingSpeed())
    /// ```
    @objc func trackingSpeed() -> Double

    /// Sets the mouse tracking speed (acceleration level).
    ///
    /// The change takes effect immediately for the current login session and is also persisted
    /// to preferences so it survives a restart. Values outside the valid range or non-finite
    /// values are rejected with a warning and no change is made.
    /// - Parameter speed: Desired tracking speed in the range `-1.0` to `3.0`.
    /// - Example:
    /// ```js
    /// hs.mouse.setTrackingSpeed(1.5)
    /// ```
    @objc func setTrackingSpeed(_ speed: Double)

    /// Returns the current scroll wheel direction setting.
    ///
    /// - Returns: `"natural"` if content scrolls in the same direction as the finger/wheel movement (macOS default), or `"normal"` for the traditional direction.
    /// - Example:
    /// ```js
    /// console.log(hs.mouse.scrollDirection())
    /// ```
    @objc func scrollDirection() -> String

    // MARK: - Cursor

    /// Returns the name of the cursor type currently set by this application.
    ///
    /// - Note: This reflects the cursor set by the Hammerspoon process. If another application
    ///   has the keyboard focus, the visible system cursor may differ.
    /// - Returns: A string such as `"arrow"`, `"iBeam"`, `"crosshair"`, `"pointingHand"`,
    ///   `"openHand"`, `"closedHand"`, `"resizeLeft"`, `"resizeRight"`, `"resizeLeftRight"`,
    ///   `"resizeUp"`, `"resizeDown"`, `"resizeUpDown"`, `"operationNotAllowed"`,
    ///   `"dragLink"`, `"dragCopy"`, `"contextualMenu"`,
    ///   `"iBeamCursorForVerticalLayout"`, or `"unknown"`.
    /// - Example:
    /// ```js
    /// console.log(hs.mouse.currentCursorType())
    /// ```
    @objc func currentCursorType() -> String
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSMouseModule: NSObject, HSModuleAPI, HSMouseModuleAPI {
    var name = "hs.mouse"
    let engineID: UUID

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {}

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - Position

    @objc func absolutePosition() -> [String: Double] {
        let loc = NSEvent.mouseLocation
        // NSEvent.mouseLocation uses AppKit coordinates (y=0 at bottom of primary screen, y-up).
        // Convert to Hammerspoon coordinates (y=0 at top of primary screen, y-down).
        // The primary screen is the one whose AppKit frame origin is at (0, 0).
        let primaryHeight = NSScreen.screens
            .first(where: { $0.frame.origin == .zero })?
            .frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        return ["x": Double(loc.x), "y": Double(primaryHeight - loc.y)]
    }

    @objc func setAbsolutePosition(_ x: Double, _ y: Double) {
        // CGWarpMouseCursorPosition uses global display coordinates:
        // (0,0) = top-left of primary display, y increases downward — same as Hammerspoon.
        CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
    }

    @objc func getRelativePosition() -> [String: Double]? {
        guard let screen = getCurrentScreen() else { return nil }
        let abs = absolutePosition()
        let sx = screen.position.x
        let sy = screen.position.y
        return ["x": (abs["x"] ?? 0) - sx, "y": (abs["y"] ?? 0) - sy]
    }

    @objc func setRelativePosition(_ x: Double, _ y: Double) {
        guard let screen = getCurrentScreen() else { return }
        let sx = screen.position.x
        let sy = screen.position.y
        setAbsolutePosition(sx + x, sy + y)
    }

    // MARK: - Screen

    @objc func getCurrentScreen() -> HSScreen? {
        // NSEvent.mouseLocation is in AppKit coordinates (y-up from bottom of primary screen).
        // NSScreen.frame is also in AppKit coordinates, so the containment check is direct.
        let loc = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(loc) {
                return HSScreen(screen: screen)
            }
        }
        return nil
    }

    // MARK: - Devices

    @objc func count(_ includeInternal: Bool) -> Int {
        mouseDeviceInfos(includeInternal: includeInternal).count
    }

    @objc func names(_ includeInternal: Bool) -> [String] {
        mouseDeviceInfos(includeInternal: includeInternal).map { $0.name }
    }

    // MARK: - Settings

    @objc func trackingSpeed() -> Double {
        let connect = openHIDEventDriver()
        guard connect != IO_OBJECT_NULL else {
            AKWarning("hs.mouse.trackingSpeed(): Failed to open HID event driver")
            return -1.0
        }
        defer { IOServiceClose(connect) }
        var speed: Double = -1.0
        _ = unsafe hs_IOHIDGetAccelerationWithKey(connect, "HIDMouseAcceleration" as CFString, &speed)
        return speed
    }

    @objc func setTrackingSpeed(_ speed: Double) {
        guard speed.isFinite && speed >= -1.0 && speed <= 3.0 else {
            AKWarning("hs.mouse.setTrackingSpeed(): speed must be in the range -1.0 to 3.0 (got \(speed))")
            return
        }
        let connect = openHIDEventDriver()
        guard connect != IO_OBJECT_NULL else {
            AKWarning("hs.mouse.setTrackingSpeed(): Failed to open HID event driver")
            return
        }
        defer { IOServiceClose(connect) }
        _ = hs_IOHIDSetAccelerationWithKey(connect, "HIDMouseAcceleration" as CFString, speed)

        // Persist so the value survives a restart.
        CFPreferencesSetValue(
            "com.apple.mouse.scaling" as CFString,
            NSNumber(value: speed),
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    @objc func scrollDirection() -> String {
        let val = CFPreferencesCopyValue(
            "com.apple.swipescrolldirection" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        // `true` (or missing) means natural scrolling (macOS default since Lion).
        let isNatural = (val as? NSNumber)?.boolValue ?? true
        return isNatural ? "natural" : "normal"
    }

    // MARK: - Cursor

    @objc func currentCursorType() -> String {
        let current = NSCursor.current
        guard let currentTiff = current.image.tiffRepresentation else { return "unknown" }

        let knownCursors: [(String, NSCursor)] = [
            ("arrow", .arrow),
            ("iBeam", .iBeam),
            ("crosshair", .crosshair),
            ("closedHand", .closedHand),
            ("openHand", .openHand),
            ("pointingHand", .pointingHand),
            ("resizeLeft", .resizeLeft),
            ("resizeRight", .resizeRight),
            ("resizeLeftRight", .resizeLeftRight),
            ("resizeUp", .resizeUp),
            ("resizeDown", .resizeDown),
            ("resizeUpDown", .resizeUpDown),
            ("iBeamCursorForVerticalLayout", .iBeamCursorForVerticalLayout),
            ("operationNotAllowed", .operationNotAllowed),
            ("dragLink", .dragLink),
            ("dragCopy", .dragCopy),
            ("contextualMenu", .contextualMenu),
        ]

        for (typeName, cursor) in knownCursors {
            if cursor.image.tiffRepresentation == currentTiff {
                return typeName
            }
        }
        return "unknown"
    }
}
