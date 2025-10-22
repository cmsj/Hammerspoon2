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
    init()
    func shutdown()
}
