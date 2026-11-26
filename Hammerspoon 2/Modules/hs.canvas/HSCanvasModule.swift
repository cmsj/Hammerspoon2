//
//  HSCanvasModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
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

    /// Animate changes to one or more canvases
    ///
    /// Calls `changes` straight away, and animates every change it makes to a canvas from
    /// its current value to the new one, over `options.duration` seconds. The changes can be
    /// to any number of elements, on any number of canvases, and all animate together.
    ///
    /// Inside `changes`, these animate:
    /// - element attributes set with `setElementAttribute()`, `assignElement()` (each attribute
    ///   that differs), `rotateElement()`, `rotateElementAroundPoint()` and
    ///   `setElementTransformation()`: `frame`, `center`, `radius`, `coordinates` (with the same
    ///   number of points), `rotation`, `rotationPoint`, `transformation`, `strokeWidth`,
    ///   `startAngle`, `endAngle`, `roundedRectRadii`, `textSize`, `imageAlpha`, `canvasAlpha`,
    ///   `fillColor`, `strokeColor`, `textColor`, `fillGradientColors` (with the same number of
    ///   colors), `fillGradientAngle` and `fillGradientCenter`
    /// - `setTransformation()` and `clearTransformation()`
    /// - the window, with `setFrame()`, `setTopLeft()`, `setSize()` and `setAlpha()`, while the
    ///   canvas is showing
    ///
    /// Everything else (e.g. `text`, `type`, `action`, or adding and removing elements) changes
    /// immediately, as it does outside `animate()`. A number and a percentage animate between
    /// each other (e.g. a `frame` width of `"100%"` to `50`).
    ///
    /// Getters return the new values as soon as `changes` returns, not the values being drawn
    /// part way through the animation. Mouse tracking follows what's drawn.
    ///
    /// Changing an attribute that's already animating (inside or outside another `animate()`)
    /// replaces that animation, starting from where it had got to on screen. Calls can be
    /// nested: changes inside a nested call use its options.
    ///
    /// If `changes` throws, the error propagates to the caller, and the changes made before
    /// the error still animate.
    /// - Parameter options: {object} `{duration, curve}`. `duration` is in seconds (default 0.25; 0 makes the changes without animating them). `curve` is `"linear"`, `"easeIn"`, `"easeOut"`, `"easeInOut"` (the default), or a cubic bezier `[x1, y1, x2, y2]` like CSS's `cubic-bezier()`, with `x1` and `x2` between 0 and 1
    /// - Parameter changes: {() => void} A function that changes canvases
    /// - Returns: {Promise<boolean>} A Promise that resolves once the animation has finished: `true` if every change ran to completion, or `false` if any was interrupted (by another change to the same attribute, its element or attribute being removed, or its canvas being destroyed)
    /// - Throws: true
    /// - Example:
    /// ```js
    /// const c = hs.canvas.create({x: 100, y: 100, w: 400, h: 300}).show()
    /// c.appendElements([{type: "rectangle", frame: {x: 10, y: 10, w: 50, h: 50}, fillColor: "#3366FF"}])
    ///
    /// // Move, resize, recolour and rotate the rectangle, and move the canvas, all at once
    /// hs.canvas.animate({duration: 0.6, curve: "easeInOut"}, () => {
    ///     c.setElementAttribute(0, "frame", {x: 300, y: 200, w: 80, h: 80})
    ///     c.setElementAttribute(0, "fillColor", {red: 1, green: 0.3, blue: 0})
    ///     c.rotateElement(0, 45)
    ///     c.setTopLeft({x: 200, y: 150})
    /// }).then(finished => console.log("Finished: " + finished))
    /// ```
    @objc func animate(_ options: [String: Any], _ changes: JSFunction) -> JSPromise?
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

    /// The animation whose `animate()` closure is running, which canvas setters animate with
    private(set) var currentAnimation: CanvasAnimationGroup?

    /// Animations that haven't finished yet, held until they do so they can resolve their
    /// promises, and so shutdown() can abandon them
    private var runningAnimations: [ObjectIdentifier: CanvasAnimationGroup] = [:]

    func shutdown() {
        currentAnimation = nil
        canvases.shutdown()
        runningAnimations.values.forEach { $0.cancel() }
        runningAnimations = [:]
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

    // MARK: - Animation

    @objc func animate(_ options: [String: Any], _ changes: JSFunction) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        func fail(_ message: String) -> JSPromise? {
            context.exception = JSValue(newErrorFromMessage: "hs.canvas.animate(): \(message)", in: context)
            return nil
        }
        guard changes.isFunction else { return fail("needs a function to make the changes") }

        var duration = 0.25
        if let raw = options["duration"] {
            guard let seconds = CanvasAnimatable.plainNumber(raw), seconds.isFinite, seconds >= 0 else {
                return fail("duration must be a number of seconds, not \(raw)")
            }
            duration = seconds
        }
        let curve: CanvasAnimationCurve
        switch CanvasAnimationCurve.parse(options["curve"]) {
        case .success(let parsed): curve = parsed
        case .failure(let error): return fail(error.message)
        }
        let unknown = Set(options.keys).subtracting(["duration", "curve"])
        if !unknown.isEmpty {
            AKWarning("hs.canvas.animate(): ignoring unknown options \(unknown.sorted().joined(separator: ", ")) (supported: duration, curve)")
        }

        let group = CanvasAnimationGroup(duration: duration, curve: curve)
        let previous = currentAnimation
        // A zero duration makes the changes immediately, even inside an outer animate()
        currentAnimation = duration > 0 ? group : nil
        _ = context.callCapturingException { changes.call(withArguments: []) }
        currentAnimation = previous

        let onFinish: (CanvasAnimationGroup) -> Void = { [weak self] finished in
            self?.runningAnimations[ObjectIdentifier(finished)] = nil
        }
        runningAnimations[ObjectIdentifier(group)] = group
        if context.exception != nil {
            // The error propagates to the caller; the changes made before it still animate
            group.start(holder: nil, onFinish: onFinish)
            return nil
        }
        return wrapAsyncInJSPromise(in: context) { holder in
            group.start(holder: holder, onFinish: onFinish)
        }
    }
}
