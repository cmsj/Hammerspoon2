//
//  JSFunction.swift
//  Hammerspoon 2
//

import JavaScriptCore

/// A type alias for JSValue representing a JavaScript function parameter.
/// Using JSFunction (instead of JSValue) in @objc protocol signatures signals
/// to callers and documentation tooling that a callable JS value is expected.
typealias JSFunction = JSValue
