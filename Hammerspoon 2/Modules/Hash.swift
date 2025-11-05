//
//  Hashing.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 28/09/2025.
//

import Foundation
import JavaScriptCore

@objc protocol HSHashingAPI: JSExport {
    @objc func base64Encode(raw: String) -> String
    @objc func base64Decode(raw: String) -> String?
}

@_documentation(visibility: private)
@objc class HSHashing: NSObject, HSModuleAPI, HSHashingAPI {
    var name = "hs.hash"

    override required init() { super.init() }
    func shutdown() {}
    deinit {
        print("Deinit of \(name)")
    }

    @objc func base64Encode(raw: String) -> String {
        Data(raw.utf8).base64EncodedString()
    }

    @objc func base64Decode(raw: String) -> String? {
        guard let data = Data(base64Encoded: raw) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
