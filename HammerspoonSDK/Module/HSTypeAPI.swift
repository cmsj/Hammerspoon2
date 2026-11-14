//
//  HSTypeAPI.swift
//  HammerspoonSDK
//
//  Created by Chris Jones on 11/12/2025.
//

import Foundation
import JavaScriptCore

/// An object a module hands to JavaScript, such as an `HSTimer` or an `HSColor`.
@objc public protocol HSTypeAPI: JSExport {
    /// The type's name as JavaScript sees it, such as `"HSTimer"`
    @objc var typeName: String { get }

    // Drives console.log()/String()/template-literal output in JS. JSExport's default
    // toString() just yields "[object ClassName]", so every conformer must provide its
    // own human-readable rendering.
    /// A human-readable description of the object, for `console.log()` and `String()`
    /// - Returns: The description
    @objc func toString() -> String
}
