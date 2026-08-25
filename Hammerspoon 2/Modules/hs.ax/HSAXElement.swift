//
//  AXElementObject.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import AXSwift

/// Object representing an Accessibility element. You should not instantiate this directly, but rather, use the hs.ax methods to create these as required.
@objc protocol HSAXElementAPI: HSTypeAPI, JSExport {
    // MARK: - Basic Properties

    /// The element's role (e.g., "AXWindow", "AXButton")
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.role)
    /// ```
    @objc var role: String? { get }

    /// The element's subrole
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.subrole)
    /// ```
    @objc var subrole: String? { get }

    /// The element's title
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.title)
    /// ```
    @objc var title: String? { get }

    /// The element's value
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.value)
    /// ```
    @objc var value: Any? { get }

    /// The element's description
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.elementDescription)
    /// ```
    @objc var elementDescription: String? { get }

    /// Whether the element is enabled
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.isEnabled)
    /// ```
    @objc var isEnabled: Bool { get }

    /// Whether the element is focused
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// el.isFocused = true
    /// ```
    @objc var isFocused: Bool { get set }

    // MARK: - Geometry

    /// The element's position on screen
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.position)
    /// ```
    @objc var position: HSPoint? { get set }

    /// The element's size
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.size)
    /// ```
    @objc var size: HSSize? { get set }

    /// The element's frame (position and size combined)
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.frame)
    /// ```
    @objc var frame: HSRect? { get set }

    // MARK: - Hierarchy

    /// The element's parent
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.parent && el.parent.role)
    /// ```
    @objc var parent: HSAXElement? { get }

    /// The element's children
    /// - Returns: An array of HSAXElement objects
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.children().length)
    /// ```
    @objc func children() -> [HSAXElement]

    /// Get a specific child by index
    /// - Parameter index: The index to fetch
    /// - Returns: An HSAXElement object, if a child exists at the given index
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// const child = el.childAtIndex(0)
    /// ```
    @objc func childAtIndex(_ index: Int) -> HSAXElement?

    // MARK: - Attributes

    /// Get all available attribute names
    /// - Returns: An array of attribute names
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.attributeNames())
    /// ```
    @objc func attributeNames() -> [String]

    /// Get the value of a specific attribute
    /// - Parameter attribute: The attribute name to fetch the value for
    /// - Returns: The requested value, or nil if none was found
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.attributeValue("AXTitle"))
    /// ```
    @objc func attributeValue(_ attribute: String) -> Any?

    /// Set the value of a specific attribute
    /// - Parameters:
    ///   - attribute: The attribute name to set
    ///   - value: The value to set
    /// - Returns: True if the operation succeeded, otherwise False
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// el.setAttributeValue("AXValue", "Hello")
    /// ```
    @objc func setAttributeValue(_ attribute: String, value: Any) -> Bool

    /// Check if an attribute is settable
    /// - Parameter attribute: An attribute name
    /// - Returns: True if the attribute is settable, otherwise False
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.isAttributeSettable("AXValue"))
    /// ```
    @objc func isAttributeSettable(_ attribute: String) -> Bool

    // MARK: - Actions

    /// Get all available action names
    /// - Returns: An array of available action names
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.actionNames())
    /// ```
    @objc func actionNames() -> [String]

    /// Perform a specific action
    /// - Parameter action: The action to perform
    /// - Returns: True if the action succeeded, otherwise False
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// el.performAction("AXPress")
    /// ```
    @objc func performAction(_ action: String) -> Bool

    // MARK: - Utility

    /// Get the process ID of the application that owns this element
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.pid)
    /// ```
    @objc var pid: Int { get }
}

@_documentation(visibility: private)
@objc class HSAXElement: NSObject, HSAXElementAPI {
    @objc var typeName = "HSAXElement"

    @objc func toString() -> String {
        return "<\(typeName): \(role ?? "unknown role")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }
    let element: UIElement

    init(element: UIElement) {
        self.element = element
        super.init()
    }

    isolated deinit {
        AKDebug("deinit of HSAXElement: \(self.role ?? "unknown")")
    }

    // MARK: - Basic Properties

    @objc var role: String? {
        return try? element.role()?.rawValue
    }

    @objc var subrole: String? {
        return try? element.subrole()?.rawValue
    }

    @objc var title: String? {
        return try? element.attribute(.title)
    }

    @objc var value: Any? {
        return attributeValue(UIElement.Attribute.value.rawValue)
    }

    @objc var elementDescription: String? {
        return try? element.attribute(.description)
    }

    @objc var isEnabled: Bool {
        let enabled: Bool? = try? element.attribute(.enabled)
        return enabled ?? false
    }

    @objc var isFocused: Bool {
        get {
            let focused: Bool? = try? element.attribute(.focused)
            return focused ?? false
        }
        set {
            do {
                try element.setAttribute(.focused, value: newValue)
            } catch {
                AKError("Failed to set focused: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Geometry

    @objc var position: HSPoint? {
        get {
            guard let pos: CGPoint = try? element.attribute(.position) else {
                return nil
            }
            return pos.toBridge()
        }
        set {
            guard let newValue = newValue else {
                return
            }

            do {
                try element.setAttribute(.position, value: CGPoint(from: newValue))
            } catch {
                AKError("Failed to set position: \(error.localizedDescription)")
            }
        }
    }

    @objc var size: HSSize? {
        get {
            guard let sz: CGSize = try? element.attribute(.size) else {
                return nil
            }
            return sz.toBridge()
        }
        set {
            guard let newValue = newValue else {
                return
            }

            do {
                try element.setAttribute(.size, value: CGSize(from: newValue))
            } catch {
                AKError("Failed to set size: \(error.localizedDescription)")
            }
        }
    }

    @objc var frame: HSRect? {
        get {
            guard let frame: CGRect = try? element.attribute(.frame) else {
                return nil
            }
            return frame.toBridge()
        }
        set {
            guard let newValue = newValue else {
                return
            }
            do {
                try element.setAttribute(.position, value: newValue.origin.point)
                try element.setAttribute(.size, value: newValue.size.size)
            } catch {
                AKError("Failed to set frame: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Hierarchy

    @objc var parent: HSAXElement? {
        guard let parentElement: UIElement = try? element.attribute(.parent) else {
            return nil
        }
        return HSAXElement(element: parentElement)
    }

    @objc func children() -> [HSAXElement] {
        guard let childElements: [UIElement] = try? element.arrayAttribute(.children) else {
            return []
        }
        return childElements.map { HSAXElement(element: $0) }
    }

    @objc func childAtIndex(_ index: Int) -> HSAXElement? {
        let childElements = children()
        guard index >= 0 && index < childElements.count else {
            return nil
        }
        return childElements[index]
    }

    // MARK: - Attributes

    @objc func attributeNames() -> [String] {
        do {
            let attributes = try element.attributes()
            return attributes.map { $0.rawValue }
        } catch {
            AKError("Failed to get attribute names: \(error.localizedDescription)")
            return []
        }
    }

    @objc func attributeValue(_ attribute: String) -> Any? {
        let attr = UIElement.Attribute(rawValue: attribute)
        guard let rawValue = try? element.getMultipleAttributes([attr]).first?.value else {
            return nil
        }

        return bridgeValue(rawValue)
    }

    @objc func setAttributeValue(_ attribute: String, value: Any) -> Bool {
        let attr = UIElement.Attribute(rawValue: attribute)

        do {
            try element.setAttribute(attr, value: unbridgeValue(value))
            return true
        } catch {
            AKError("Failed to set attribute \(attribute): \(error.localizedDescription)")
            return false
        }
    }

    @objc func isAttributeSettable(_ attribute: String) -> Bool {
        let attr = UIElement.Attribute(rawValue: attribute)

        do {
            return try element.attributeIsSettable(attr)
        } catch {
            return false
        }
    }

    // MARK: - Actions

    @objc func actionNames() -> [String] {
        do {
            let actions = try element.actions()
            return actions.map { $0.rawValue }
        } catch {
            AKError("Failed to get action names: \(error.localizedDescription)")
            return []
        }
    }

    @objc func performAction(_ action: String) -> Bool {
        let act = UIElement.Action(rawValue: action)

        do {
            try element.performAction(act)
            return true
        } catch {
            AKError("Failed to perform action \(action): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Utility

    @objc var pid: Int {
        let pid = try? Int(element.pid())
        return pid ?? -1
    }

    private func bridgeValue(_ value: Any) -> Any {
        if let uiElement = value as? UIElement {
            return HSAXElement(element: uiElement)
        }
        if let elements = value as? [UIElement] {
            return elements.map { HSAXElement(element: $0) }
        }
        if let point = value as? CGPoint {
            return point.toBridge()
        }
        if let size = value as? CGSize {
            return size.toBridge()
        }
        if let rect = value as? CGRect {
            return rect.toBridge()
        }
        if let values = value as? [Any] {
            return values.map { bridgeValue($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { bridgeValue($0) }
        }
        return value
    }

    private func unbridgeValue(_ value: Any) -> Any {
        if let element = value as? HSAXElement {
            return element.element
        }
        if let elements = value as? [HSAXElement] {
            return elements.map { $0.element }
        }
        if let point = value as? HSPoint {
            return point.point
        }
        if let size = value as? HSSize {
            return size.size
        }
        if let rect = value as? HSRect {
            return rect.rect
        }
        if let values = value as? [Any] {
            return values.map { unbridgeValue($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { unbridgeValue($0) }
        }
        return value
    }
}
