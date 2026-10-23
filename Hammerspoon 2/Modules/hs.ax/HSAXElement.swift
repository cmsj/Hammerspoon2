//
//  AXElementObject.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import ApplicationServices
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
    ///
    /// The value must be of the type the Accessibility API expects for the attribute. For the
    /// well-known attributes below the type is checked first, and a value of the wrong type throws
    /// an error naming the expected type.
    ///
    /// | Attribute | Expected value |
    /// |---|---|
    /// | `AXPosition` | an `HSPoint` |
    /// | `AXSize` | an `HSSize` |
    /// | `AXFrame` | an `HSRect` |
    /// | `AXFocused`, `AXMain`, `AXMinimized`, `AXHidden`, `AXFrontmost`, `AXFullScreen`, `AXSelected`, `AXExpanded`, `AXDisclosing`, `AXEnhancedUserInterface` | a boolean |
    /// | `AXSelectedText` | a string |
    ///
    /// Plain objects such as `{x: 1, y: 2}` are not accepted for geometry attributes; use `new HSPoint(1, 2)`.
    ///
    /// If the Accessibility API refuses the change, this throws an `Error` whose message says why, and whose
    /// `code` property is the Accessibility error's name, e.g. `"kAXErrorAttributeUnsupported"` (the element
    /// doesn't have the attribute), `"kAXErrorIllegalArgument"` (the value isn't valid for it) or
    /// `"kAXErrorCannotComplete"` (the application didn't respond). A value of the wrong type for one of
    /// the attributes above throws an `Error` with no `code`.
    /// - Parameters:
    ///   - attribute: The attribute name to set
    ///   - value: {any} The value to set
    /// - Returns: `true` if the attribute was set. Failures throw rather than returning `false`.
    /// - Throws: true
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// el.setAttributeValue("AXValue", "Hello")
    ///
    /// const win = hs.ax.windowElement(hs.window.focusedWindow())
    /// win.setAttributeValue("AXPosition", new HSPoint(100, 100))
    /// win.setAttributeValue("AXSize", new HSSize(800, 600))
    ///
    /// try {
    ///     win.setAttributeValue("AXFullScreen", true)
    /// } catch (err) {
    ///     console.error(err.message, err.code)
    /// }
    /// ```
    @objc func setAttributeValue(_ attribute: String, _ value: JSValue) -> Bool

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
    ///
    /// If the Accessibility API refuses the action, this throws an `Error` whose message says why, and whose
    /// `code` property is the Accessibility error's name, e.g. `"kAXErrorActionUnsupported"` or
    /// `"kAXErrorAttributeUnsupported"` (the element doesn't have the action; AppKit applications report the
    /// latter) or `"kAXErrorCannotComplete"` (the application didn't respond). Use `actionNames()` to see
    /// which actions an element supports.
    /// - Parameter action: The action to perform
    /// - Returns: `true` if the action was performed. Failures throw rather than returning `false`.
    /// - Throws: true
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// try {
    ///     el.performAction("AXPress")
    /// } catch (err) {
    ///     console.error(err.message, err.code)
    /// }
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

    /// Test whether this element and another refer to the same underlying accessibility object
    /// - Parameter other: Another HSAXElement to compare against
    /// - Returns: True if both objects represent the same underlying accessibility element
    /// - Example:
    /// ```js
    /// const el1 = hs.ax.focusedElement()
    /// const el2 = hs.ax.focusedElement()
    /// console.log(el1.isEqualToElement(el2)) // true, assuming focus hasn't changed
    /// ```
    @objc func isEqualToElement(_ other: HSAXElement) -> Bool
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
        AKGarbage("deinit of HSAXElement: \(self.role ?? "unknown")")
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

    @objc func setAttributeValue(_ attribute: String, _ value: JSValue) -> Bool {
        if let expected = AXAttributeValueType.known[attribute], !expected.accepts(value) {
            throwJSError("hs.ax setAttributeValue(): \(attribute) requires \(expected.typeDescription), got \(AXAttributeValueType.describe(value))")
            return false
        }
        guard !value.isNull, let object = value.toObject() else {
            throwJSError("hs.ax setAttributeValue(): \(attribute) can't be set to \(AXAttributeValueType.describe(value))")
            return false
        }
        let attr = UIElement.Attribute(rawValue: attribute)

        do {
            try element.setAttribute(attr, value: unbridgeValue(object))
            return true
        } catch {
            throwJSError("hs.ax setAttributeValue(): failed to set \(attribute): \(error.explanation) (\(error.constantName))",
                         code: error.constantName)
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
            // AppKit reports an action an element doesn't have as kAXErrorAttributeUnsupported, so explain
            // that as the action being unsupported, but keep the real error name for scripts to check.
            let explanation = error == .attributeUnsupported ? AXError.actionUnsupported.explanation : error.explanation
            throwJSError("hs.ax performAction(): failed to perform \(action): \(explanation) (\(error.constantName))",
                         code: error.constantName)
            return false
        }
    }

    /// Raise a JS `Error` in the calling context, since Swift `throws` doesn't bridge to JSExport.
    /// `code`, if given, is set as the error's `code` property so scripts can branch on it.
    private func throwJSError(_ message: String, code: String? = nil) {
        guard let ctx = JSContext.current(), let error = JSValue(newErrorFromMessage: message, in: ctx) else {
            AKError(message)
            return
        }
        if let code {
            error.setValue(code, forProperty: "code")
        }
        ctx.exception = error
    }

    // MARK: - Utility

    @objc var pid: Int {
        let pid = try? Int(element.pid())
        return pid ?? -1
    }

    @objc func isEqualToElement(_ other: HSAXElement) -> Bool {
        return element == other.element
    }

    private func bridgeValue(_ value: Any) -> Any {
        if let uiElement = value as? UIElement {
            return HSAXElement(element: uiElement)
        }
        if let elements = value as? [UIElement] {
            return elements.map { HSAXElement(element: $0) }
        }
        // AXSwift's getMultipleAttributes() only unwraps a raw AXUIElement into its
        // UIElement wrapper for scalar attributes (e.g. AXParent). For array-valued
        // attributes (e.g. AXChildren, AXWindows) the elements are left as raw,
        // untyped AXUIElement CFTypeRefs, which don't match `UIElement` above. Detect
        // that case directly so both scalar and array element-valued attributes bridge
        // correctly; the [Any] branch below then recurses into arrays and hits this.
        let cfValue = value as CFTypeRef
        if CFGetTypeID(cfValue) == AXUIElementGetTypeID() {
            return HSAXElement(element: UIElement(cfValue as! AXUIElement))
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

/// The value types the Accessibility API requires for well-known settable attributes, so that
/// setAttributeValue() can reject a mistyped value with a useful error instead of the API's bare
/// failure (e.g. a plain `{x, y}` object for AXPosition, which bridges to a dictionary).
private enum AXAttributeValueType {
    case point, size, rect, boolean, string

    static let known: [String: AXAttributeValueType] = {
        var types: [String: AXAttributeValueType] = [
            "AXPosition": .point,
            "AXSize": .size,
            "AXFrame": .rect,
            "AXSelectedText": .string,
        ]
        for attribute in ["AXFocused", "AXMain", "AXMinimized", "AXHidden", "AXFrontmost", "AXFullScreen",
                          "AXSelected", "AXExpanded", "AXDisclosing", "AXEnhancedUserInterface"] {
            types[attribute] = .boolean
        }
        return types
    }()

    var typeDescription: String {
        switch self {
        case .point: return "an HSPoint, e.g. new HSPoint(x, y)"
        case .size: return "an HSSize, e.g. new HSSize(w, h)"
        case .rect: return "an HSRect, e.g. new HSRect(x, y, w, h)"
        case .boolean: return "a boolean"
        case .string: return "a string"
        }
    }

    func accepts(_ value: JSValue) -> Bool {
        switch self {
        case .point: return value.toObjectOf(HSPoint.self) is HSPoint
        case .size: return value.toObjectOf(HSSize.self) is HSSize
        case .rect: return value.toObjectOf(HSRect.self) is HSRect
        case .boolean: return value.isBoolean
        case .string: return value.isString
        }
    }

    /// A short description of a value's type for error messages, naming bridged types (e.g. "HSSize")
    static func describe(_ value: JSValue) -> String {
        if value.isUndefined { return "undefined" }
        if value.isNull { return "null" }
        if value.isBoolean { return "a boolean" }
        if value.isNumber { return "a number" }
        if value.isString { return "a string" }
        if value.isArray { return "an array" }
        if let typed = value.toObject() as? HSTypeAPI { return "an \(typed.typeName)" }
        return "a plain object"
    }
}

/// Names and plain-language explanations of Accessibility API errors, for the JS errors that
/// setAttributeValue() and performAction() throw.
private extension AXError {
    /// The error's constant name from AXError.h, e.g. "kAXErrorAttributeUnsupported"
    var constantName: String {
        switch self {
        case .success: return "kAXErrorSuccess"
        case .failure: return "kAXErrorFailure"
        case .illegalArgument: return "kAXErrorIllegalArgument"
        case .invalidUIElement: return "kAXErrorInvalidUIElement"
        case .invalidUIElementObserver: return "kAXErrorInvalidUIElementObserver"
        case .cannotComplete: return "kAXErrorCannotComplete"
        case .attributeUnsupported: return "kAXErrorAttributeUnsupported"
        case .actionUnsupported: return "kAXErrorActionUnsupported"
        case .notificationUnsupported: return "kAXErrorNotificationUnsupported"
        case .notImplemented: return "kAXErrorNotImplemented"
        case .notificationAlreadyRegistered: return "kAXErrorNotificationAlreadyRegistered"
        case .notificationNotRegistered: return "kAXErrorNotificationNotRegistered"
        case .apiDisabled: return "kAXErrorAPIDisabled"
        case .noValue: return "kAXErrorNoValue"
        case .parameterizedAttributeUnsupported: return "kAXErrorParameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "kAXErrorNotEnoughPrecision"
        @unknown default: return "AXError(\(rawValue))"
        }
    }

    var explanation: String {
        switch self {
        case .illegalArgument: return "the Accessibility API rejected an argument as invalid"
        case .invalidUIElement: return "the element no longer exists"
        case .cannotComplete: return "the application did not respond, or refused the request"
        case .attributeUnsupported: return "the element does not support this attribute"
        case .actionUnsupported: return "the element does not support this action"
        case .notImplemented: return "the application does not implement this"
        case .apiDisabled: return "Hammerspoon does not have Accessibility permission"
        case .noValue: return "the attribute has no value"
        default: return "the Accessibility API reported an error"
        }
    }
}
