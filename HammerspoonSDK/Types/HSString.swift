//
//  HSString.swift
//  HammerspoonSDK
//
//  Created by Claude Code on 28/02/2026.
//

import Foundation
import JavaScriptCore
import Observation

// ---------------------------------------------------------------
// MARK: - Bridge Class (JavaScript Interface)
// ---------------------------------------------------------------

/// A reactive string container. Pass to `.text()` to get automatic
/// re-renders when `.set()` is called from JavaScript.
@objc public protocol HSStringAPI: HSTypeAPI, JSExport {
    /// The current string value
    @objc var value: String { get }

    /// Update the string value, triggering a re-render if bound to a UI element
    /// - Parameter newValue: The new string
    @objc func set(_ newValue: String)
}

/// A string whose changes SwiftUI views observe, shared between Swift and JavaScript. Its
/// JavaScript API is ``HSStringAPI``.
@Observable
@objc public class HSString: NSObject, HSStringAPI {
    @objc public var typeName = "HSString"

    @objc public func toString() -> String {
        let snippet = _value.count > 40 ? String(_value.prefix(40)) + "…" : _value
        return "<\(typeName): '\(snippet)'>"
    }

    public nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // @Observable can't track @objc stored properties, so _value is the
    // Observable-tracked backing store and the @objc computed property
    // forwards to it. SwiftUI sees the dependency chain: value → _value.
    private var _value: String

    @objc public var value: String { _value }

    /// Creates a string container.
    /// - Parameter value: Its initial value
    public init(value: String) {
        self._value = value
        super.init()
    }

    @objc public func set(_ newValue: String) {
        _value = newValue
    }

    // MARK: - Helper

    /// Create an HSString from a JSValue (supports raw JS strings or HSString objects)
    public static func fromJSValue(_ jsValue: JSValue) -> HSString? {
        if jsValue.isString, let str = jsValue.toString() {
            return HSString(value: str)
        } else if let hsString = jsValue.toObjectOf(HSString.self) as? HSString {
            return hsString
        }
        return nil
    }
}
