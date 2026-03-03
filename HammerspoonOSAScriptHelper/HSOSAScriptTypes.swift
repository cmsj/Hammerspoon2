//
//  HSOSAScriptLanguage.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 03/03/2026.
//

nonisolated struct HSOSARequest: Codable {
    let language: String
    let source: String
}

nonisolated struct HSOSAResponse: Codable {
    let success: Bool
    let rawMessage: String
    let jsonMessage: String?
}
