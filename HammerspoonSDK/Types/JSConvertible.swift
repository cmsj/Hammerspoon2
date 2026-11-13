//
//  JSConvertible.swift
//  HammerspoonSDK
//
//  Created by Chris Jones on 04/11/2025.
//

import Foundation
import JavaScriptCore

public protocol JSConvertible {
    associatedtype BridgeType: NSObject
    init(from bridge: BridgeType)
    func toBridge() -> BridgeType
}
