//
//  HSOSAScriptShared.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 03/03/2026.
//

// This is for data that needs to be shared between the HammerspoonOSAScriptHelper XPC helper, and Hammerspoon itself
// This file is compiled into both binaries.

let HSOSAScriptServiceName = "net.tenshu.Hammerspoon-2.HammerspoonOSAScriptHelper"

nonisolated struct HSOSARequest: Codable {
    let language: String
    let source: String
}

nonisolated struct HSOSAResponse: Codable {
    let success: Bool
    let rawMessage: String
    let jsonMessage: String?
}
