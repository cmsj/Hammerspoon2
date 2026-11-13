//
//  HammerspoonLogType.swift
//  HammerspoonSDK
//
//  Created by Chris Jones on 31/08/2026.
//

@_documentation(visibility: private)
nonisolated public enum HammerspoonLogType: Int, CaseIterable, Identifiable, Sendable {
    // Raw values are deliberately spaced out so future cases can be inserted
    // without reshuffling the severity ordering (or persisted @AppStorage values)
    // of existing cases.
    case Garbage = 0
    case Debug = 10
    case Info = 20
    case Warning = 30
    case Error = 40
    case Console = 50
    case Autocomplete = 60

    public var id: Self { self }
    public var asString: String {
        switch self {
        case .Garbage:
            return "Garbage"
        case .Debug:
            return "Debug"
        case .Info:
            return "Info"
        case .Warning:
            return "Warning"
        case .Error:
            return "Error"
        case .Console:
            return "JavaScript"
        case .Autocomplete:
            return "Autocomplete"
        }
    }
}
