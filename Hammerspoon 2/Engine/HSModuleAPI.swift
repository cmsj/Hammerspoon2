//
//  ModuleAPI.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 27/09/2025.
//

import Foundation
import JavaScriptCore

@_documentation(visibility: private)
@objc protocol HSModuleAPI: JSExport {
    @objc var moduleName: String { get }
    @objc var engineID: UUID { get }
    init(engineID: UUID)
    func shutdown()

    // Drives console.log()/String()/template-literal output in JS. JSExport's default
    // toString() just yields "[object ClassName]", so every conformer must provide its
    // own human-readable rendering.
    @objc func toString() -> String
}
