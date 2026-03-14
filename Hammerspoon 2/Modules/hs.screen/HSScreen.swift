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
/// Obtain instances from `hs.screen.allScreens()`, `hs.screen.mainScreen()`, or
/// `hs.screen.primaryScreen()` — do not construct these directly.
///
/// ## Coordinate system
///
/// All geometry is returned in **macOS screen coordinates**: the origin `(0, 0)`
/// is at the bottom-left of the primary display, and `y` increases upward.
/// This is the same coordinate system used by `NSScreen` and `CGDisplay` APIs.
///
/// ## Examples
///
/// ```javascript
/// const s = hs.screen.mainScreen();
/// console.log(s.name);               // e.g. "Built-in Retina Display"
/// console.log(s.frame().w);          // usable width in points
///
/// const mode = s.currentMode();
/// console.log(mode.width, mode.scale); // e.g. 1440, 2
///
/// s.setDesktopImage("/Users/me/wallpaper.jpg");
/// ```
@objc protocol HSScreenAPI: JSExport {

    // MARK: - Identity

    /// Unique display identifier (matches `CGDirectDisplayID`).
    @objc var id: Int { get }

    /// The manufacturer-assigned localized display name.
    @objc var name: String { get }

    /// The display's UUID string.
    @objc var uuid: String { get }

    // MARK: - Geometry

    /// The usable screen area in screen coordinates, excluding the menu bar and Dock.
    @objc func frame() -> HSRect

    /// The full screen area in screen coordinates, including menu bar and Dock regions.
    @objc func fullFrame() -> HSRect

    /// The screen's origin point relative to the primary display's bottom-left corner.
    @objc func position() -> HSPoint

    // MARK: - Display Modes

    /// The currently active display mode.
    ///
    /// Returns an object with keys: `width`, `height`, `scale`, `frequency`.
    @objc func currentMode() -> NSDictionary

    /// All display modes supported by this screen.
    ///
    /// Each element has keys: `width`, `height`, `scale`, `frequency`.
    @objc func availableModes() -> [NSDictionary]

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
    @objc func rotation() -> Double

    // MARK: - Screenshot

    /// Capture the current contents of this screen as an image.
    ///
    /// Requires **Screen Recording** permission.
    ///
    /// - Returns: {Promise<HSImage>} Resolves with the captured image, or rejects if the
    ///   capture fails (e.g. permission denied).
    @objc func snapshot() -> JSPromise?

    // MARK: - Navigation

    /// The next screen in `hs.screen.allScreens()` order, wrapping around.
    @objc func next() -> HSScreen

    /// The previous screen in `hs.screen.allScreens()` order, wrapping around.
    @objc func previous() -> HSScreen

    /// The nearest screen whose left edge is at or beyond this screen's right edge, or `null`.
    @objc func toEast() -> HSScreen?

    /// The nearest screen whose right edge is at or before this screen's left edge, or `null`.
    @objc func toWest() -> HSScreen?

    /// The nearest screen whose bottom edge is at or above this screen's top edge, or `null`.
    ///
    /// *Note:* "north" means higher `y` values in macOS screen coordinates.
    @objc func toNorth() -> HSScreen?

    /// The nearest screen whose top edge is at or below this screen's bottom edge, or `null`.
    @objc func toSouth() -> HSScreen?

    // MARK: - Configuration

    /// Move this screen so its bottom-left corner is at the given global position.
    ///
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

    /// Convert a rect in global screen coordinates to coordinates local to this screen.
    ///
    /// The result origin is relative to this screen's bottom-left corner.
    ///
    /// - Parameter rect: An `HSRect` in global screen coordinates.
    /// - Returns: The rect offset to be relative to this screen, or `null` if the input is invalid.
    @objc func absoluteToLocal(_ rect: JSValue) -> HSRect?

    /// Convert a rect in local screen coordinates to global screen coordinates.
    ///
    /// - Parameter rect: An `HSRect` relative to this screen's bottom-left corner.
    /// - Returns: The rect in global screen coordinates, or `null` if the input is invalid.
    @objc func localToAbsolute(_ rect: JSValue) -> HSRect?

    // MARK: - Desktop

    /// The URL string of the current desktop background image for this screen, or `null`.
    @objc func desktopImage() -> String?

    /// Set the desktop background image for this screen.
    ///
    /// - Parameter path: Absolute file path or `file://` URL string.
    /// - Returns: `true` on success.
    @objc func setDesktopImage(_ path: String) -> Bool
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

    @objc func frame() -> HSRect { screen.visibleFrame.toBridge() }

    @objc func fullFrame() -> HSRect { screen.frame.toBridge() }

    @objc func position() -> HSPoint {
        HSPoint(x: Double(screen.frame.origin.x), y: Double(screen.frame.origin.y))
    }

    // MARK: - Display Modes

    @objc func currentMode() -> NSDictionary {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return [:] }
        let scale = mode.width > 0 ? Double(mode.pixelWidth) / Double(mode.width) : 1.0
        return [
            "width": mode.width,
            "height": mode.height,
            "scale": scale,
            "frequency": mode.refreshRate,
        ]
    }

    @objc func availableModes() -> [NSDictionary] {
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return []
        }
        return modes.map { mode in
            let scale = mode.width > 0 ? Double(mode.pixelWidth) / Double(mode.width) : 1.0
            return [
                "width": mode.width,
                "height": mode.height,
                "scale": scale,
                "frequency": mode.refreshRate,
            ]
        }
    }

    @objc func setMode(_ width: Int, _ height: Int, _ scale: Double, _ frequency: Double) -> Bool {
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return false
        }
        guard let mode = modes.first(where: {
            $0.width == width &&
            $0.height == height &&
            (scale == 0 || Double($0.pixelWidth) / Double(max($0.width, 1)) == scale) &&
            (frequency == 0 || $0.refreshRate == frequency)
        }) else {
            AKError("hs.screen: no mode found matching \(width)×\(height) scale:\(scale) freq:\(frequency)")
            return false
        }
        var config: CGDisplayConfigRef?
        guard unsafe CGBeginDisplayConfiguration(&config) == .success else { return false }
        unsafe CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)

        return unsafe CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    // MARK: - Rotation

    @objc func rotation() -> Double { CGDisplayRotation(displayID) }

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
    /// Directions use raw NSScreen coordinates (y increases upward):
    /// - east  = larger x (right)
    /// - west  = smaller x (left)
    /// - north = larger y (up on physical display)
    /// - south = smaller y (down on physical display)
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
        var config: CGDisplayConfigRef?
        guard unsafe CGBeginDisplayConfiguration(&config) == .success else { return false }
        unsafe CGConfigureDisplayOrigin(config, displayID, Int32(x), Int32(y))

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
        let origin = screen.frame.origin
        return HSRect(x: hsRect.x - Double(origin.x),
                      y: hsRect.y - Double(origin.y),
                      w: hsRect.w, h: hsRect.h)
    }

    @objc func localToAbsolute(_ rect: JSValue) -> HSRect? {
        guard let hsRect = rect.toObjectOf(HSRect.self) as? HSRect else { return nil }
        let origin = screen.frame.origin
        return HSRect(x: hsRect.x + Double(origin.x),
                      y: hsRect.y + Double(origin.y),
                      w: hsRect.w, h: hsRect.h)
    }

    // MARK: - Desktop

    @objc func desktopImage() -> String? {
        NSWorkspace.shared.desktopImageURL(for: screen)?.absoluteString
    }

    @objc func setDesktopImage(_ path: String) -> Bool {
        let url = path.hasPrefix("file://") ? URL(string: path)! : URL(fileURLWithPath: path)
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            return true
        } catch {
            AKError("hs.screen.setDesktopImage: \(error.localizedDescription)")
            return false
        }
    }
}
