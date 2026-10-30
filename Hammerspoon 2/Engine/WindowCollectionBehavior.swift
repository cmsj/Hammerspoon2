//
//  WindowCollectionBehavior.swift
//  Hammerspoon 2
//

import AppKit
import JavaScriptCore

/// The `NSWindow.CollectionBehavior` names shared by the modules that make their own windows
/// (`hs.canvas`, `hs.ui`), and the validation they all need before assigning one.
enum WindowCollectionBehavior {
    /// Every behavior name scripts can use, mapped to its flag
    static let named: [String: NSWindow.CollectionBehavior] = [
        "default": [],
        "canJoinAllSpaces": .canJoinAllSpaces,
        "moveToActiveSpace": .moveToActiveSpace,
        "managed": .managed,
        "transient": .transient,
        "stationary": .stationary,
        "participatesInCycle": .participatesInCycle,
        "ignoresCycle": .ignoresCycle,
        "fullScreenPrimary": .fullScreenPrimary,
        "fullScreenAuxiliary": .fullScreenAuxiliary,
        "fullScreenNone": .fullScreenNone,
        "fullScreenAllowsTiling": .fullScreenAllowsTiling,
        "fullScreenDisallowsTiling": .fullScreenDisallowsTiling,
    ]

    /// Groups of names AppKit documents as mutually exclusive. Assigning both of
    /// canJoinAllSpaces and moveToActiveSpace raises an NSInternalInconsistencyException that
    /// nothing catches, so it kills the app; the other groups are accepted but meaningless.
    static let exclusiveGroups: [[String]] = [
        ["canJoinAllSpaces", "moveToActiveSpace"],
        ["managed", "transient", "stationary"],
        ["participatesInCycle", "ignoresCycle"],
        ["fullScreenPrimary", "fullScreenAuxiliary", "fullScreenNone"],
        ["fullScreenAllowsTiling", "fullScreenDisallowsTiling"],
    ]

    /// Combines behavior names into one behavior, logging and skipping unknown names
    /// - Parameters:
    ///   - names: Names from `named`
    ///   - caller: Prefix for the log message, e.g. `"hs.canvas"`
    /// - Returns: The union of the known names' flags
    static func combining(_ names: [String], caller: String) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = []
        for name in names {
            if let value = named[name] {
                behavior.insert(value)
            } else {
                AKWarning("\(caller): Unknown window behavior '\(name)', ignoring it")
            }
        }
        return behavior
    }

    /// Describes the first mutually exclusive pair of flags set in a behavior
    /// - Parameter behavior: The behavior to check
    /// - Returns: A message naming the conflicting flags, or nil if there are none
    static func conflict(in behavior: NSWindow.CollectionBehavior) -> String? {
        for group in exclusiveGroups {
            let present = group.filter { behavior.contains(named[$0]!) }
            if present.count > 1 {
                return "'\(present[0])' and '\(present[1])' cannot be combined"
            }
        }
        return nil
    }

    /// Checks a behavior is safe to assign to a window, raising a JS `Error` in the calling
    /// context if it isn't (Swift `throws` doesn't bridge to JSExport)
    /// - Parameters:
    ///   - behavior: The behavior about to be assigned
    ///   - caller: Prefix for the error message, e.g. `"hs.canvas"`
    /// - Returns: true if the behavior can be assigned
    static func validate(_ behavior: NSWindow.CollectionBehavior, caller: String) -> Bool {
        guard let conflict = conflict(in: behavior) else { return true }
        let message = "\(caller): Invalid window behavior: \(conflict)"
        if let ctx = JSContext.current(), let error = JSValue(newErrorFromMessage: message, in: ctx) {
            ctx.exception = error
        } else {
            AKError(message)
        }
        return false
    }
}
