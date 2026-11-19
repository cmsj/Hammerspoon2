//
//  HammerspoonLogType.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 31/08/2026.
//

@_documentation(visibility: private)
enum HammerspoonLogType: Int, CaseIterable, Identifiable {
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

    var id: Self { self }

    /// Parses a level name, as typed by a user (e.g. `hs2 --log warning`, or `hs.consoleHistory()`'s `minimumLevel`)
    nonisolated init?(string: String) {
        switch string.lowercased() {
        case "garbage":                     self = .Garbage
        case "debug":                       self = .Debug
        case "info":                        self = .Info
        case "warning", "warn":             self = .Warning
        case "error":                       self = .Error
        case "javascript", "console", "js": self = .Console
        default: return nil
        }
    }

    /// The level's name as JavaScript sees it, e.g. in `hs.consoleHistory()`'s results
    nonisolated var jsName: String {
        switch self {
        case .Garbage: return "garbage"
        case .Debug: return "debug"
        case .Info: return "info"
        case .Warning: return "warning"
        case .Error: return "error"
        case .Console: return "javascript"
        case .Autocomplete: return "autocomplete"
        }
    }
    var asString: String {
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
