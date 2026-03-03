//
//  HSOSAScriptModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - JavaScript API

/// Run AppleScript and OSA JavaScript from Hammerspoon scripts.
///
/// **WARNING**: hs.osascript is UNSAFE to use on 
/// Script execution is isolated in a separate XPC helper process
/// (`HammerspoonOSAScriptHelper`). If a script crashes or deadlocks, only the
/// helper is affected — the main app remains stable and the next call
/// reconnects automatically.
///
/// ## Return value
///
/// Every function returns a `Promise` that **always resolves** (never rejects)
/// with an object containing three fields:
///
/// | Field | Type | Description |
/// |-------|------|-------------|
/// | `success` | `Boolean` | `true` if the script ran without error |
/// | `result` | `any` | Parsed return value of the script, or `null` on failure |
/// | `raw` | `String` | Raw string representation of the result, or the error message on failure |
///
/// The `result` field is typed based on what the script returned: strings,
/// numbers, booleans, lists, and records are all mapped to their JavaScript
/// equivalents. `null` is used for AppleScript's `missing value` and for any
/// failure case.
///
/// ## Examples
///
/// **Return a string:**
/// ```javascript
/// hs.osascript.applescript('return "hello"')
///   .then(r => console.log(r.result));  // "hello"
/// ```
///
/// **Return a number:**
/// ```javascript
/// hs.osascript.applescript('return 42')
///   .then(r => console.log(r.result));  // 42
/// ```
///
/// **Interact with an application:**
/// ```javascript
/// hs.osascript.applescript('tell application "Finder" to get name of home')
///   .then(r => console.log(r.result));  // e.g. "cmsj"
/// ```
///
/// **Handle errors (the Promise never rejects — check `success`):**
/// ```javascript
/// hs.osascript.applescript('this is not valid')
///   .then(r => {
///     if (!r.success) console.log("Error:", r.raw);
///   });
/// ```
///
/// **OSA JavaScript:**
/// ```javascript
/// hs.osascript.javascript('Application("Finder").name()')
///   .then(r => console.log(r.result));  // "Finder"
/// ```
///
/// **Run a script from a file:**
/// ```javascript
/// hs.osascript.applescriptFromFile('/Users/me/scripts/notify.applescript')
///   .then(r => console.log(r.success));
/// ```
@objc protocol HSOSAScriptModuleAPI: JSExport {
    /// Run an AppleScript source string.
    ///
    /// - Parameter source: The AppleScript source code to compile and execute.
    /// - Returns: A `Promise` resolving to `{ success, result, raw }`.
    @objc func applescript(_ source: String) -> JSPromise?

    /// Run an OSA JavaScript source string.
    ///
    /// OSA JavaScript is Apple's Open Scripting Architecture dialect of
    /// JavaScript, distinct from the JavaScriptCore engine that runs
    /// Hammerspoon scripts themselves.
    ///
    /// - Parameter source: The OSA JavaScript source code to compile and execute.
    /// - Returns: A `Promise` resolving to `{ success, result, raw }`.
    @objc func javascript(_ source: String) -> JSPromise?

    /// Read a file from disk and execute its contents as AppleScript.
    ///
    /// The file is read in the main process before being sent to the XPC
    /// helper. If the file cannot be read the promise resolves immediately
    /// with `{ success: false, result: null, raw: "Failed to read file: <path>" }`.
    ///
    /// - Parameter path: Absolute path to the AppleScript source file.
    /// - Returns: A `Promise` resolving to `{ success, result, raw }`.
    @objc func applescriptFromFile(_ path: String) -> JSPromise?

    /// Read a file from disk and execute its contents as OSA JavaScript.
    ///
    /// The file is read in the main process before being sent to the XPC
    /// helper. If the file cannot be read the promise resolves immediately
    /// with `{ success: false, result: null, raw: "Failed to read file: <path>" }`.
    ///
    /// - Parameter path: Absolute path to the OSA JavaScript source file.
    /// - Returns: A `Promise` resolving to `{ success, result, raw }`.
    @objc func javascriptFromFile(_ path: String) -> JSPromise?

    /// Low-level execution entry point used by the higher-level helpers.
    ///
    /// Prefer `applescript()` or `javascript()` over calling this directly.
    ///
    /// - Parameters:
    ///   - source: The script source code.
    ///   - language: The OSA language name — must be `"AppleScript"` or `"JavaScript"`.
    /// - Returns: A `Promise` resolving to `{ success, result, raw }`.
    @objc func _execute(_ source: String, _ language: String) -> JSPromise?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSOSAScriptModule: NSObject, HSModuleAPI, HSOSAScriptModuleAPI {
    var name = "hs.osascript"

    private let runner = HSOSAScriptRunner()

    // MARK: - Module lifecycle

    override required init() { super.init() }

    func shutdown() {
        runner.shutdown()
    }

    deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Public API

    @objc func applescript(_ source: String) -> JSPromise? {
        return _execute(source, "AppleScript")
    }

    @objc func javascript(_ source: String) -> JSPromise? {
        return _execute(source, "JavaScript")
    }

    @objc func applescriptFromFile(_ path: String) -> JSPromise? {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            return resolvedFailurePromise(raw: "Failed to read file: \(path)")
        }
        return _execute(source, "AppleScript")
    }

    @objc func javascriptFromFile(_ path: String) -> JSPromise? {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            return resolvedFailurePromise(raw: "Failed to read file: \(path)")
        }
        return _execute(source, "JavaScript")
    }

    @objc func _execute(_ source: String, _ language: String) -> JSPromise? {
        guard let context = JSContext.current() else {
            AKError("hs.osascript: _execute called outside a JS context")
            return nil
        }

        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                let resultDict: [String: Any]
                do {
                    let (success, resultJSON, raw) = try await self.runner.run(
                        source: source, language: language)

                    if success {
                        let parsed = Self.parseJSON(resultJSON)
                        resultDict = ["success": true, "result": parsed, "raw": raw]
                    } else {
                        resultDict = ["success": false, "result": NSNull(), "raw": raw]
                    }
                } catch {
                    resultDict = [
                        "success": false,
                        "result": NSNull(),
                        "raw": "XPC error: \(error.localizedDescription)"
                    ]
                }
                holder.resolveWith(resultDict)
            }
        }
    }

    // MARK: - Private helpers

    /// Immediately-resolved failure promise, used for synchronous errors (e.g. file not found).
    private func resolvedFailurePromise(raw: String) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let result: [String: Any] = ["success": false, "result": NSNull(), "raw": raw]
        return context.createResolvedPromise(with: result)
    }

    /// Deserialise a JSON string into a JS-compatible value.
    /// Returns `NSNull()` if the string is nil or unparseable.
    private static func parseJSON(_ jsonString: String?) -> Any {
        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(
                  with: data, options: [.fragmentsAllowed]) else {
            return NSNull()
        }
        return parsed
    }
}
