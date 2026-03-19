//
//  HSScreen.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import CoreGraphics
import JavaScriptCore
import ScreenCaptureKit


// MARK: - JavaScript API

/// An object representing a single display attached to the system.
///
/// ## Coordinate system
///
/// All geometry is returned in **Hammerspoon screen coordinates**: the origin `(0, 0)`
/// is at the top-left of the primary display, and `y` increases downward.
/// This matches Hammerspoon v1 and is the inverse of the raw macOS/CoreGraphics convention.
///
/// ## Examples
///
/// ```javascript
/// const s = hs.screen.main();
/// console.log(s.name);               // e.g. "Built-in Retina Display"
/// console.log(s.frame.w);            // usable width in points
///
/// console.log(s.mode.width, s.mode.scale); // e.g. 1440, 2
///
/// s.desktopImage = "/Users/me/wallpaper.jpg";
/// ```
@objc protocol HSScreenAPI: HSTypeAPI, JSExport {

    // MARK: - Identity

    /// Unique display identifier (matches `CGDirectDisplayID`).
    @objc var id: Int { get }

    /// The manufacturer-assigned localized display name.
    @objc var name: String { get }

    /// The display's UUID string.
    @objc var uuid: String { get }

    // MARK: - Geometry

    /// The usable screen area in Hammerspoon coordinates, excluding the menu bar and Dock.
    @objc var frame: HSRect { get }

    /// The full screen area in Hammerspoon coordinates, including menu bar and Dock regions.
    @objc var fullFrame: HSRect { get }

    /// The screen's top-left corner in global Hammerspoon coordinates.
    @objc var position: HSPoint { get }

    // MARK: - Display Modes

    /// The currently active display mode.
    ///
    /// An object with keys: `width`, `height`, `scale`, `frequency`.
    @objc var mode: NSDictionary { get }

    /// All display modes supported by this screen.
    ///
    /// Each element has keys: `width`, `height`, `scale`, `frequency`.
    @objc var availableModes: [NSDictionary] { get }

    /// Switch to the given display mode.
    ///
    /// Pass `0` for `scale` or `frequency` to match any value.
    ///
    /// - Parameters:
    ///   - width: Horizontal resolution in pixels.
    ///   - height: Vertical resolution in pixels.
    ///   - scale: Backing scale factor (e.g. `2` for HiDPI, `1` for non-HiDPI). Pass `0` to ignore.
    ///   - frequency: Refresh rate in Hz. Pass `0` to ignore.
    /// - Returns: `true` on success.
    @objc func setMode(_ width: Int, _ height: Int, _ scale: Double, _ frequency: Double) -> Bool

    // MARK: - Rotation

    /// The current screen rotation in degrees (0, 90, 180, or 270).
    ///
    /// Assign one of `0`, `90`, `180`, or `270` to rotate the display.
    @objc var rotation: Double { get set }

    // MARK: - Screenshot

    /// Capture the current contents of this screen as an image.
    ///
    /// Requires **Screen Recording** permission.
    ///
    /// - Returns: {Promise<HSImage>} Resolves with the captured image, or rejects if the capture fails (e.g. permission denied).
    @objc func snapshot() -> JSPromise?

    // MARK: - Navigation

    /// The next screen in `hs.screen.all()` order, wrapping around.
    /// - Returns: An HSScreen object
    @objc func next() -> HSScreen

    /// The previous screen in `hs.screen.all()` order, wrapping around.
    /// - Returns: An HSScreen object
    @objc func previous() -> HSScreen

    /// The nearest screen whose left edge is at or beyond this screen's right edge, or `null`.
    /// - Returns: An HSScreen object
    @objc func toEast() -> HSScreen?

    /// The nearest screen whose right edge is at or before this screen's left edge, or `null`.
    /// - Returns: An HSScreen object
    @objc func toWest() -> HSScreen?

    /// The nearest screen that is physically above this screen, or `null`.
    /// - Returns: An HSScreen object
    @objc func toNorth() -> HSScreen?

    /// The nearest screen that is physically below this screen, or `null`.
    /// - Returns: An HSScreen object
    @objc func toSouth() -> HSScreen?

    // MARK: - Configuration

    /// Move this screen so its top-left corner is at the given position in global Hammerspoon coordinates.
    ///
    /// - Parameters:
    ///   - x: The X coordinate to move to
    ///   - y: The Y coordinate to move to
    /// - Returns: `true` on success.
    @objc func setOrigin(_ x: Double, _ y: Double) -> Bool

    /// Designate this screen as the primary display (moves the menu bar here).
    ///
    /// - Returns: `true` on success.
    @objc func setPrimary() -> Bool

    /// Configure this screen to mirror another screen.
    ///
    /// - Parameter screen: The screen to mirror.
    /// - Returns: `true` on success.
    @objc func mirrorOf(_ screen: HSScreen) -> Bool

    /// Stop mirroring, restoring this screen to an independent display.
    ///
    /// - Returns: `true` on success.
    @objc func mirrorStop() -> Bool

    // MARK: - Coordinate Conversion

    /// Convert a rect in global Hammerspoon coordinates to coordinates local to this screen.
    ///
    /// The result origin is relative to this screen's top-left corner.
    ///
    /// - Parameter rect: An `HSRect` in global Hammerspoon coordinates.
    /// - Returns: The rect offset to be relative to this screen's top-left, or `null` if the input is invalid.
    @objc func absoluteToLocal(_ rect: JSValue) -> HSRect?

    /// Convert a rect in local screen coordinates to global Hammerspoon coordinates.
    ///
    /// - Parameter rect: An `HSRect` relative to this screen's top-left corner.
    /// - Returns: The rect in global Hammerspoon coordinates, or `null` if the input is invalid.
    @objc func localToAbsolute(_ rect: JSValue) -> HSRect?

    // MARK: - Desktop

    /// The URL string of the current desktop background image for this screen, or `null`.
    ///
    /// Assign a new absolute file path or `file://` URL string to change the wallpaper.
    @objc var desktopImage: String? { get set }
}

// MARK: - CGDisplayMode helpers

private extension CGDisplayMode {
    /// Pixel-to-point scale factor (e.g. 2.0 for HiDPI/Retina, 1.0 otherwise).
    var modeScale: Double {
        width > 0 ? Double(pixelWidth) / Double(width) : 1.0
    }

    /// Serialised representation passed to JavaScript.
    var asDictionary: NSDictionary {
        ["width": width, "height": height, "scale": modeScale, "frequency": refreshRate]
    }
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSScreen: NSObject, HSScreenAPI {
    @objc var typeName = "HSScreen"
    let screen: NSScreen

    init(screen: NSScreen) {
        self.screen = screen
        super.init()
    }

    // MARK: - Private

    var displayID: CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Height of the primary display in macOS points, used as the flip baseline.
    private var primaryScreenHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0}

    /// Converts a rect from macOS coordinates (origin bottom-left, y-up) to
    /// Hammerspoon coordinates (origin top-left of primary screen, y-down).
    private func flip(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.origin.x,
               y: primaryScreenHeight - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }

    // MARK: - Identity

    @objc var id: Int { Int(displayID) }

    @objc var name: String { screen.localizedName }

    @objc var uuid: String {
        guard let cfUUID = unsafe CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return ""
        }
        return CFUUIDCreateString(nil, cfUUID) as String? ?? ""
    }

    // MARK: - Geometry

    @objc var frame: HSRect { flip(screen.visibleFrame).toBridge() }

    @objc var fullFrame: HSRect { flip(screen.frame).toBridge() }

    @objc var position: HSPoint {
        let origin = flip(screen.frame).origin
        return HSPoint(x: Double(origin.x), y: Double(origin.y))
    }

    // MARK: - Display Modes

    // Memory note: CGDisplayCopyDisplayMode / CGDisplayCopyAllDisplayModes follow the CF "Copy"
    // rule (caller owns +1).  Swift bridges CGDisplayMode as an ARC-managed class, so the
    // compiler inserts releases automatically — no manual CFRelease needed.

    @objc var mode: NSDictionary {
        guard let cgMode = CGDisplayCopyDisplayMode(displayID) else { return [:] }
        return cgMode.asDictionary
    }

    @objc var availableModes: [NSDictionary] {
        // kCGDisplayShowDuplicateLowResolutionModes is required to surface HiDPI (Retina) modes
        // that CGDisplayCopyAllDisplayModes would otherwise omit when called with nil options.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let cfArray = CGDisplayCopyAllDisplayModes(displayID, options),
              let cgModes = cfArray as? [CGDisplayMode] else {
            return []
        }
        return cgModes.map(\.asDictionary)
    }

    @objc func setMode(_ width: Int, _ height: Int, _ scale: Double, _ frequency: Double) -> Bool {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let cfArray = CGDisplayCopyAllDisplayModes(displayID, options),
              let modes = cfArray as? [CGDisplayMode] else {
            return false
        }
        guard let match = modes.first(where: {
            $0.width == width &&
            $0.height == height &&
            (scale == 0     || Int($0.modeScale) == Int(scale)) &&
            (frequency == 0 || $0.refreshRate == frequency)
        }) else {
            AKError("hs.screen: no mode found matching \(width)×\(height) scale:\(scale) freq:\(frequency)")
            return false
        }
        var config: CGDisplayConfigRef?
        guard unsafe CGBeginDisplayConfiguration(&config) == .success else { return false }
        unsafe CGConfigureDisplayWithDisplayMode(config, displayID, match, nil)
        return unsafe CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    // MARK: - Rotation

    @objc var rotation: Double {
        get { CGDisplayRotation(displayID) }
        set {
            guard newValue == 0 || newValue == 90 || newValue == 180 || newValue == 270 else {
                AKError("hs.screen.rotation: invalid value \(newValue); must be 0, 90, 180, or 270")
                return
            }
            if !HSScreenSetRotation(displayID, Int32(newValue)) {
                AKError("hs.screen.rotation: failed to set rotation to \(newValue) degrees")
            }
        }
    }

    // MARK: - Screenshot

    @objc func snapshot() -> JSPromise? {
        let capturedDisplayID = displayID
        let frameSize = screen.frame.size

        return JSEngine.shared.createPromise { holder in
            Task.detached {
                do {
                    let content = try await SCShareableContent.current
                    guard let scDisplay = content.displays.first(where: { $0.displayID == capturedDisplayID }) else {
                        await holder.rejectWithMessage("hs.screen.snapshot: could not locate display \(capturedDisplayID)")
                        return
                    }

                    let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

                    let config = SCStreamConfiguration()
                    config.width = Int(CGDisplayPixelsWide(capturedDisplayID))
                    config.height = Int(CGDisplayPixelsHigh(capturedDisplayID))
                    config.showsCursor = false

                    let cgImage = try await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: config
                    )
                    await holder.resolveWith(HSImage(image: NSImage(cgImage: cgImage, size: frameSize)))
                } catch {
                    await holder.rejectWithMessage("hs.screen.snapshot: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Navigation

    @objc func next() -> HSScreen {
        let screens = NSScreen.screens
        guard let idx = screens.firstIndex(of: screen) else { return self }
        return HSScreen(screen: screens[(idx + 1) % screens.count])
    }

    @objc func previous() -> HSScreen {
        let screens = NSScreen.screens
        guard let idx = screens.firstIndex(of: screen) else { return self }
        return HSScreen(screen: screens[(idx - 1 + screens.count) % screens.count])
    }

    /// Returns the closest screen in the given direction, or nil if none exists.
    ///
    /// Comparisons are performed in raw macOS coordinates (y-up) to determine
    /// physical adjacency; the direction names map to physical screen positions.
    private enum Direction { case east, west, north, south }

    private func nearestScreen(in direction: Direction) -> HSScreen? {
        let sf = screen.frame
        typealias Candidate = (screen: NSScreen, dist: CGFloat)
        let candidates: [Candidate] = NSScreen.screens.compactMap { candidate in
            guard candidate != screen else { return nil }
            let cf = candidate.frame
            switch direction {
            case .east:
                guard cf.minX >= sf.maxX else { return nil }
                return (candidate, cf.minX - sf.maxX)
            case .west:
                guard cf.maxX <= sf.minX else { return nil }
                return (candidate, sf.minX - cf.maxX)
            case .north:
                guard cf.minY >= sf.maxY else { return nil }
                return (candidate, cf.minY - sf.maxY)
            case .south:
                guard cf.maxY <= sf.minY else { return nil }
                return (candidate, sf.minY - cf.maxY)
            }
        }
        guard let best = candidates.min(by: { $0.dist < $1.dist }) else { return nil }
        return HSScreen(screen: best.screen)
    }

    @objc func toEast() -> HSScreen? { nearestScreen(in: .east) }
    @objc func toWest() -> HSScreen? { nearestScreen(in: .west) }
    @objc func toNorth() -> HSScreen? { nearestScreen(in: .north) }
    @objc func toSouth() -> HSScreen? { nearestScreen(in: .south) }

    // MARK: - Configuration

    @objc func setOrigin(_ x: Double, _ y: Double) -> Bool {
        // x, y are in Hammerspoon coordinates (top-left origin, y-down).
        // CGConfigureDisplayOrigin expects macOS coordinates (bottom-left origin, y-up).
        let macY = Double(primaryScreenHeight) - y - Double(screen.frame.height)
        var config: CGDisplayConfigRef?
        guard unsafe CGBeginDisplayConfiguration(&config) == .success else { return false }
        unsafe CGConfigureDisplayOrigin(config, displayID, Int32(x), Int32(macY))

        return unsafe CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    @objc func setPrimary() -> Bool {
        // Shift all displays so this display's origin becomes (0, 0).
        let selfOrigin = screen.frame.origin
        let dx = Int32(selfOrigin.x)
        let dy = Int32(selfOrigin.y)
        var config: CGDisplayConfigRef?
        guard unsafe CGBeginDisplayConfiguration(&config) == .success else { return false }
        for s in NSScreen.screens {
            guard let sid = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            let o = s.frame.origin
            unsafe CGConfigureDisplayOrigin(config, sid, Int32(o.x) - dx, Int32(o.y) - dy)
        }
        return unsafe CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    @objc func mirrorOf(_ screen: HSScreen) -> Bool {
        var config: CGDisplayConfigRef?
        guard unsafe CGBeginDisplayConfiguration(&config) == .success else { return false }
        unsafe CGConfigureDisplayMirrorOfDisplay(config, displayID, screen.displayID)
        return unsafe CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    @objc func mirrorStop() -> Bool {
        var config: CGDisplayConfigRef?
        guard unsafe CGBeginDisplayConfiguration(&config) == .success else { return false }
        unsafe CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)
        return unsafe CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    // MARK: - Coordinate Conversion

    @objc func absoluteToLocal(_ rect: JSValue) -> HSRect? {
        guard let hsRect = rect.toObjectOf(HSRect.self) as? HSRect else { return nil }
        let screenOrigin = flip(screen.frame).origin
        return HSRect(x: hsRect.x - Double(screenOrigin.x),
                      y: hsRect.y - Double(screenOrigin.y),
                      w: hsRect.w, h: hsRect.h)
    }

    @objc func localToAbsolute(_ rect: JSValue) -> HSRect? {
        guard let hsRect = rect.toObjectOf(HSRect.self) as? HSRect else { return nil }
        let screenOrigin = flip(screen.frame).origin
        return HSRect(x: hsRect.x + Double(screenOrigin.x),
                      y: hsRect.y + Double(screenOrigin.y),
                      w: hsRect.w, h: hsRect.h)
    }

    // MARK: - Desktop

    @objc var desktopImage: String? {
        get {
            NSWorkspace.shared.desktopImageURL(for: screen)?.absoluteString
        }
        set {
            guard let path = newValue else { return }

            let url: URL
            if path.hasPrefix("file://") {
                guard let fileURL = URL(string: path) else {
                    AKError("hs.screen.desktopImage: Invalid URL")
                    return
                }
                url = fileURL
            } else {
                url = URL(fileURLWithPath: path)
            }

            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                AKError("hs.screen.desktopImage: \(error.localizedDescription)")
            }
        }
    }
}
