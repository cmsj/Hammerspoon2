//
//  HSCanvas.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit
import SwiftUI

/// # HSCanvas
///
/// A single canvas window: an absolutely-positioned, low-level drawing surface
/// mirroring v1 Hammerspoon's `hs.canvas`. Elements are plain JS objects (matching
/// v1's Lua tables) added with `appendElements()` and mutated in place with
/// `setElementAttribute()`/`elementAttribute()`. Supports the same `fill`/`stroke`/
/// `strokeAndFill`/`clip`/`build`/`skip` action pipeline as v1, including the
/// `build`+`clip`+`reversePath` technique used to punch holes in shapes (see
/// `hs.canvas.windowLevels`/`hs.canvas.windowBehaviors` for the window-level/Spaces
/// controls needed alongside this for overlay-style canvases).
///
/// ## Example
/// ```javascript
/// const c = hs.canvas.create({x: 100, y: 100, w: 200, h: 200})
/// c.appendElements([
///     { type: "rectangle", action: "fill", fillColor: { red: 0.2, green: 0.5, blue: 0.9, alpha: 1 } }
/// ])
/// c.show()
/// ```
@objc protocol HSCanvasAPI: HSTypeAPI, JSExport {
    // MARK: Window lifecycle

    /// Show the canvas window, optionally fading it in
    ///
    /// A fade goes from fully transparent up to the canvas's `alpha()`. Calling `show()`,
    /// `hide()` or `destroy()` while a fade is running replaces that fade, so showing a
    /// canvas that is fading out of `hide()` brings it back. A canvas that has been
    /// destroyed can't be shown again, even while it is still fading out.
    /// - Note: A shown canvas stays on screen, with its callbacks, until it's hidden or destroyed, even if you don't keep a reference to it
    /// - Parameter fadeInTime?: The number of seconds to fade the canvas in over. Defaults to `0`, which shows it immediately
    /// - Returns: Self for chaining
    /// - Throws: true
    /// - Example:
    /// ```js
    /// c.show(0.3)
    /// ```
    @objc(show:) func show(_ fadeInTime: Double) -> HSCanvas

    /// Hide the canvas window, optionally fading it out (elements and window config are preserved while you keep a reference to it)
    ///
    /// The canvas keeps its callbacks, and `isShowing()` stays `true`, until a fade-out
    /// has finished. Afterwards its `alpha()` is unchanged, so the next `show()` brings it
    /// back at the same opacity. Hiding a canvas that has been destroyed does nothing.
    /// - Parameter fadeOutTime?: The number of seconds to fade the canvas out over. Defaults to `0`, which hides it immediately
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// c.hide(0.3)
    /// ```
    @objc(hide:) func hide(_ fadeOutTime: Double) -> HSCanvas

    /// Destroy the canvas window and release its resources, optionally fading it out first
    ///
    /// This releases the canvas's window, callbacks and elements (including any images
    /// they hold) straight away, rather than when the canvas is garbage collected. A
    /// destroyed canvas is finished with: from the moment `destroy()` is called, calling
    /// `show()`, `appendElements()`, `insertElement()`, `assignElement()`,
    /// `replaceElements()`, `mouseCallback()`, `draggingCallback()` or `duplicate()` on it
    /// throws an error, and `imageFromCanvas()` returns `null`.
    ///
    /// Named `destroy()` rather than v1's `delete()` -- `delete` cannot be used as a
    /// JavaScriptCore-exported method name in this codebase's bridging layer.
    /// - Parameter fadeOutTime?: The number of seconds to fade the canvas out over before destroying it. Defaults to `0`, which destroys it immediately
    /// - Example:
    /// ```js
    /// c.destroy(0.3)
    /// ```
    @objc(destroy:) func destroy(_ fadeOutTime: Double)

    /// The opacity of the canvas window
    /// - Returns: The opacity, from `0` (fully transparent) to `1` (fully opaque)
    @objc func alpha() -> Double

    /// Set the opacity of the whole canvas window
    ///
    /// This is the opacity `show()` fades in to, and that a hidden canvas comes back at.
    /// - Parameter alpha: The opacity, from `0` (fully transparent) to `1` (fully opaque). Values outside that range are clamped
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// c.setAlpha(0.5)
    /// ```
    @objc func setAlpha(_ alpha: Double) -> HSCanvas

    /// Whether the canvas window is currently ordered onto the screen
    /// - Returns: `true` if the canvas has been shown and not hidden or destroyed
    @objc func isShowing() -> Bool

    /// Whether the canvas is showing AND at least partially visible (not fully occluded or off-screen)
    /// - Returns: `true` if the canvas is showing and at least partially on-screen
    @objc func isVisible() -> Bool

    /// Whether the canvas is hidden behind other windows, or off-screen entirely
    /// - Returns: `true` if the canvas is showing but fully occluded or off-screen
    @objc func isOccluded() -> Bool

    // MARK: Window position and size

    /// The canvas window's current position and size
    /// - Returns: {object} A `{x, y, w, h}` dictionary, in the same unflipped AppKit screen coordinates as `create()`
    @objc func frame() -> [String: Any]

    /// Move and/or resize the canvas window
    /// - Parameter rect: {object} A `{x, y, w, h}` dictionary. Any keys left out keep their current value
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// c.setFrame({x: 200, y: 200, w: 300, h: 300})
    /// ```
    @objc func setFrame(_ rect: [String: Any]) -> HSCanvas

    /// The canvas window's current top-left corner
    ///
    /// "Top-left" here means the same unflipped AppKit sense `create()`/`frame()` use:
    /// the point at the window's highest `y` (its screen-visual top), not `y = 0`.
    /// - Returns: {object} An `{x, y}` dictionary
    @objc func topLeft() -> [String: Any]

    /// Move the canvas window without changing its size
    /// - Parameter point: {object} An `{x, y}` dictionary giving the new top-left corner. Any keys left out keep their current value
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// c.setTopLeft({x: 200, y: 800})
    /// ```
    @objc func setTopLeft(_ point: [String: Any]) -> HSCanvas

    /// The canvas window's current size
    /// - Returns: {object} A `{w, h}` dictionary
    @objc func size() -> [String: Any]

    /// Resize the canvas window without moving its top-left corner
    /// - Parameter dimensions: {object} A `{w, h}` dictionary. Any keys left out keep their current value
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// c.setSize({w: 400, h: 300})
    /// ```
    @objc func setSize(_ dimensions: [String: Any]) -> HSCanvas

    // MARK: Window styling

    /// Set the window level by name
    /// - Parameter name: A level name from `hs.canvas.windowLevels` (e.g. `"floating"`, `"screenSaver"`)
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// c.level("floating")
    /// ```
    @objc func level(_ name: String) -> HSCanvas

    /// Set the window level to a raw numeric value
    ///
    /// Split out from `level(_:)` (rather than accepting a string-or-number union)
    /// because JSExport parameters must have a single concrete type -- see
    /// `hs.canvas.windowLevels`, which exposes raw numeric values (not opaque name
    /// strings) so scripts can do arithmetic on them, matching v1 behavior.
    /// - Parameter value: A raw numeric window level
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// c.levelValue(hs.canvas.windowLevels.screenSaver + 1)
    /// ```
    @objc func levelValue(_ value: Int) -> HSCanvas

    /// Set the window's Spaces/Exposé collection behavior to a single named behavior
    /// - Parameter name: A behavior name from `hs.canvas.windowBehaviors` (e.g. `"canJoinAllSpaces"`)
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// c.behavior("canJoinAllSpaces")
    /// ```
    @objc func behavior(_ name: String) -> HSCanvas

    /// Set the window's Spaces/Exposé collection behavior to a combination of named behaviors
    ///
    /// Throws if the behavior combines flags AppKit treats as mutually exclusive (e.g.
    /// `canJoinAllSpaces` with `moveToActiveSpace`), leaving the current behavior unchanged.
    /// Unknown names are logged and ignored.
    /// - Parameter names: {string[]} Behavior names from `hs.canvas.windowBehaviors`, combined together
    /// - Returns: Self for chaining
    /// - Throws: true
    /// - Example:
    /// ```js
    /// c.behaviorList(["canJoinAllSpaces", "stationary"])
    /// ```
    @objc func behaviorList(_ names: [String]) -> HSCanvas

    /// Set the window's Spaces/Exposé collection behavior to a raw bitmask
    ///
    /// Throws if the behavior combines flags AppKit treats as mutually exclusive (e.g.
    /// `canJoinAllSpaces` with `moveToActiveSpace`), leaving the current behavior unchanged.
    /// - Parameter value: A raw `NSWindow.CollectionBehavior` bitmask
    /// - Returns: Self for chaining
    /// - Throws: true
    /// - Example:
    /// ```js
    /// c.behaviorValue(hs.canvas.windowBehaviors.canJoinAllSpaces | hs.canvas.windowBehaviors.stationary)
    /// ```
    @objc func behaviorValue(_ value: Int) -> HSCanvas

    /// Set whether clicking the canvas activates the Hammerspoon app
    /// - Parameter flag: Pass `false` to prevent clicks on the canvas from bringing the app forward
    /// - Returns: Self for chaining
    @objc func clickActivating(_ flag: Bool) -> HSCanvas

    /// Set whether the canvas window ignores all mouse events, passing clicks through to whatever is behind it
    ///
    /// This is a capability beyond v1's `hs.canvas` API surface (not a literal v1 method
    /// name) -- v1 has no direct equivalent for full click pass-through.
    /// - Parameter flag: Pass `true` to make the canvas fully click-through
    /// - Returns: Self for chaining
    @objc func ignoreMouseEvents(_ flag: Bool) -> HSCanvas

    // MARK: Element management

    /// Append one or more elements to the end of the canvas
    ///
    /// Element `frame`/`center`/`coordinates` values are y-down (`y = 0` at the top of
    /// the canvas) -- a different sense from the canvas *window's* own `x`/`y` position,
    /// which is unflipped AppKit screen coordinates. See `hs.canvas`'s module-level docs
    /// for the full explanation.
    /// - Parameter elements: {object[]} Array of element dictionaries (each needs at least a `type`)
    /// - Returns: Self for chaining
    /// - Throws: true
    /// - Example:
    /// ```js
    /// c.appendElements([{ type: "circle", action: "fill", fillColor: { alpha: 1 } }])
    /// ```
    @objc func appendElements(_ elements: [[String: Any]]) -> HSCanvas

    /// Insert an element at a specific index
    /// - Parameters:
    ///   - element: The element dictionary to insert
    ///   - index: The index to insert at (clamped to the valid range)
    /// - Returns: Self for chaining
    /// - Throws: true
    @objc func insertElement(_ element: [String: Any], _ index: Int) -> HSCanvas

    /// Replace the element at an index, or append if the index equals the current element count
    /// - Parameters:
    ///   - element: The replacement element dictionary
    ///   - index: The index to replace
    /// - Returns: Self for chaining
    /// - Throws: true
    @objc func assignElement(_ element: [String: Any], _ index: Int) -> HSCanvas

    /// Remove the element at a specific index
    /// - Parameter index: The index to remove
    /// - Returns: Self for chaining
    @objc func removeElement(_ index: Int) -> HSCanvas

    /// Remove the last element
    /// - Returns: Self for chaining
    @objc func removeLastElement() -> HSCanvas

    /// Replace all elements on the canvas
    /// - Parameter elements: {object[]} The new full element list
    /// - Returns: Self for chaining
    /// - Throws: true
    @objc func replaceElements(_ elements: [[String: Any]]) -> HSCanvas

    /// The number of elements on the canvas
    /// - Returns: The current element count
    @objc func elementCount() -> Int

    /// All elements currently on the canvas
    /// - Returns: {object[]} Array of element dictionaries
    @objc func canvasElements() -> [[String: Any]]

    /// The attribute keys present on an element
    /// - Parameter index: The element index
    /// - Returns: {string[]} Array of attribute key names
    @objc func elementKeys(_ index: Int) -> [String]

    /// Get a single attribute value from an element
    ///
    /// Returns `Any?` (mirroring `hs.userdefaults.get()`) rather than a concrete Swift
    /// type because an element attribute's value is genuinely heterogeneous -- a
    /// string, number, boolean, nested object, or array, matching v1's dynamically-typed
    /// Lua table values.
    /// - Parameters:
    ///   - index: The element index
    ///   - key: The attribute key
    /// - Returns: The attribute's current value, or `null` if not set
    @objc func elementAttribute(_ index: Int, _ key: String) -> Any?

    /// Set a single attribute value on an element
    /// - Parameters:
    ///   - index: The element index
    ///   - key: The attribute key
    ///   - value: The value to assign
    /// - Returns: Self for chaining
    @objc func setElementAttribute(_ index: Int, _ key: String, _ value: Any) -> HSCanvas

    /// Remove a single attribute from an element
    /// - Parameters:
    ///   - index: The element index
    ///   - key: The attribute key to remove
    /// - Returns: Self for chaining
    @objc func removeElementAttribute(_ index: Int, _ key: String) -> HSCanvas

    /// The smallest rectangle enclosing an element's rendered shape
    /// - Parameter index: The element index
    /// - Returns: {object} A `{x, y, w, h}` dictionary
    @objc func elementBounds(_ index: Int) -> [String: Any]

    /// The smallest size that can fully render a string of text, using the font attributes
    /// (`textFont`/`textSize`/`textWeight`/`textDesign`/`textItalic`) of an element, of an
    /// attributes object, or the defaults
    ///
    /// Mirrors v1's `hs.canvas:minimumTextSize([index], text)`. It can be called three ways:
    /// - `minimumTextSize(index, text)` measures with the font attributes of the element at
    ///   `index`. Any element type works; attributes it doesn't set use their defaults.
    /// - `minimumTextSize(attributes, text)` measures with the font attributes in a plain
    ///   object, so text can be measured before any element exists.
    /// - `minimumTextSize(text)` measures with the default font attributes (the system font
    ///   at size 27, as a text element with no font attributes would be drawn).
    ///
    /// Multi-line strings (separated by `\n`) are measured correctly -- the height covers every
    /// line and the width is the longest line's width, not a fixed single-line size.
    /// - Parameters:
    ///   - source: {number | {textFont?: string, textSize?: number, textWeight?: string, textDesign?: string, textItalic?: boolean} | string} The index of an element whose font attributes to measure with, an object of font attributes, or the string to measure (to use the default font attributes)
    ///   - text?: {string} The string to measure -- it doesn't need to match the element's own `text`. Omitted when `source` is the string
    /// - Returns: {object} A `{w, h}` dictionary, or `{}` (with a warning logged) if `index` is out of bounds or the arguments are invalid
    /// - Example:
    /// ```js
    /// // Size a text element to fit its text, before it's added to the canvas
    /// const attributes = { textFont: "Menlo-Bold", textSize: 24 }
    /// const size = c.minimumTextSize(attributes, "Hello\nWorld")
    /// c.appendElements([{ type: "text", text: "Hello\nWorld", ...attributes,
    ///                     frame: { x: 10, y: 10, w: size.w, h: size.h } }])
    ///
    /// // Or measure with an existing element's font, or the default font
    /// const fromElement = c.minimumTextSize(0, "Goodbye")
    /// const withDefaults = c.minimumTextSize("Goodbye")
    /// ```
    @objc func minimumTextSize(_ source: JSValue, _ text: JSValue) -> [String: Any]

    // MARK: Mouse interaction

    /// Set the callback fired for tracked mouse events
    ///
    /// Fires for elements with `trackMouseDown`/`trackMouseUp`/`trackMouseEnterExit`/
    /// `trackMouseMove`/`trackRightMouseDown`/`trackRightMouseUp` set to `true` in their
    /// element dictionary, and for whole-canvas regions enabled via `canvasMouseEvents()`
    /// (delivered with id `"_canvas"`). `mouseDown`/`mouseUp` are the left button only;
    /// the right button (or a Ctrl-click, the standard macOS secondary click) is reported
    /// separately as `rightMouseDown`/`rightMouseUp`.
    /// - Parameter callback: {(canvas: HSCanvas, message: string, id: any, x: number, y: number) => void} A JavaScript function called with the canvas, the event name (`"mouseDown"`/`"mouseUp"`/`"rightMouseDown"`/`"rightMouseUp"`/`"mouseEnter"`/`"mouseExit"`/`"mouseMove"`), the tracked element's id, and the event's x/y coordinates
    /// - Returns: Self for chaining
    /// - Throws: true
    /// - Example:
    /// ```js
    /// c.appendElements([{ type: "circle", action: "fill", trackMouseDown: true, id: "dot" }])
    /// c.mouseCallback((canvas, message, id, x, y) => console.log(message, id, x, y))
    ///
    /// // Offer a secondary action on right-click
    /// c.appendElements([{ type: "rectangle", action: "fill", id: "button",
    ///                     trackMouseUp: true, trackRightMouseDown: true }])
    /// c.mouseCallback((canvas, message, id) => {
    ///     if (message === "rightMouseDown") console.log("context menu for", id)
    /// })
    /// ```
    @objc func mouseCallback(_ callback: JSFunction) -> HSCanvas

    /// Enable whole-canvas mouse tracking for regions not covered by any individually
    /// tracked element. Delivered through `mouseCallback()` with id `"_canvas"`.
    /// - Parameters:
    ///   - down: Track mouse-down events
    ///   - up: Track mouse-up events
    ///   - enterExit: Track mouse enter/exit events
    ///   - move: Track mouse-move events
    ///   - rightDown?: Track right mouse-down events (defaults to `false`). Every call sets
    ///     all six flags, so omitting this turns right mouse-down tracking off
    ///   - rightUp?: Track right mouse-up events (defaults to `false`). Every call sets all
    ///     six flags, so omitting this turns right mouse-up tracking off
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// // Left and right clicks anywhere on the canvas
    /// c.canvasMouseEvents(true, false, false, false, true, false)
    /// ```
    @objc func canvasMouseEvents(_ down: Bool, _ up: Bool, _ enterExit: Bool, _ move: Bool, _ rightDown: Bool, _ rightUp: Bool) -> HSCanvas

    // MARK: Element and canvas transforms

    /// Rotate an element about its own bounding-box center
    /// - Parameters:
    ///   - index: The element index
    ///   - angle: The rotation angle, in degrees
    /// - Returns: Self for chaining
    @objc func rotateElement(_ index: Int, _ angle: Double) -> HSCanvas

    /// Rotate an element about a specific point
    /// - Parameters:
    ///   - index: The element index
    ///   - angle: The rotation angle, in degrees
    ///   - point: {object} A `{x, y}` dictionary giving the pivot point
    /// - Returns: Self for chaining
    @objc func rotateElementAroundPoint(_ index: Int, _ angle: Double, _ point: [String: Any]) -> HSCanvas

    /// Apply a raw 2D affine transformation matrix to a single element
    /// - Parameters:
    ///   - index: The element index
    ///   - matrix: {object} A `{m11, m12, m21, m22, tX, tY}` matrix dictionary
    /// - Returns: Self for chaining
    @objc func setElementTransformation(_ index: Int, _ matrix: [String: Any]) -> HSCanvas

    /// Apply a raw 2D affine transformation matrix to the whole canvas
    /// - Parameter matrix: {object} A `{m11, m12, m21, m22, tX, tY}` matrix dictionary
    /// - Returns: Self for chaining
    @objc func setTransformation(_ matrix: [String: Any]) -> HSCanvas

    /// Remove the whole-canvas transformation set by `setTransformation()`
    /// - Returns: Self for chaining
    @objc func clearTransformation() -> HSCanvas

    // MARK: Export and duplication

    /// Render the canvas's current contents to an image
    /// - Returns: An HSImage snapshot of the canvas, or `null` if it could not be rendered or the canvas has been destroyed
    @objc func imageFromCanvas() -> HSImage?

    /// Create an independent copy of this canvas, with the same frame, elements, and
    /// window configuration
    ///
    /// Named `duplicate()` rather than v1's `copy()` -- this codebase's conventions
    /// forbid method names starting with `copy` (an ARC/ObjC hazard), the same rule
    /// that renamed `new()` to `create()`.
    /// - Returns: A new HSCanvas
    /// - Throws: true
    @objc func duplicate() -> HSCanvas

    // MARK: Accessibility

    /// Set the accessibility subrole reported for this canvas's window
    /// - Parameter subrole: The accessibility subrole string
    /// - Returns: Self for chaining
    @objc func setAccessibilitySubrole(_ subrole: String) -> HSCanvas

    // MARK: Drag and drop

    /// Set a callback fired when files or text are dropped onto the canvas
    /// - Parameter callback: {(paths: string[]) => void} Called with the dropped file paths, or a single-element array containing dropped text
    /// - Returns: Self for chaining
    /// - Throws: true
    @objc func draggingCallback(_ callback: JSFunction) -> HSCanvas
}

@_documentation(visibility: private)
@MainActor
@objc class HSCanvas: NSObject, HSCanvasAPI, HSTrackedObject {
    @objc var typeName = "HSCanvas"

    @objc func toString() -> String {
        return "<\(typeName): \(elementStore.elements.count) element(s)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc let identifier = UUID().uuidString

    private var canvasFrame: CGRect
    private var nsWindow: NSWindow?
    private weak var module: HSCanvasModule?

    // A shown canvas is active: it stays on screen, with its callbacks, until it's hidden or
    // destroyed, even if the user dropped their reference to it. A hidden canvas nobody
    // references can never be shown again, so it's ordinary garbage.
    private var isShown = false {
        didSet {
            module?.canvases.setActive(self, isShown)
        }
    }

    private let elementStore = CanvasElementStore()

    // The opacity set by setAlpha(). Kept apart from the window's alphaValue, which is
    // animated by fades and so can't be read back as the opacity to fade in to.
    private var targetAlpha: CGFloat = 1

    // Whether a hide()/destroy() fade is running, so setAlpha() doesn't interrupt it.
    private var isFadingOut = false

    // Set as soon as destroy() is called, before any fade-out, so the canvas can't be
    // shown or take on elements or callbacks again (see rejectIfDestroyed()), or be
    // hidden, which would cancel the fade and leave it undestroyed.
    private var isDestroyed = false

    // Bumped by every show()/hide()/destroy(), so a fade's completion handler can tell
    // that a later call has replaced it and must do nothing.
    private var fadeGeneration = 0

    /// The window's actual alphaValue, for tests -- not exposed to JS.
    var windowAlphaValue: CGFloat? { nsWindow?.alphaValue }

    /// The window's actual collectionBehavior, for tests -- not exposed to JS.
    var windowCollectionBehavior: NSWindow.CollectionBehavior? { nsWindow?.collectionBehavior }

    private var windowLevelRaw: Int?
    private var windowBehaviorRaw: NSWindow.CollectionBehavior = []
    private var isClickActivating = true
    private var ignoresMouseEventsFlag = false
    private var accessibilitySubroleValue: String?

    private var mouseCallbackRef: JSCallback?
    private var draggingCallbackRef: JSCallback?

    /// Internal accessor for `CanvasElementDrawing.drawNestedCanvas` -- not exposed to JS.
    var elementsForNestedRendering: [[String: Any]] { elementStore.elements }

    init(frame: CGRect, module: HSCanvasModule) {
        self.canvasFrame = frame
        self.module = module
        super.init()
        module.canvases.add(self)
    }

    convenience init(dict: [String: Any], module: HSCanvasModule) {
        let x = (dict["x"] as? NSNumber)?.doubleValue ?? 0
        let y = (dict["y"] as? NSNumber)?.doubleValue ?? 0
        let w = (dict["w"] as? NSNumber)?.doubleValue ?? 200
        let h = (dict["h"] as? NSNumber)?.doubleValue ?? 200
        self.init(frame: CGRect(x: x, y: y, width: w, height: h), module: module)
    }

    isolated deinit {
        AKGarbage("Deinit of \(typeName)(\(identifier))")

        mouseCallbackRef?.detach(from: self)
        draggingCallbackRef?.detach(from: self)

        guard let window = nsWindow else { return }
        DispatchQueue.main.async {
            window.contentView = nil
            window.close()
        }
    }

    // MARK: - Lifecycle

    @objc(show:) func show(_ fadeInTime: Double) -> HSCanvas {
        if rejectIfDestroyed("show") { return self }
        if nsWindow == nil {
            let content = HSCanvasRenderView(store: elementStore) { [weak self] message, id, x, y in
                guard let self else { return }
                _ = self.mouseCallbackRef?.call(withArguments: [self, message, id, x, y])
            }
            let hostingView = HSCanvasDragHostingView(rootView: content)
            hostingView.onDrop = { [weak self] paths in
                _ = self?.draggingCallbackRef?.call(withArguments: [paths])
            }
            if let subrole = accessibilitySubroleValue {
                hostingView.setAccessibilitySubrole(NSAccessibility.Subrole(rawValue: subrole))
            }

            var styleMask: NSWindow.StyleMask = [.borderless]
            if !isClickActivating {
                styleMask.insert(.nonactivatingPanel)
            }
            let window = HSCanvasWindow(
                contentRect: canvasFrame,
                styleMask: styleMask,
                backing: .buffered,
                defer: false,
                pressState: hostingView.pressState
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = ignoresMouseEventsFlag
            window.acceptsMouseMovedEvents = true
            window.level = resolvedLevel()
            window.collectionBehavior = windowBehaviorRaw
            window.contentView = hostingView

            self.nsWindow = window
            // Kept until the canvas is freed, including while hidden
            JSExtraMemory.reportBackingStore(of: window)
        }
        guard let window = nsWindow else { return self }

        fadeGeneration += 1
        isFadingOut = false
        let duration = Self.fadeDuration(fadeInTime)
        if duration > 0 && !window.isVisible {
            window.alphaValue = 0
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        isShown = true
        animateAlpha(to: targetAlpha, over: duration) {}
        return self
    }

    @objc(hide:) func hide(_ fadeOutTime: Double) -> HSCanvas {
        guard !isDestroyed else { return self }
        fadeOut(over: Self.fadeDuration(fadeOutTime)) { [weak self] in
            guard let self else { return }
            self.nsWindow?.orderOut(nil)
            self.nsWindow?.alphaValue = self.targetAlpha
            self.isShown = false
        }
        return self
    }

    @objc(destroy:) func destroy(_ fadeOutTime: Double) {
        isDestroyed = true
        fadeOut(over: Self.fadeDuration(fadeOutTime)) { [weak self] in
            self?.destroy()
        }
    }

    func destroy() {
        isDestroyed = true
        fadeGeneration += 1
        isFadingOut = false
        mouseCallbackRef?.detach(from: self)
        mouseCallbackRef = nil
        draggingCallbackRef?.detach(from: self)
        draggingCallbackRef = nil
        isShown = false

        // The elements can hold large native buffers (images) that JavaScriptCore doesn't
        // know about, so it may not collect this canvas for a long time. Release them now.
        elementStore.elements = []
        elementStore.canvasTransform = nil

        guard let window = nsWindow else { return }
        window.contentView = nil
        window.close()
        nsWindow = nil
    }

    /// Throws a JS error for a call to `method` if the canvas has been destroyed, so a
    /// destroyed canvas can't be shown or take on elements and callbacks again.
    /// - Returns: `true` if the canvas has been destroyed, and the caller must do nothing
    private func rejectIfDestroyed(_ method: String) -> Bool {
        guard isDestroyed else { return false }
        if let ctx = JSContext.current() {
            ctx.exception = JSValue(newErrorFromMessage: "hs.canvas: \(method)() can't be called on a canvas that has been destroyed", in: ctx)
        }
        return true
    }

    @objc func alpha() -> Double {
        Double(targetAlpha)
    }

    @objc func setAlpha(_ alpha: Double) -> HSCanvas {
        guard !alpha.isNaN else {
            AKWarning("hs.canvas: setAlpha() needs a number")
            return self
        }
        targetAlpha = CGFloat(min(max(alpha, 0), 1))
        // A fade-out keeps going, and its completion restores targetAlpha; anything else
        // (including a fade-in) jumps straight to the new opacity.
        if !isFadingOut {
            animateAlpha(to: targetAlpha, over: 0) {}
        }
        return self
    }

    // MARK: - Fading

    /// Fades the window out and then runs `completion`, unless a later show()/hide()/destroy()
    /// replaces the fade first. The canvas stays active (and so alive, with its callbacks)
    /// until `completion` makes it inactive, matching v1, which held a reference during fades.
    private func fadeOut(over duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        fadeGeneration += 1
        guard duration > 0, let window = nsWindow, window.isVisible else {
            isFadingOut = false
            // Settle any running fade-in, so the window is at targetAlpha the next time it's shown.
            animateAlpha(to: targetAlpha, over: 0) {}
            completion()
            return
        }
        let generation = fadeGeneration
        isFadingOut = true
        animateAlpha(to: 0, over: duration) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            self.isFadingOut = false
            completion()
        }
    }

    /// Animates the window's alphaValue, replacing any animation already running on it.
    private func animateAlpha(to alpha: CGFloat, over duration: TimeInterval,
                              completion: @escaping @MainActor () -> Void) {
        guard let window = nsWindow else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            window.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
        if duration <= 0 {
            window.alphaValue = alpha
        }
    }

    /// A fade time from JS: an omitted argument arrives as NaN, which means no fade.
    private static func fadeDuration(_ seconds: Double) -> TimeInterval {
        seconds.isFinite && seconds > 0 ? seconds : 0
    }

    @objc func isShowing() -> Bool {
        nsWindow?.isVisible ?? false
    }

    @objc func isVisible() -> Bool {
        guard let window = nsWindow, window.isVisible else { return false }
        return window.occlusionState.contains(.visible)
    }

    @objc func isOccluded() -> Bool {
        guard let window = nsWindow, window.isVisible else { return false }
        return !window.occlusionState.contains(.visible)
    }

    // MARK: - Window position and size

    @objc func frame() -> [String: Any] {
        let rect = nsWindow?.frame ?? canvasFrame
        return ["x": rect.origin.x, "y": rect.origin.y, "w": rect.size.width, "h": rect.size.height]
    }

    @objc func setFrame(_ rect: [String: Any]) -> HSCanvas {
        let x = (rect["x"] as? NSNumber)?.doubleValue ?? Double(canvasFrame.origin.x)
        let y = (rect["y"] as? NSNumber)?.doubleValue ?? Double(canvasFrame.origin.y)
        let w = (rect["w"] as? NSNumber)?.doubleValue ?? Double(canvasFrame.size.width)
        let h = (rect["h"] as? NSNumber)?.doubleValue ?? Double(canvasFrame.size.height)
        canvasFrame = CGRect(x: x, y: y, width: w, height: h)
        nsWindow?.setFrame(canvasFrame, display: true)
        return self
    }

    @objc func topLeft() -> [String: Any] {
        let rect = nsWindow?.frame ?? canvasFrame
        return ["x": rect.origin.x, "y": rect.origin.y + rect.size.height]
    }

    @objc func setTopLeft(_ point: [String: Any]) -> HSCanvas {
        let x = (point["x"] as? NSNumber)?.doubleValue ?? Double(canvasFrame.origin.x)
        let topY = (point["y"] as? NSNumber)?.doubleValue ?? Double(canvasFrame.origin.y + canvasFrame.size.height)
        canvasFrame = CGRect(
            origin: CGPoint(x: x, y: topY - canvasFrame.size.height),
            size: canvasFrame.size
        )
        nsWindow?.setFrame(canvasFrame, display: true)
        return self
    }

    @objc func size() -> [String: Any] {
        let rect = nsWindow?.frame ?? canvasFrame
        return ["w": rect.size.width, "h": rect.size.height]
    }

    @objc func setSize(_ dimensions: [String: Any]) -> HSCanvas {
        let w = (dimensions["w"] as? NSNumber)?.doubleValue ?? Double(canvasFrame.size.width)
        let h = (dimensions["h"] as? NSNumber)?.doubleValue ?? Double(canvasFrame.size.height)
        // canvasFrame.origin is the AppKit bottom-left, not the top-left this method
        // promises to preserve -- recompute the origin from the previous top edge so a
        // height change doesn't silently shift where the canvas visually sits.
        let topY = canvasFrame.origin.y + canvasFrame.size.height
        canvasFrame = CGRect(
            origin: CGPoint(x: canvasFrame.origin.x, y: topY - h),
            size: CGSize(width: w, height: h)
        )
        nsWindow?.setFrame(canvasFrame, display: true)
        return self
    }

    // MARK: - Window styling

    @objc func level(_ name: String) -> HSCanvas {
        if let raw = HSCanvasModule.windowLevelValues[name] {
            windowLevelRaw = raw
        } else {
            AKWarning("hs.canvas: Unknown window level name '\(name)'")
        }
        nsWindow?.level = resolvedLevel()
        return self
    }

    @objc func levelValue(_ value: Int) -> HSCanvas {
        windowLevelRaw = value
        nsWindow?.level = resolvedLevel()
        return self
    }

    @objc func behavior(_ name: String) -> HSCanvas {
        guard let value = WindowCollectionBehavior.named[name] else {
            AKWarning("hs.canvas: Unknown window behavior '\(name)'")
            return self
        }
        return setBehavior(value)
    }

    @objc func behaviorList(_ names: [String]) -> HSCanvas {
        setBehavior(WindowCollectionBehavior.combining(names, caller: "hs.canvas"))
    }

    @objc func behaviorValue(_ value: Int) -> HSCanvas {
        setBehavior(NSWindow.CollectionBehavior(rawValue: UInt(bitPattern: value)))
    }

    private func setBehavior(_ behavior: NSWindow.CollectionBehavior) -> HSCanvas {
        guard WindowCollectionBehavior.validate(behavior, caller: "hs.canvas") else { return self }
        windowBehaviorRaw = behavior
        nsWindow?.collectionBehavior = behavior
        return self
    }

    @objc func clickActivating(_ flag: Bool) -> HSCanvas {
        isClickActivating = flag
        if let window = nsWindow {
            if flag {
                window.styleMask.remove(.nonactivatingPanel)
            } else {
                window.styleMask.insert(.nonactivatingPanel)
            }
        }
        return self
    }

    @objc func ignoreMouseEvents(_ flag: Bool) -> HSCanvas {
        ignoresMouseEventsFlag = flag
        nsWindow?.ignoresMouseEvents = flag
        return self
    }

    private func resolvedLevel() -> NSWindow.Level {
        NSWindow.Level(rawValue: windowLevelRaw ?? HSCanvasModule.windowLevelValues["normal"]!)
    }

    // MARK: - Element management

    @objc func appendElements(_ elements: [[String: Any]]) -> HSCanvas {
        if rejectIfDestroyed("appendElements") { return self }
        elements.forEach { CanvasElementDrawing.warnAboutInvalidAttributes($0, caller: "appendElements") }
        elementStore.elements.append(contentsOf: elements)
        return self
    }

    @objc func insertElement(_ element: [String: Any], _ index: Int) -> HSCanvas {
        if rejectIfDestroyed("insertElement") { return self }
        CanvasElementDrawing.warnAboutInvalidAttributes(element, caller: "insertElement")
        let clamped = max(0, min(index, elementStore.elements.count))
        elementStore.elements.insert(element, at: clamped)
        return self
    }

    @objc func assignElement(_ element: [String: Any], _ index: Int) -> HSCanvas {
        if rejectIfDestroyed("assignElement") { return self }
        CanvasElementDrawing.warnAboutInvalidAttributes(element, caller: "assignElement")
        if index >= 0 && index < elementStore.elements.count {
            elementStore.elements[index] = element
        } else if index == elementStore.elements.count {
            elementStore.elements.append(element)
        } else {
            AKWarning("hs.canvas: assignElement() index \(index) out of bounds")
        }
        return self
    }

    @objc func removeElement(_ index: Int) -> HSCanvas {
        guard index >= 0 && index < elementStore.elements.count else {
            AKWarning("hs.canvas: removeElement() index \(index) out of bounds")
            return self
        }
        elementStore.elements.remove(at: index)
        return self
    }

    @objc func removeLastElement() -> HSCanvas {
        guard !elementStore.elements.isEmpty else { return self }
        elementStore.elements.removeLast()
        return self
    }

    @objc func replaceElements(_ elements: [[String: Any]]) -> HSCanvas {
        if rejectIfDestroyed("replaceElements") { return self }
        elements.forEach { CanvasElementDrawing.warnAboutInvalidAttributes($0, caller: "replaceElements") }
        elementStore.elements = elements
        return self
    }

    @objc func elementCount() -> Int {
        elementStore.elements.count
    }

    @objc func canvasElements() -> [[String: Any]] {
        elementStore.elements
    }

    @objc func elementKeys(_ index: Int) -> [String] {
        guard index >= 0 && index < elementStore.elements.count else { return [] }
        return Array(elementStore.elements[index].keys)
    }

    @objc func elementAttribute(_ index: Int, _ key: String) -> Any? {
        guard index >= 0 && index < elementStore.elements.count else { return nil }
        return elementStore.elements[index][key]
    }

    @objc func setElementAttribute(_ index: Int, _ key: String, _ value: Any) -> HSCanvas {
        guard index >= 0 && index < elementStore.elements.count else {
            AKWarning("hs.canvas: setElementAttribute() index \(index) out of bounds")
            return self
        }
        CanvasElementDrawing.warnAboutInvalidAttribute(key, value, caller: "setElementAttribute")
        elementStore.elements[index][key] = value
        return self
    }

    @objc func removeElementAttribute(_ index: Int, _ key: String) -> HSCanvas {
        guard index >= 0 && index < elementStore.elements.count else {
            AKWarning("hs.canvas: removeElementAttribute() index \(index) out of bounds")
            return self
        }
        elementStore.elements[index].removeValue(forKey: key)
        return self
    }

    @objc func elementBounds(_ index: Int) -> [String: Any] {
        guard index >= 0 && index < elementStore.elements.count else { return [:] }
        let element = elementStore.elements[index]
        let containerSize = nsWindow?.frame.size ?? canvasFrame.size
        guard var path = CanvasElementDrawing.pathFor(element: element, containerSize: containerSize) else { return [:] }
        // Match what's actually drawn: the whole-canvas transform from setTransformation()
        // is applied at render time (HSCanvasRenderView), so the reported bounds have to
        // account for it too, or they'll disagree with the displayed shape.
        if let canvasTransform = elementStore.canvasTransform {
            path = path.applying(canvasTransform)
        }
        let rect = path.boundingRect
        return ["x": rect.origin.x, "y": rect.origin.y, "w": rect.size.width, "h": rect.size.height]
    }

    @objc func minimumTextSize(_ source: JSValue, _ text: JSValue) -> [String: Any] {
        let attributes: [String: Any]
        let string: String
        if source.isString && (text.isUndefined || text.isNull) {
            // minimumTextSize(text): v1's form with the index left out
            attributes = [:]
            string = source.toString()
        } else {
            guard text.isString else {
                AKWarning("hs.canvas: minimumTextSize() needs a string to measure")
                return [:]
            }
            string = text.toString()
            if source.isNumber {
                // Bounds-checked as a double: toInt32() would wrap an index past 2^32 back into range
                let index = source.toDouble()
                guard index >= 0 && index < Double(elementStore.elements.count) else {
                    AKWarning("hs.canvas: minimumTextSize() index \(source.toString() ?? "") is out of bounds (the canvas has \(elementStore.elements.count) elements)")
                    return [:]
                }
                attributes = elementStore.elements[Int(index)]
            } else if source.isObject, let dict = source.toDictionary() as? [String: Any] {
                attributes = dict
            } else if source.isUndefined || source.isNull {
                attributes = [:]
            } else {
                AKWarning("hs.canvas: minimumTextSize() needs an element index or an object of font attributes")
                return [:]
            }
        }
        let size = CanvasElementDrawing.minimumTextSize(text: string, element: attributes)
        return ["w": size.width, "h": size.height]
    }

    // MARK: - Mouse interaction

    @objc func mouseCallback(_ callback: JSFunction) -> HSCanvas {
        if rejectIfDestroyed("mouseCallback") { return self }
        mouseCallbackRef?.detach(from: self)
        mouseCallbackRef = JSCallback(value: callback, owner: self)
        return self
    }

    @objc func canvasMouseEvents(_ down: Bool, _ up: Bool, _ enterExit: Bool, _ move: Bool, _ rightDown: Bool, _ rightUp: Bool) -> HSCanvas {
        elementStore.canvasTrackMouseDown = down
        elementStore.canvasTrackMouseUp = up
        elementStore.canvasTrackRightMouseDown = rightDown
        elementStore.canvasTrackRightMouseUp = rightUp
        elementStore.canvasTrackMouseEnterExit = enterExit
        elementStore.canvasTrackMouseMove = move
        return self
    }

    // MARK: - Element and canvas transforms

    @objc func rotateElement(_ index: Int, _ angle: Double) -> HSCanvas {
        guard index >= 0 && index < elementStore.elements.count else {
            AKWarning("hs.canvas: rotateElement() index \(index) out of bounds")
            return self
        }
        elementStore.elements[index]["rotation"] = angle
        elementStore.elements[index].removeValue(forKey: "rotationPoint")
        return self
    }

    @objc func rotateElementAroundPoint(_ index: Int, _ angle: Double, _ point: [String: Any]) -> HSCanvas {
        guard index >= 0 && index < elementStore.elements.count else {
            AKWarning("hs.canvas: rotateElementAroundPoint() index \(index) out of bounds")
            return self
        }
        elementStore.elements[index]["rotation"] = angle
        elementStore.elements[index]["rotationPoint"] = point
        return self
    }

    @objc func setElementTransformation(_ index: Int, _ matrix: [String: Any]) -> HSCanvas {
        guard index >= 0 && index < elementStore.elements.count else {
            AKWarning("hs.canvas: setElementTransformation() index \(index) out of bounds")
            return self
        }
        elementStore.elements[index]["transformation"] = matrix
        return self
    }

    @objc func setTransformation(_ matrix: [String: Any]) -> HSCanvas {
        elementStore.canvasTransform = CanvasElementDrawing.transformMatrix(matrix)
        return self
    }

    @objc func clearTransformation() -> HSCanvas {
        elementStore.canvasTransform = nil
        return self
    }

    // MARK: - Export and duplication

    @objc func imageFromCanvas() -> HSImage? {
        guard !isDestroyed else { return nil }
        let containerSize = nsWindow?.frame.size ?? canvasFrame.size
        guard containerSize.width > 0, containerSize.height > 0 else { return nil }

        let view = HSCanvasRenderView(store: elementStore)
            .frame(width: containerSize.width, height: containerSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = nsWindow?.backingScaleFactor ?? 2.0

        guard let cgImage = renderer.cgImage else {
            AKError("hs.canvas: imageFromCanvas() failed to render")
            return nil
        }
        return HSImage(image: NSImage(cgImage: cgImage, size: containerSize))
    }

    @objc func duplicate() -> HSCanvas {
        if rejectIfDestroyed("duplicate") { return self }
        guard let module else {
            AKError("hs.canvas: duplicate() failed, module reference is gone")
            return self
        }
        let copy = HSCanvas(frame: canvasFrame, module: module)
        copy.elementStore.elements = elementStore.elements
        copy.elementStore.canvasTransform = elementStore.canvasTransform
        copy.windowLevelRaw = windowLevelRaw
        copy.windowBehaviorRaw = windowBehaviorRaw
        copy.isClickActivating = isClickActivating
        copy.ignoresMouseEventsFlag = ignoresMouseEventsFlag
        copy.accessibilitySubroleValue = accessibilitySubroleValue
        copy.targetAlpha = targetAlpha
        return copy
    }

    // MARK: - Accessibility

    @objc func setAccessibilitySubrole(_ subrole: String) -> HSCanvas {
        accessibilitySubroleValue = subrole
        nsWindow?.contentView?.setAccessibilitySubrole(NSAccessibility.Subrole(rawValue: subrole))
        return self
    }

    // MARK: - Drag and drop

    @objc func draggingCallback(_ callback: JSFunction) -> HSCanvas {
        if rejectIfDestroyed("draggingCallback") { return self }
        draggingCallbackRef?.detach(from: self)
        draggingCallbackRef = JSCallback(value: callback, owner: self)
        return self
    }
}
