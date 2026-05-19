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
    @objc var name: String { get }
    @objc var engineID: UUID { get }
    init(engineID: UUID)
    func shutdown()
}
