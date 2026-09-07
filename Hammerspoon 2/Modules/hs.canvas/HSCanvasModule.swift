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
/// ## Coordinate systems -- read this before positioning elements
///
/// A canvas's **window position** (`create({x, y, w, h})`, and any later `x`/`y` you
/// compare it against, e.g. from `hs.screen`) uses unflipped AppKit screen coordinates:
/// `y = 0` is the *bottom* of the screen, and `y` increases upward. This matches
/// `hs.ui.window`.
///
/// But **element content** positioned *inside* a canvas -- every `frame`, `center`, and
/// `coordinates` value you pass to `appendElements()` and friends -- is drawn top-down:
/// `y = 0` is the *top* of the canvas, and `y` increases downward. These two coordinate
/// senses are independent of each other and easy to conflate, especially when a script
/// computes an element's position from the same screen geometry it used for the
/// window's own placement. If a shape appears vertically mirrored from where you
/// expect, this mismatch is the first thing to check.
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
    /// - Parameter rect: {object} A `{x, y, w, h}` dictionary describing the canvas window's frame
    /// - Returns: A new HSCanvas, not yet shown
    /// - Example:
    /// ```js
    /// const c = hs.canvas.create({x: 100, y: 100, w: 200, h: 200})
    /// ```
    @objc func create(_ rect: [String: Any]) -> HSCanvas
}

@_documentation(visibility: private)
@MainActor
@objc class HSCanvasModule: NSObject, HSModuleAPI, HSCanvasModuleAPI {
    var moduleName = "hs.canvas"
    let engineID: UUID

    // Keep strong references to shown canvases so they aren't deallocated while on screen,
    // mirroring HSUIModule's activeWindows tracking.
    private var activeCanvases: [UUID: HSCanvas] = [:]

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

    static let windowBehaviorValues: [String: Int] = [
        "default": 0,
        "canJoinAllSpaces": Int(NSWindow.CollectionBehavior.canJoinAllSpaces.rawValue),
        "moveToActiveSpace": Int(NSWindow.CollectionBehavior.moveToActiveSpace.rawValue),
        "managed": Int(NSWindow.CollectionBehavior.managed.rawValue),
        "transient": Int(NSWindow.CollectionBehavior.transient.rawValue),
        "stationary": Int(NSWindow.CollectionBehavior.stationary.rawValue),
        "participatesInCycle": Int(NSWindow.CollectionBehavior.participatesInCycle.rawValue),
        "ignoresCycle": Int(NSWindow.CollectionBehavior.ignoresCycle.rawValue),
        "fullScreenPrimary": Int(NSWindow.CollectionBehavior.fullScreenPrimary.rawValue),
        "fullScreenAuxiliary": Int(NSWindow.CollectionBehavior.fullScreenAuxiliary.rawValue),
        "fullScreenNone": Int(NSWindow.CollectionBehavior.fullScreenNone.rawValue),
        "fullScreenAllowsTiling": Int(NSWindow.CollectionBehavior.fullScreenAllowsTiling.rawValue),
        "fullScreenDisallowsTiling": Int(NSWindow.CollectionBehavior.fullScreenDisallowsTiling.rawValue),
    ]

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
        // Snapshot into an Array first -- canvas.destroy() synchronously calls back into
        // unregister(canvas:), which mutates activeCanvases. Iterating the dictionary's
        // .values directly while that happens traps ("Dictionary was mutated while being
        // enumerated").
        for canvas in Array(activeCanvases.values) {
            canvas.destroy()
        }
        activeCanvases.removeAll()
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        "<\(moduleName): \(activeCanvases.count) canvas(es)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc var windowLevels: [String: Int] { HSCanvasModule.windowLevelValues }
    @objc var windowBehaviors: [String: Int] { HSCanvasModule.windowBehaviorValues }
    @objc var compositeTypes: [String: String] { HSCanvasModule.compositeTypeValues }

    @objc func create(_ rect: [String: Any]) -> HSCanvas {
        HSCanvas(dict: rect, module: self)
    }

    // MARK: - Object registration (called by HSCanvas when shown/destroyed)

    func register(_ canvas: HSCanvas, id: UUID) {
        activeCanvases[id] = canvas
    }

    func unregister(canvas id: UUID) {
        activeCanvases.removeValue(forKey: id)
    }
}
