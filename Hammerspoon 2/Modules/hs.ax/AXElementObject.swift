//
//  AXElementObject.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import AXSwift

/// Object representing an Accessibility element
@objc protocol HSAXElementAPI: JSExport {
    // MARK: - Basic Properties

    /// The element's role (e.g., "AXWindow", "AXButton")
    @objc var role: String? { get }

    /// The element's subrole
    @objc var subrole: String? { get }

    /// The element's title
    @objc var title: String? { get }

    /// The element's value
    @objc var value: Any? { get }

    /// The element's description
    @objc var elementDescription: String? { get }

    /// Whether the element is enabled
    @objc var isEnabled: Bool { get }

    /// Whether the element is focused
    @objc var isFocused: Bool { get set }

    // MARK: - Geometry

    /// The element's position on screen
    @objc var position: HSPoint? { get set }

    /// The element's size
    @objc var size: HSSize? { get set }

    /// The element's frame (position and size combined)
    @objc var frame: HSRect? { get set }

    // MARK: - Hierarchy

    /// The element's parent
    @objc var parent: HSAXElement? { get }

    /// The element's children
    @objc func children() -> [HSAXElement]

    /// Get a specific child by index
    @objc func childAtIndex(_ index: Int) -> HSAXElement?

    // MARK: - Attributes

    /// Get all available attribute names
    @objc func attributeNames() -> [String]

    /// Get the value of a specific attribute
    @objc func attributeValue(_ attribute: String) -> Any?

    /// Set the value of a specific attribute
    @objc func setAttributeValue(_ attribute: String, value: Any) -> Bool

    /// Check if an attribute is settable
    @objc func isAttributeSettable(_ attribute: String) -> Bool

    // MARK: - Actions

    /// Get all available action names
    @objc func actionNames() -> [String]

    /// Perform a specific action
    @objc func performAction(_ action: String) -> Bool

    // MARK: - Utility

    /// Get the process ID of the application that owns this element
    @objc var pid: Int { get }
}

@_documentation(visibility: private)
@objc class HSAXElement: NSObject, HSAXElementAPI {
    let element: UIElement

    init(element: UIElement) {
        self.element = element
        super.init()
    }

    isolated deinit {
        AKTrace("deinit of HSAXElement: \(self.role ?? "unknown")")
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
        return try? element.attribute(.value)
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
        guard let childElements: [UIElement] = try? element.attribute(.children) else {
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
        return try? element.getMultipleAttributes([attr]).first?.value
    }

    @objc func setAttributeValue(_ attribute: String, value: Any) -> Bool {
        let attr = UIElement.Attribute(rawValue: attribute)

        do {
            try element.setAttribute(attr, value: value)
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
}
