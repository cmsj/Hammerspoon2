//
//  JSConvertible.swift
//  HammerspoonSDK
//
//  Created by Chris Jones on 04/11/2025.
//

import Foundation
import JavaScriptCore

/// A Swift value type that has an equivalent JSExport class, so it can be passed to and from
/// JavaScript. For example, `CGPoint` converts to and from ``HSPoint``.
public protocol JSConvertible {
    /// The JSExport class that represents the value in JavaScript
    associatedtype BridgeType: NSObject

    /// Creates the value from its JavaScript representation.
    /// - Parameter bridge: The JavaScript representation
    init(from bridge: BridgeType)

    /// Creates the value's JavaScript representation.
    /// - Returns: The JavaScript representation
    func toBridge() -> BridgeType
}
