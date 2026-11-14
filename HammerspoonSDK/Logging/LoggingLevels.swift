//
//  HammerspoonLogType.swift
//  HammerspoonSDK
//
//  Created by Chris Jones on 31/08/2026.
//

/// The kinds of entry in the Hammerspoon 2 Console, from least to most severe, followed by the
/// output of scripts.
nonisolated public enum HammerspoonLogType: Int, CaseIterable, Identifiable, Sendable {
    // Raw values are deliberately spaced out so future cases can be inserted
    // without reshuffling the severity ordering (or persisted @AppStorage values)
    // of existing cases.
    /// Object lifecycle events, logged with ``AKGarbage(_:)``
    case Garbage = 0
    /// Debugging and trace events, logged with ``AKDebug(_:)``
    case Debug = 10
    /// Useful information, logged with ``AKInfo(_:)``
    case Info = 20
    /// Recoverable problems, logged with ``AKWarning(_:)``
    case Warning = 30
    /// Unrecoverable failures, logged with ``AKError(_:)``
    case Error = 40
    /// Output from JavaScript's `console`
    case Console = 50
    /// Console autocompletion results
    case Autocomplete = 60

    public var id: Self { self }

    /// The kind's name, as the Console shows it
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
