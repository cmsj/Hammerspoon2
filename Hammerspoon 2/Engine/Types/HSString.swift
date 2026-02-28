//
//  HSString.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 28/02/2026.
//

import Foundation
import JavaScriptCore
import Combine

// ---------------------------------------------------------------
// MARK: - Bridge Class (JavaScript Interface)
// ---------------------------------------------------------------

/// A reactive string container. Pass to `.text()` to get automatic
/// re-renders when `.set()` is called from JavaScript.
@objc protocol HSStringAPI: HSTypeAPI, JSExport {
    /// The current string value
    @objc var value: String { get }

    /// Update the string value, triggering a re-render if bound to a UI element
    /// - Parameter newValue: The new string
    @objc func set(_ newValue: String)
}

@objc class HSString: NSObject, HSStringAPI, ObservableObject {
    @objc var typeName = "HSString"

    @objc private(set) var value: String {
        willSet { objectWillChange.send() }
    }

    init(value: String) {
        self.value = value
        super.init()
    }

    @objc func set(_ newValue: String) {
        value = newValue
    }

    // MARK: - Helper

    /// Create an HSString from a JSValue (supports raw JS strings or HSString objects)
    static func fromJSValue(_ jsValue: JSValue) -> HSString? {
        if jsValue.isString, let str = jsValue.toString() {
            return HSString(value: str)
        } else if let hsString = jsValue.toObjectOf(HSString.self) as? HSString {
            return hsString
        }
        return nil
    }
}
