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

@objc class HSPermissions: NSObject, HSModule, HSPermissionsAPI {
    @objc var name = "Permissions"

    required override init() {}

    @objc func checkAccessibility() -> Bool {
        return PermissionsManager.shared.check(.accessibility) == .trusted
    }

    @objc func requestAccessibility() {
        PermissionsManager.shared.request(.accessibility)
    }
}
