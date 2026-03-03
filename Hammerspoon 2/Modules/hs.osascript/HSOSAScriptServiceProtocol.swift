//
//  HSOSAScriptServiceProtocol.swift
//  Hammerspoon 2
//
//  NOTE: This file is linked into both Hammerspoon 2 and its OSAScript XPC helper
//

import Foundation

/// XPC protocol for communicating with the OSAScript helper process.
///
/// Each call gets a fresh XPC connection for maximum isolation: if a script
/// crashes or deadlocks the helper, only that helper process is affected.
/// The next call transparently spawns a new one.
@objc protocol HSOSAScriptServiceProtocol: NSObjectProtocol {
    /// Execute an OSA script and return the result via reply block.
    ///
    /// - Parameters:
    ///   - source: The script source code.
    ///   - language: The OSA language name, e.g. `"AppleScript"` or `"JavaScript"`.
    ///   - reply: Called exactly once with:
    ///     - On success: `(true, jsonString, rawString)` where `jsonString` is the
    ///       JSON-serialised result and `rawString` is `result.stringValue`.
    ///     - On failure: `(false, nil, errorMessage)`.
    func execute(source: String,
                 language: String,
                 withReply reply: @escaping (Bool, String?, String?) -> Void)
}
