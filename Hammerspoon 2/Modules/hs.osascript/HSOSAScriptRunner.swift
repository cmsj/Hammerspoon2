//
//  HSOSAScriptRunner.swift
//  Hammerspoon 2
//

import Foundation

/// Executes OSA scripts via the `HammerspoonOSAScriptHelper` XPC service.
///
/// A **fresh connection** is created for every call.  This provides maximum
/// isolation: if the helper crashes mid-execution the error handler fires and
/// the continuation is resumed with a thrown error; the next call simply
/// creates a new connection and a new helper process is launched automatically.
class HSOSAScriptRunner {

    private let serviceName = "net.tenshu.Hammerspoon-2.HammerspoonOSAScriptHelper"

    // MARK: - Public API

    /// Execute an OSA script in the helper process.
    ///
    /// - Parameters:
    ///   - source: Script source code.
    ///   - language: OSA language name (`"AppleScript"` or `"JavaScript"`).
    /// - Returns: A tuple where:
    ///   - `success` mirrors the helper's success flag.
    ///   - `resultJSON` is a JSON string of the parsed result (nil on failure).
    ///   - `raw` is `result.stringValue` on success, or the error message on failure.
    /// - Throws: Only for XPC infrastructure failures (connection refused, helper crash
    ///   before reply, etc.).  Script-level errors are returned as `(false, nil, message)`.
    func run(source: String, language: String) async throws -> (Bool, String?, String) {
        let session = try XPCSession(xpcService: serviceName, options: .inactive)
#if DEBUG
        AKWarning("OSASCRIPT XPC SERVICE RUNNING WITHOUT PEER REQUIREMENTS. This is a serious security risk, do not use this build for production.")
#else
        if #available(macOS 26.0, *) {
            AKTrace("Enforcing peer requirement for XPC connections.")
            session.setPeerRequirement(.isFromSameTeam())
        }
#endif
        try session.activate()

        return try await withCheckedThrowingContinuation { continuation in
            let message = HSOSARequest(language: language, source: source)

            do {
                try session.send(message) { result in
                    var success = false
                    var resultJSON: String? = ""
                    var raw = ""

                    switch result {
                    case let .success(result):
                        if let response = try? result.decode(as: HSOSAResponse.self) {
                            success = response.success
                            resultJSON = response.jsonMessage
                            raw = response.rawMessage
                        } else {
                            raw = "Unable to decode response"
                        }
                    case let .failure(error):
                        raw = error.localizedDescription
                    }

                    continuation.resume(returning: (success, resultJSON, raw))
                    session.cancel(reason: "OSAScriptRunner deinit")
                }
            } catch {
                continuation.resume(throwing: error)
                session.cancel(reason: "OSAScriptRunner deinit")
            }
        }
    }

    /// Execute an OSA script in the helper process synchronously.
    ///
    /// Blocks the calling thread until the helper responds.  Use only when an
    /// async context is not available; prefer `run(source:language:)` otherwise.
    ///
    /// - Parameters:
    ///   - source: Script source code.
    ///   - language: OSA language name (`"AppleScript"` or `"JavaScript"`).
    /// - Returns: A tuple where:
    ///   - `success` mirrors the helper's success flag.
    ///   - `resultJSON` is a JSON string of the parsed result (nil on failure).
    ///   - `raw` is `result.stringValue` on success, or the error message on failure.
    /// - Throws: Only for XPC infrastructure failures (connection refused, helper crash, etc.).
    ///   Script-level errors are returned as `(false, nil, message)`.
    func runSync(source: String, language: String) throws -> (Bool, String?, String) {
        let session = try XPCSession(xpcService: serviceName, options: .inactive)
#if DEBUG
        AKWarning("OSASCRIPT XPC SERVICE RUNNING WITHOUT PEER REQUIREMENTS. This is a serious security risk, do not use this build for production.")
#else
        if #available(macOS 26.0, *) {
            AKTrace("Enforcing peer requirement for XPC connections.")
            session.setPeerRequirement(.isFromSameTeam())
        }
#endif
        try session.activate()
        defer { session.cancel(reason: "OSAScriptRunner.runSync completed") }

        let message = HSOSARequest(language: language, source: source)
        let received = try session.sendSync(message)

        if let response = try? received.decode(as: HSOSAResponse.self) {
            return (response.success, response.jsonMessage, response.rawMessage)
        } else {
            return (false, nil, "Unable to decode response")
        }
    }

    /// No-op: there is no persistent connection to tear down.
    func shutdown() {}
}
