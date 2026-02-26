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
/// `HSUIWindow` allows you to create custom borderless windows with a SwiftUI-like
/// declarative syntax. Build interfaces using shapes, text, images, and layout containers.
///
/// ## Building UI Elements
///
/// - **Shapes**: `rectangle()`, `circle()`
/// - **Text**: `text(content)`
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

    /// Set the window's background color
    /// - Parameter colorValue: Color as hex string (e.g., "#FF0000") or HSColor object
    /// - Returns: Self for chaining
    @objc func backgroundColor(_ colorValue: JSValue) -> HSUIWindow

    // MARK: Shape Elements

    /// Add a rectangle shape
    /// - Returns: Self for chaining (apply modifiers like `fill()`, `frame()`)
    @objc func rectangle() -> HSUIWindow

    /// Add a circle shape
    /// - Returns: Self for chaining (apply modifiers like `fill()`, `frame()`)
    @objc func circle() -> HSUIWindow

    /// Add a text element
    /// - Parameter content: The text to display
    /// - Returns: Self for chaining (apply modifiers like `font()`, `foregroundColor()`)
    @objc func text(_ content: String) -> HSUIWindow

    /// Add an image element
    /// - Parameter imageValue: Image as HSImage object or file path string
    /// - Returns: Self for chaining (apply modifiers like `resizable()`, `aspectRatio()`, `frame()`)
    @objc func image(_ imageValue: JSValue) -> HSUIWindow

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

    /// End the current layout container
    /// - Returns: Self for chaining
    @objc func end() -> HSUIWindow

    // MARK: Shape Modifiers

    /// Fill a shape with a color
    /// - Parameter colorValue: Color as hex string or HSColor
    /// - Returns: Self for chaining
    @objc func fill(_ colorValue: JSValue) -> HSUIWindow

    /// Add a stroke (border) to a shape
    /// - Parameter colorValue: Color as hex string or HSColor
    /// - Returns: Self for chaining
    @objc func stroke(_ colorValue: JSValue) -> HSUIWindow

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
    /// - Parameter colorValue: Color as hex string or HSColor
    /// - Returns: Self for chaining
    @objc func foregroundColor(_ colorValue: JSValue) -> HSUIWindow

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

    // Element tree
    private var rootElement: (any HSUIElement)?
    private var currentElement: (any HSUIElement)?
    private var containerStack: [any UIContainer] = []

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
        AKTrace("deinit of HSUIWindow: \(windowID)")
    }

    // MARK: - Window Management

    @objc func show() -> HSUIWindow {
        guard let root = rootElement else {
            AKError("hs.ui.window: Cannot show window without content")
            return self
        }

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
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
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self

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
        guard nsWindow != nil else { return } // Already closed

        // Unregister from module
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

    // MARK: - Background Styling

    @objc func backgroundColor(_ colorValue: JSValue) -> HSUIWindow {
        if let color = colorValue.toColor() {
            windowBackgroundColor = color
        }
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

    @objc func text(_ content: String) -> HSUIWindow {
        let textElement = UIText(content: content)
        currentElement = textElement
        addToCurrentContainer(textElement)
        return self
    }

    @objc func image(_ imageValue: JSValue) -> HSUIWindow {
        let nsImage = imageValue.toNSImage()
        let imageElement = UIImage(image: nsImage)
        currentElement = imageElement
        addToCurrentContainer(imageElement)
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

    @objc func fill(_ colorValue: JSValue) -> HSUIWindow {
        if let shapeable = currentElement as? any ShapeModifiable,
           let color = colorValue.toColor() {
            shapeable.fillColor = color
        }
        return self
    }

    @objc func stroke(_ colorValue: JSValue) -> HSUIWindow {
        if let shapeable = currentElement as? any ShapeModifiable,
           let color = colorValue.toColor() {
            shapeable.strokeColor = color
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
        if let textElement = currentElement as? UIText {
            textElement.font = font.font
        }
        return self
    }

    @objc func foregroundColor(_ colorValue: JSValue) -> HSUIWindow {
        if let textElement = currentElement as? UIText,
           let color = colorValue.toColor() {
            textElement.foregroundColor = color
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

    // MARK: - Helper Methods

    private func addToCurrentContainer(_ element: any HSUIElement) {
        if rootElement == nil {
            rootElement = element
        } else if let container = containerStack.last {
            container.addChild(element)
        }
    }
}
