//
//  Console.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 08/10/2025.
//

import Foundation
import JavaScriptCore
import AppKit

@objc protocol HSConsoleAPI: JSExport {
    @objc func open()
    @objc func close()
}

@_documentation(visibility: private)
@objc class HSConsole: NSObject, HSModuleAPI, HSConsoleAPI {
    var name = "hs.console"

    override required init() { super.init() }
    func shutdown() {}
    deinit {
        print("Deinit of \(name)")
    }

    @objc func open() {
        if let url = URL(string:"hammerspoon2://openConsole") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func close() {
        if let url = URL(string:"hammerspoon2://closeConsole") {
            NSWorkspace.shared.open(url)
        }
    }
}

