//
//  AlertObject.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/11/2025.
//

import Foundation
import JavaScriptCore
import SwiftUI

/// An object for use with hs.alert API
@objc protocol HSAlertAPI: HSTypeAPI, JSExport {
    /// The message to display in an alert
    @objc var message: String { get set }
    /// How many seconds the alert should be shown for
    @objc var expire: Int { get set }
    /// An HSFont describing the font to use in the alert
    @objc var font: HSFont { get set }
    /// How many points of padding to use in the alert
    @objc var padding: Int { get set }
}

@objc class HSAlert: NSObject, HSAlertAPI {
    @objc var typeName = "HSAlert"

    @objc var message: String = ""
    @objc var expire: Int = 5
    @objc var font: HSFont = HSFont.body()
    @objc var padding: Int = -1

    var swiftUIPadding: CGFloat? {
        guard padding >= 0 else {
            return nil
        }
        return CGFloat(padding)
    }

    var swiftUIFont: Font {
        return font.font
    }
}
