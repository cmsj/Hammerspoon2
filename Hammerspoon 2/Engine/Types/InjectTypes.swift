//
//  InjectTypes.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 04/11/2025.
//

import Foundation
import JavaScriptCore

extension JSContext {
    /// Registers all bridge types so JS can use them
    func injectTypeBridges() {
        let typeBridges = [
            "HSPoint": HSPoint.self,
            "HSSize":  HSSize.self,
            "HSRect":  HSRect.self
        ]

        typeBridges.forEach { key, value in
            setObject(value, forKeyedSubscript: key as NSString)
        }
    }
}
