//
//  Optional.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 23/10/2026.
//

import Foundation

extension Optional {
    /// The wrapped value, or `NSNull` if there isn't one. A `[String: Any]` can't hold `nil`,
    /// and `NSNull` bridges to JavaScript as `null`, so use this when building dictionaries for JS.
    var orNSNull: Any {
        map { $0 as Any } ?? NSNull()
    }
}
