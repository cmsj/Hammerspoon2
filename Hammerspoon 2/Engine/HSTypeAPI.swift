//
//  HSTypeAPI.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 11/12/2025.
//

import Foundation
import JavaScriptCore

@_documentation(visibility: private)
@objc protocol HSTypeAPI: JSExport {
    @objc var typeName: String { get }

    // Drives console.log()/String()/template-literal output in JS. JSExport's default
    // toString() just yields "[object ClassName]", so every conformer must provide its
    // own human-readable rendering.
    @objc func toString() -> String
}
