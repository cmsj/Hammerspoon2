//
//  Exceptions.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/09/2025.
//

import Foundation

@_documentation(visibility: private)
struct HammerspoonError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    enum ErrorKind: String {
        case vmCreation = "Creating JS VM"
        case jsEvalURLKind = "Invalid JS URL"
        case unknown = "Unknown"
    }

    let kind: ErrorKind
    let msg: String

    var description: String {
        localizedDescription
    }

    var localizedDescription: String {
        "\(kind.rawValue): \(msg)"
    }

    var localizedStringResource: LocalizedStringResource {
        "\(kind.rawValue): \(msg)"
    }

    init(_ kind: ErrorKind, msg: String) {
        self.kind = kind
        self.msg = msg
    }
}
