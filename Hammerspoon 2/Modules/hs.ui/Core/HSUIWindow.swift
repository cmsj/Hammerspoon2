//
//  HSUIWindow.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import JavaScriptCore
import AppKit
import SwiftUI

/// # HSUIWindow
///
/// **A custom window with declarative UI building**
///
/// `HSUIWindow` allows you to create custom windows with a SwiftUI-like
/// declarative syntax. Build interfaces using shapes, text, images, and layout containers.
///
/// ## Building UI Elements
///
/// - **Shapes**: `rectangle()`, `circle()`
/// - **Text**: `text(content)`
/// - **Buttons**: `button(label)` — uses SwiftUI's native Button for press-state feedback
/// - **Images**: `image(imageValue)`
/// - **Layout**: `vstack()`, `hstack()`, `zstack()`, `spacer()`
///
/// ## Modifying Elements
///
/// - **Shape modifiers**: `fill()`, `stroke()`, `strokeWidth()`, `cornerRadius()`
/// - **Text modifiers**: `font()`, `foregroundColor()`
/// - **Image modifiers**: `resizable()`, `aspectRatio(mode)`
/// - **Layout modifiers**: `frame()`, `opacity()`, `padding()`, `spacing()`
///
/// ## Examples
///
/// **Simple window with text and shapes:**
/// ```javascript
/// hs.ui.window({x: 100, y: 100, w: 300, h: 200})
///     .vstack()
///         .spacing(10)
///         .padding(20)
///         .text("Dashboard")
///             .font(HSFont.largeTitle())
///             .foregroundColor("#FFFFFF")
///         .rectangle()
///             .fill("#4A90E2")
///             .cornerRadius(10)
///             .frame({w: "90%", h: 80})
///     .end()
///     .backgroundColor("#2C3E50")
///     .show();
/// ```
///
/// **Window with image:**
/// ```javascript
/// const img = HSImage.fromPath("~/Pictures/photo.jpg")
/// hs.ui.window({x: 100, y: 100, w: 400, h: 300})
///     .vstack()
///         .padding(20)
///         .image(img)
///             .resizable()
///             .aspectRatio("fit")
///             .frame({w: 360, h: 240})
///     .end()
///     .show();
/// ```
@objc protocol HSUIWindowAPI: HSTypeAPI, JSExport {
    // MARK: Window Management

    /// Show the window
    /// - Returns: Self for chaining
    @objc func show() -> HSUIWindow

    /// Hide the window (keeps it in memory)
    @objc func hide()

    /// Close and destroy the window
    @objc func close()

    // MARK: Window Styling

    /// Show or hide the window's title bar
    ///
    /// By default windows have a title bar. Pass `false` to create a borderless window.
    /// `.closable()`, `.miniaturizable()`, and `.allowResize()` only take visual effect
    /// when the window is titled.
    ///
    /// - Parameter show: Pass `false` to make the window borderless
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// // Borderless floating overlay
    /// hs.ui.window({x: 100, y: 100, w: 400, h: 300})
    ///     .titled(false)
    ///     .level("floating")
    ///     .show()
    /// ```
    @objc func titled(_ show: Bool) -> HSUIWindow

    /// Show or hide the close button on the window
    ///
    /// Requires `.titled(true)` to be visible. Enabled by default.
    ///
    /// - Parameter show: Pass `false` to hide the close button
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.window({x: 100, y: 100, w: 800, h: 600})
    ///     .closable(false).show()
    /// ```
    @objc func closable(_ show: Bool) -> HSUIWindow

    /// Show or hide the miniaturize (yellow) button on the window
    ///
    /// Requires `.titled(true)` to be visible. Enabled by default.
    ///
    /// - Parameter show: Pass `false` to hide the miniaturize button
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.window({x: 100, y: 100, w: 800, h: 600})
    ///     .miniaturizable(false).show()
    /// ```
    @objc func miniaturizable(_ show: Bool) -> HSUIWindow

    /// Allow or prevent the user from resizing the window
    ///
    /// Enabled by default. Only has a visual effect when `.titled(true)` is also set.
    ///
    /// - Parameter enable: Pass `false` to prevent the user from resizing the window
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.window({x: 100, y: 100, w: 800, h: 600})
    ///     .allowResize(false).show()
    /// ```
    @objc func allowResize(_ enable: Bool) -> HSUIWindow

    /// Set the text shown in the window's title bar
    ///
    /// Only visible when `.titled(true)` is set (the default).
    ///
    /// - Parameter text: The title bar text
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.window({x: 100, y: 100, w: 800, h: 600})
    ///     .windowTitle("My Browser").show()
    /// ```
    @objc func windowTitle(_ text: String) -> HSUIWindow

    /// Set the window stacking level
    ///
    /// Controls where this window sits in the macOS window hierarchy.
    /// Supported values:
    /// - `"normal"` — regular app window, sits with other app windows (default)
    /// - `"floating"` — floats above all normal windows
    /// - `"screenSaver"` — above the screen saver layer
    /// - `"dock"` — same level as the Dock
    /// - `"status"` — status bar level
    /// - `"popUpMenu"` — pop-up menu level
    ///
    /// - Parameter name: {'"normal"' | '"floating"' | '"screenSaver"' | '"dock"' | '"status"' | '"popUpMenu"'} The level name
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.window({x: 100, y: 100, w: 800, h: 600})
    ///     .level("floating").show()
    /// ```
    @objc func level(_ name: String) -> HSUIWindow

    /// Set the window's background color
    /// - Parameter colorValue: Color as an HSColor object
    /// - Returns: Self for chaining
    @objc func backgroundColor(_ colorValue: HSColor) -> HSUIWindow

    // MARK: Shape Elements

    /// Add a rectangle shape
    /// - Returns: Self for chaining (apply modifiers like `fill()`, `frame()`)
    @objc func rectangle() -> HSUIWindow

    /// Add a circle shape
    /// - Returns: Self for chaining (apply modifiers like `fill()`, `frame()`)
    @objc func circle() -> HSUIWindow

    /// Add a text element
    /// - Parameter content: {string | HSString} The text to display — a plain JS string for static text,
    ///   or an `HSString` object (from `hs.ui.string()`) for reactive text
    /// - Returns: Self for chaining (apply modifiers like `font()`, `foregroundColor()`)
    @objc func text(_ content: JSValue) -> HSUIWindow

    /// Add an image element
    /// - Parameter imageValue: Image as HSImage object
    /// - Returns: Self for chaining (apply modifiers like `resizable()`, `aspectRatio()`, `frame()`)
    @objc func image(_ imageValue: HSImage) -> HSUIWindow

    /// Add a button element
    /// - Parameter label: {string | HSString} The button label — a plain JS string for static text,
    ///   or an `HSString` object (from `hs.ui.string()`) for reactive text
    /// - Returns: Self for chaining (apply `.fill()`, `.cornerRadius()`, `.font()`,
    ///   `.foregroundColor()`, `.frame()`, `.onClick()` etc.)
    @objc func button(_ label: JSValue) -> HSUIWindow

    // MARK: Layout Containers

    /// Begin a vertical stack (elements arranged top to bottom)
    /// - Returns: Self for chaining (call `end()` when done)
    @objc func vstack() -> HSUIWindow

    /// Begin a horizontal stack (elements arranged left to right)
    /// - Returns: Self for chaining (call `end()` when done)
    @objc func hstack() -> HSUIWindow

    /// Begin a z-stack (overlapping elements)
    /// - Returns: Self for chaining (call `end()` when done)
    @objc func zstack() -> HSUIWindow

    /// Add flexible spacing that expands to fill available space
    /// - Returns: Self for chaining
    @objc func spacer() -> HSUIWindow

    /// Embed a web browser element created with `hs.ui.webview()` (macOS 26+)
    ///
    /// The element fills the available space in the window layout.
    /// Keep a reference to the element to call navigation methods after the window is shown.
    ///
    /// - Parameter element: A `UIWebView` created via `hs.ui.webview()`
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// const wv = hs.ui.webview()
    ///     .toolbar(["back", "forward", "reload", "url"])
    ///     .loadURL("https://apple.com")
    ///
    /// hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
    ///     .webview(wv)
    ///     .show()
    /// ```
    @available(macOS 26.0, *)
    @objc func webview(_ element: UIWebView) -> HSUIWindow

    /// End the current layout container
    /// - Returns: Self for chaining
    @objc func end() -> HSUIWindow

    // MARK: Shape Modifiers

    /// Fill a shape with a color
    /// - Parameter colorValue: Color as an HSColor
    /// - Returns: Self for chaining
    @objc func fill(_ colorValue: HSColor) -> HSUIWindow

    /// Add a stroke (border) to a shape
    /// - Parameter colorValue: Color as an HSColor
    /// - Returns: Self for chaining
    @objc func stroke(_ colorValue: HSColor) -> HSUIWindow

    /// Set the stroke width
    /// - Parameter width: Width in points
    /// - Returns: Self for chaining
    @objc func strokeWidth(_ width: Double) -> HSUIWindow

    /// Round the corners of a shape
    /// - Parameter radius: Corner radius in points
    /// - Returns: Self for chaining
    @objc func cornerRadius(_ radius: Double) -> HSUIWindow

    /// Set the frame (size) of an element
    /// - Parameter dict: Dictionary with `w` and/or `h` (can be numbers or percentage strings like "50%")
    /// - Returns: Self for chaining
    @objc func frame(_ dict: [String: Any]) -> HSUIWindow

    /// Set the opacity of an element
    /// - Parameter value: Opacity from 0.0 (transparent) to 1.0 (opaque)
    /// - Returns: Self for chaining
    @objc func opacity(_ value: Double) -> HSUIWindow

    // MARK: Text Modifiers

    /// Set the font for a text element
    /// - Parameter font: An HSFont object (e.g., `HSFont.title()`)
    /// - Returns: Self for chaining
    @objc func font(_ font: HSFont) -> HSUIWindow

    /// Set the text color
    /// - Parameter colorValue: Color as HSColor
    /// - Returns: Self for chaining
    @objc func foregroundColor(_ colorValue: HSColor) -> HSUIWindow

    // MARK: Image Modifiers

    /// Make an image resizable (allows it to scale with frame size)
    /// - Returns: Self for chaining
    @objc func resizable() -> HSUIWindow

    /// Set the aspect ratio mode for an image
    /// - Parameter mode: "fit" (scales to fit within frame) or "fill" (scales to fill frame)
    /// - Returns: Self for chaining
    @objc func aspectRatio(_ mode: String) -> HSUIWindow

    // MARK: Layout Modifiers

    /// Add padding around a layout container
    /// - Parameter value: Padding in points
    /// - Returns: Self for chaining
    @objc func padding(_ value: Double) -> HSUIWindow

    /// Set spacing between elements in a stack
    /// - Parameter value: Spacing in points
    /// - Returns: Self for chaining
    @objc func spacing(_ value: Double) -> HSUIWindow

    // MARK: Interaction Callbacks

    /// Set a callback to fire when the element is clicked
    /// - Parameter callback: {() => void} A JavaScript function to call on click
    /// - Returns: Self for chaining
    @objc func onClick(_ callback: JSFunction) -> HSUIWindow

    /// Set a callback to fire when the cursor enters or leaves the element
    /// - Parameter callback: {(isHovering: boolean) => void} A JavaScript function called with `true` when the cursor enters and `false` when it leaves
    /// - Returns: Self for chaining
    @objc func onHover(_ callback: JSFunction) -> HSUIWindow
}

@MainActor
@objc class HSUIWindow: NSObject, HSUIWindowAPI, NSWindowDelegate {
    @objc var typeName = "HSUIWindow"

    // Window properties
    private var windowFrame: CGRect
    private var nsWindow: NSWindow?
    private var windowBackgroundColor: Color = .clear
    private let windowID: UUID = UUID()
    private weak var module: HSUIModule?

    // Style configuration
    private var isTitled: Bool = true
    private var isClosable: Bool = true
    private var isMiniaturizable: Bool = true
    private var isResizable: Bool = true
    private var windowTitleText: String = ""
    private var windowLevelName: String = "normal"

    // Element tree
    private var rootElement: (any HSUIElement)?
    private var currentElement: (any HSUIElement)?
    private var containerStack: [any UIContainer] = []

    // Type-erased refs to UIWebView elements (macOS 26+) for eager resource cleanup on close.
    private var embeddedWebViews: [AnyObject] = []

    // Initialization
    init(frame: CGRect, module: HSUIModule) {
        self.windowFrame = frame
        self.module = module
        super.init()
    }

    convenience init(dict: [String: Any], module: HSUIModule) {
        let x = (dict["x"] as? NSNumber)?.doubleValue ?? 0
        let y = (dict["y"] as? NSNumber)?.doubleValue ?? 0
        let w = (dict["w"] as? NSNumber)?.doubleValue ?? 200
        let h = (dict["h"] as? NSNumber)?.doubleValue ?? 200

        self.init(frame: CGRect(x: x, y: y, width: w, height: h), module: module)
    }

    isolated deinit {
        close()
        AKDebug("deinit of HSUIWindow: \(windowID)")
    }

    // MARK: - Window Management

    @objc func show() -> HSUIWindow {
        guard let root = rootElement else {
            AKError("hs.ui.window: Cannot show window without content")
            return self
        }

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: resolvedStyleMask(),
            backing: .buffered,
            defer: false
        )

        let contentView = UICanvasView(
            element: root,
            backgroundColor: windowBackgroundColor,
            containerSize: windowFrame.size
        )
        window.contentView = NSHostingView(rootView: contentView)
        window.isOpaque = false
        window.backgroundColor = NSColor(windowBackgroundColor)
        window.level = resolvedLevel()
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !windowTitleText.isEmpty {
            window.title = windowTitleText
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.nsWindow = window

        // Register with module to prevent premature deallocation
        module?.register(self, id: windowID)

        return self
    }

    @objc func hide() {
        nsWindow?.orderOut(nil)
    }

    @objc func close() {
        guard nsWindow != nil || rootElement != nil else { return } // Already closed

        // Destroy embedded web views first to release their JS callbacks before the element
        // tree is released. This breaks JSValue → JSContext chains so the context can be freed.
        if #available(macOS 26.0, *) {
            for obj in embeddedWebViews { (obj as? UIWebView)?.destroy() }
        }
        embeddedWebViews.removeAll()

        // Release the element tree. Elements may hold closures that captured JSValue
        // callbacks (onClick/onHover) which would hold the old JSContext alive otherwise.
        rootElement = nil
        currentElement = nil
        containerStack.removeAll()

        module?.unregister(window: windowID)

        nsWindow?.delegate = nil
        nsWindow?.close()
        nsWindow = nil
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        // Window is being closed (by user or system)
        Task { @MainActor in
            self.close()
        }
    }

    // MARK: - Window Styling

    @objc func titled(_ show: Bool) -> HSUIWindow { isTitled = show; return self }
    @objc func closable(_ show: Bool) -> HSUIWindow { isClosable = show; return self }
    @objc func miniaturizable(_ show: Bool) -> HSUIWindow { isMiniaturizable = show; return self }
    @objc func allowResize(_ enable: Bool) -> HSUIWindow { isResizable = enable; return self }
    @objc func windowTitle(_ text: String) -> HSUIWindow { windowTitleText = text; return self }
    @objc func level(_ name: String) -> HSUIWindow { windowLevelName = name; return self }

    private func resolvedStyleMask() -> NSWindow.StyleMask {
        guard isTitled else { return [.borderless] }
        var mask: NSWindow.StyleMask = [.titled]
        if isClosable { mask.insert(.closable) }
        if isMiniaturizable { mask.insert(.miniaturizable) }
        if isResizable { mask.insert(.resizable) }
        return mask
    }

    private func resolvedLevel() -> NSWindow.Level {
        switch windowLevelName {
        case "normal":      return .normal
        case "floating":    return .floating
        case "screenSaver": return .screenSaver
        case "dock":        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        case "status":      return .statusBar
        case "popUpMenu":   return .popUpMenu
        default:
            AKWarning("hs.ui.window: Unknown level '\(windowLevelName)', using 'floating'")
            return .floating
        }
    }

    // MARK: - Background Styling

    @objc func backgroundColor(_ colorValue: HSColor) -> HSUIWindow {
        windowBackgroundColor = colorValue.color
        return self
    }

    // MARK: - Shape Constructors

    @objc func rectangle() -> HSUIWindow {
        let rect = UIRectangle()
        currentElement = rect
        addToCurrentContainer(rect)
        return self
    }

    @objc func circle() -> HSUIWindow {
        let circle = UICircle()
        currentElement = circle
        addToCurrentContainer(circle)
        return self
    }

    @objc func text(_ content: JSValue) -> HSUIWindow {
        guard let hsString = HSString.fromJSValue(content) else { return self }
        let textElement = UIText(content: hsString)
        currentElement = textElement
        addToCurrentContainer(textElement)
        return self
    }

    @objc func image(_ imageValue: HSImage) -> HSUIWindow {
        let imageElement = UIImage(hsImage: imageValue)
        currentElement = imageElement
        addToCurrentContainer(imageElement)
        return self
    }

    @objc func button(_ label: JSValue) -> HSUIWindow {
        guard let hsString = HSString.fromJSValue(label) else { return self }
        let buttonElement = UIButton(label: hsString)
        currentElement = buttonElement
        addToCurrentContainer(buttonElement)
        return self
    }

    // MARK: - Layout Containers

    @objc func vstack() -> HSUIWindow {
        let stack = UIVStack()
        currentElement = stack
        containerStack.append(stack)

        if rootElement == nil {
            rootElement = stack
        } else if !containerStack.isEmpty && containerStack.count >= 2 {
            containerStack[containerStack.count - 2].addChild(stack)
        }

        return self
    }

    @objc func hstack() -> HSUIWindow {
        let stack = UIHStack()
        currentElement = stack
        containerStack.append(stack)

        if rootElement == nil {
            rootElement = stack
        } else if !containerStack.isEmpty && containerStack.count >= 2 {
            containerStack[containerStack.count - 2].addChild(stack)
        }

        return self
    }

    @objc func zstack() -> HSUIWindow {
        let stack = UIZStack()
        currentElement = stack
        containerStack.append(stack)

        if rootElement == nil {
            rootElement = stack
        } else if !containerStack.isEmpty && containerStack.count >= 2 {
            containerStack[containerStack.count - 2].addChild(stack)
        }

        return self
    }

    @objc func spacer() -> HSUIWindow {
        let spacer = UISpacer()
        currentElement = spacer
        addToCurrentContainer(spacer)
        return self
    }

    @objc func end() -> HSUIWindow {
        if !containerStack.isEmpty {
            containerStack.removeLast()
        }
        currentElement = containerStack.last
        return self
    }

    // MARK: - Shape Modifiers

    @objc func fill(_ colorValue: HSColor) -> HSUIWindow {
        if let shapeable = currentElement as? any ShapeModifiable {
            shapeable.fillColor = colorValue
        }
        return self
    }

    @objc func stroke(_ colorValue: HSColor) -> HSUIWindow {
        if let shapeable = currentElement as? any ShapeModifiable {
            shapeable.strokeColor = colorValue
        }
        return self
    }

    @objc func strokeWidth(_ width: Double) -> HSUIWindow {
        if let shapeable = currentElement as? any ShapeModifiable {
            shapeable.strokeWidth = CGFloat(width)
        }
        return self
    }

    @objc func cornerRadius(_ radius: Double) -> HSUIWindow {
        if let shapeable = currentElement as? any ShapeModifiable {
            shapeable.cornerRadius = CGFloat(radius)
        }
        return self
    }

    @objc func frame(_ dict: [String: Any]) -> HSUIWindow {
        if let frameable = currentElement as? any FrameModifiable,
           let uiFrame = UIFrame.from(dict: dict) {
            frameable.elementFrame = uiFrame
        }
        return self
    }

    @objc func opacity(_ value: Double) -> HSUIWindow {
        if let modifiable = currentElement as? any OpacityModifiable {
            modifiable.elementOpacity = value
        }
        return self
    }

    // MARK: - Text Modifiers

    @objc func font(_ font: HSFont) -> HSUIWindow {
        if let textable = currentElement as? any TextModifiable {
            textable.font = font.font
        }
        return self
    }

    @objc func foregroundColor(_ colorValue: HSColor) -> HSUIWindow {
        if let textable = currentElement as? any TextModifiable {
            textable.foregroundColor = colorValue
        }
        return self
    }

    // MARK: - Image Modifiers

    @objc func resizable() -> HSUIWindow {
        if let imageElement = currentElement as? UIImage {
            imageElement.resizable = true
        }
        return self
    }

    @objc func aspectRatio(_ mode: String) -> HSUIWindow {
        if let imageElement = currentElement as? UIImage {
            switch mode.lowercased() {
            case "fit":
                imageElement.aspectRatio = .fit
            case "fill":
                imageElement.aspectRatio = .fill
            default:
                AKError("hs.ui: Invalid aspect ratio mode: \(mode), use 'fit' or 'fill'")
            }
        }
        return self
    }

    // MARK: - Layout Modifiers

    @objc func padding(_ value: Double) -> HSUIWindow {
        if let container = currentElement as? PaddingModifiable {
            container.elementPadding = CGFloat(value)
        }
        return self
    }

    @objc func spacing(_ value: Double) -> HSUIWindow {
        if let container = currentElement as? SpacingModifiable {
            container.elementSpacing = CGFloat(value)
        }
        return self
    }

    // MARK: - Interaction Callbacks

    @objc func onClick(_ callback: JSFunction) -> HSUIWindow {
        if let interactive = currentElement as? any InteractiveModifiable {
            interactive.clickCallback = { callback.call(withArguments: []) }
        } else {
            AKWarning("hs.ui: onClick() called on an element that does not support interactions")
        }
        return self
    }

    @objc func onHover(_ callback: JSFunction) -> HSUIWindow {
        if let interactive = currentElement as? any InteractiveModifiable {
            interactive.hoverCallback = { isHovered in callback.call(withArguments: [isHovered]) }
        } else {
            AKWarning("hs.ui: onHover() called on an element that does not support interactions")
        }
        return self
    }

    // MARK: - Web View Element

    @available(macOS 26.0, *)
    @objc func webview(_ element: UIWebView) -> HSUIWindow {
        addToCurrentContainer(element)
        currentElement = element
        embeddedWebViews.append(element)
        return self
    }

    // MARK: - Helper Methods

    private func addToCurrentContainer(_ element: any HSUIElement) {
        if rootElement == nil {
            rootElement = element
        } else if let container = containerStack.last {
            container.addChild(element)
        }
    }
}
