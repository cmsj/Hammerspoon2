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

/// JavaScript API for HSUIWindow
@objc protocol HSUIWindowAPI: HSTypeAPI, JSExport {
    // Window management
    @objc func show() -> HSUIWindow
    @objc func hide()
    @objc func close()

    // Background styling
    @objc func backgroundColor(_ colorValue: JSValue) -> HSUIWindow

    // Shape constructors
    @objc func rectangle() -> HSUIWindow
    @objc func circle() -> HSUIWindow
    @objc func text(_ content: String) -> HSUIWindow

    // Layout containers
    @objc func vstack() -> HSUIWindow
    @objc func hstack() -> HSUIWindow
    @objc func zstack() -> HSUIWindow
    @objc func spacer() -> HSUIWindow
    @objc func end() -> HSUIWindow

    // Modifiers for shapes
    @objc func fill(_ colorValue: JSValue) -> HSUIWindow
    @objc func stroke(_ colorValue: JSValue) -> HSUIWindow
    @objc func strokeWidth(_ width: Double) -> HSUIWindow
    @objc func cornerRadius(_ radius: Double) -> HSUIWindow
    @objc func frame(_ dict: [String: Any]) -> HSUIWindow
    @objc func opacity(_ value: Double) -> HSUIWindow

    // Modifiers for text
    @objc func font(_ font: HSFont) -> HSUIWindow
    @objc func foregroundColor(_ colorValue: JSValue) -> HSUIWindow

    // Layout modifiers
    @objc func padding(_ value: Double) -> HSUIWindow
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
        if let color = HSColor.fromJSValue(colorValue) {
            windowBackgroundColor = color.color
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
           let color = HSColor.fromJSValue(colorValue) {
            shapeable.fillColor = color.color
        }
        return self
    }

    @objc func stroke(_ colorValue: JSValue) -> HSUIWindow {
        if let shapeable = currentElement as? any ShapeModifiable,
           let color = HSColor.fromJSValue(colorValue) {
            shapeable.strokeColor = color.color
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
           let color = HSColor.fromJSValue(colorValue) {
            textElement.foregroundColor = color.color
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
