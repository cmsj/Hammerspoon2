//
//  HSCanvasModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit

/// # hs.canvas
///
/// **A low-level, absolutely-positioned drawing surface**
///
/// `hs.canvas` mirrors v1 Hammerspoon's `hs.canvas` module: elements are plain JS
/// objects (mirroring v1's Lua tables) describing shapes (`rectangle`, `circle`,
/// `oval`, `text`) with a `fill`/`stroke`/`strokeAndFill`/`clip`/`build`/`skip` action
/// pipeline. This is a different tool from `hs.ui`, which is a SwiftUI stack/layout
/// builder for app-like interfaces -- reach for `hs.canvas` when you need absolute
/// positioning, clipped/composited shapes, or direct window-level/Spaces control.
///
/// ## Coordinates
///
/// A canvas's **window position** (`create({x, y, w, h})`, `frame()`, `setFrame()`,
/// `topLeft()`) uses the same screen coordinates as `hs.screen`, `hs.window` and
/// `hs.ui.window`: `y = 0` is the *top* of the primary screen, and `y` increases downward.
/// You can pass a window's or screen's `frame` straight to `create()` or `setFrame()`.
///
/// **Element content** positioned *inside* a canvas -- every `frame`, `center`, and
/// `coordinates` value you pass to `appendElements()` and friends -- is relative to the
/// canvas: `{x: 0, y: 0}` is the canvas's top-left corner, and `y` increases downward.
///
/// ## Example: a rounded screen corner overlay
/// ```javascript
/// const radius = 12
/// const corner = hs.canvas.create({x: 0, y: 0, w: radius, h: radius})
/// corner.appendElements([
///     { action: "build", type: "rectangle" },
///     { action: "clip", type: "circle", center: {x: radius, y: radius}, radius: radius, reversePath: true },
///     { action: "fill", type: "rectangle", fillColor: { alpha: 1 } },
///     { type: "resetClip" }
/// ])
/// corner.levelValue(hs.canvas.windowLevels.screenSaver + 1)
/// corner.behavior("canJoinAllSpaces")
/// corner.show()
/// ```
@objc protocol HSCanvasModuleAPI: JSExport {
    /// Named window levels, exposed as raw numeric values (not opaque strings) so
    /// scripts can do arithmetic on them, matching v1 behavior.
    /// - Example:
    /// ```js
    /// canvas.levelValue(hs.canvas.windowLevels.screenSaver + 1)
    /// ```
    @objc var windowLevels: [String: Int] { get }

    /// Named window Spaces/Exposé collection behaviors, exposed as raw numeric bit values.
    /// - Example:
    /// ```js
    /// canvas.behavior("canJoinAllSpaces")
    /// ```
    @objc var windowBehaviors: [String: Int] { get }

    /// Named compositing/blend rules usable as an element's `compositeRule` attribute.
    /// - Example:
    /// ```js
    /// c.appendElements([{ type: "circle", action: "fill", compositeRule: hs.canvas.compositeTypes.multiply }])
    /// ```
    @objc var compositeTypes: [String: String] { get }

    /// Create a new canvas
    ///
    /// Named `create()` rather than v1's `new()` -- `new` cannot be used as a
    /// JavaScriptCore-exported method name (it collides with the JS `new` operator
    /// keyword at the bridging layer), and this codebase's conventions additionally
    /// forbid method names starting with `new`/`alloc`/`copy` (an ARC/ObjC hazard).
    /// - Parameter rect: {HSRect | object} The canvas window's frame: an HSRect (e.g. a window's or screen's `frame`) or a `{x, y, w, h}` dictionary, with `y = 0` at the top of the primary screen
    /// - Returns: A new HSCanvas, not yet shown
    /// - Example:
    /// ```js
    /// const c = hs.canvas.create({x: 100, y: 100, w: 200, h: 200})
    /// const overlay = hs.canvas.create(hs.window.focusedWindow().frame)
    /// ```
    @objc func create(_ rect: JSValue) -> HSCanvas
}

@_documentation(visibility: private)
@MainActor
@objc class HSCanvasModule: NSObject, HSModuleAPI, HSCanvasModuleAPI {
    var moduleName = "hs.canvas"
    let engineID: UUID

    // Keep strong references to shown canvases so they aren't deallocated while on screen,
    // mirroring HSUIModule's activeWindows tracking.
    // Shown canvases are kept alive by the tracker while active; hidden ones are ordinary
    // garbage once JS drops them. Internal so each HSCanvas can register itself.
    let canvases = HSObjectTracker<HSCanvas>()

    static let windowLevelValues: [String: Int] = [
        "desktop": Int(CGWindowLevelForKey(.desktopWindow)),
        "desktopIcon": Int(CGWindowLevelForKey(.desktopIconWindow)),
        "normal": Int(CGWindowLevelForKey(.normalWindow)),
        "floating": Int(CGWindowLevelForKey(.floatingWindow)),
        "tornOffMenu": Int(CGWindowLevelForKey(.tornOffMenuWindow)),
        "modalPanel": Int(CGWindowLevelForKey(.modalPanelWindow)),
        "utility": Int(CGWindowLevelForKey(.utilityWindow)),
        "dock": Int(CGWindowLevelForKey(.dockWindow)),
        "mainMenu": Int(CGWindowLevelForKey(.mainMenuWindow)),
        "status": Int(CGWindowLevelForKey(.statusWindow)),
        "popUpMenu": Int(CGWindowLevelForKey(.popUpMenuWindow)),
        "overlay": Int(CGWindowLevelForKey(.overlayWindow)),
        "help": Int(CGWindowLevelForKey(.helpWindow)),
        "dragging": Int(CGWindowLevelForKey(.draggingWindow)),
        "screenSaver": Int(CGWindowLevelForKey(.screenSaverWindow)),
        "assistiveTechHigh": Int(CGWindowLevelForKey(.assistiveTechHighWindow)),
        "cursor": Int(CGWindowLevelForKey(.cursorWindow)),
    ]

    static let windowBehaviorValues: [String: Int] =
        WindowCollectionBehavior.named.mapValues { Int($0.rawValue) }

    // Identity mapping of valid element `compositeRule` names -- gives JS callers
    // autocomplete/discoverability instead of hardcoded strings, mirroring the
    // windowLevels/windowBehaviors pattern. Kept in sync with
    // CanvasElementDrawing.blendModeValues.
    static let compositeTypeValues: [String: String] = Dictionary(
        uniqueKeysWithValues: CanvasElementDrawing.blendModeValues.keys.map { ($0, $0) }
    )

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        canvases.shutdown()
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        "<\(moduleName): \(canvases.activeCount) canvas(es)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc var windowLevels: [String: Int] { HSCanvasModule.windowLevelValues }
    @objc var windowBehaviors: [String: Int] { HSCanvasModule.windowBehaviorValues }
    @objc var compositeTypes: [String: String] { HSCanvasModule.compositeTypeValues }

    @objc func create(_ rect: JSValue) -> HSCanvas {
        HSCanvas(rect: rect, module: self)
    }
}
