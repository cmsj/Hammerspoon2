//
//  Permissions.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 17/10/2025.
//

import Foundation
import JavaScriptCore

@objc protocol HSPermissionsAPI: JSExport {
    @objc func checkAccessibility() -> Bool
    @objc func requestAccessibility()
}

@_documentation(visibility: private)
@objc class HSPermissions: NSObject, HSModuleAPI, HSPermissionsAPI {
    var name = "hs.permissions"

    override required init() {}
    func shutdown() {}
    deinit {
        print("Deinit of \(name)")
    }

    @objc func checkAccessibility() -> Bool {
        return PermissionsManager.shared.check(.accessibility) == .trusted
    }

    @objc func requestAccessibility() {
        PermissionsManager.shared.request(.accessibility)
    }
}
