//
//  NSRunningApplication.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 17/10/2025.
//

import Foundation
import JavaScriptCore
import Cocoa

extension NSRunningApplication {
    func asHSApplication() -> HSApplication? {
        return AXObjectCache.shared.application(for: self)
    }
}
