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
        #warning("DEBUG build, XPC running without peer requirements")
#else
        session.setPeerRequirement(.isFromSameTeam())
#endif
        try session.activate()

        return try await withCheckedThrowingContinuation { continuation in
            defer { session.cancel(reason: "OSAScriptRunner deinit") }

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
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
//    func run(source: String,
//             language: String) async throws -> (success: Bool, resultJSON: String?, raw: String) {
//        return try await withCheckedThrowingContinuation { continuation in
//            let connection = NSXPCConnection(serviceName: serviceName)
//            connection.remoteObjectInterface = NSXPCInterface(with: HSOSAScriptServiceProtocol.self)
//            connection.resume()
//
//            // remoteObjectProxyWithErrorHandler fires if the connection dies before
//            // a reply is received (e.g. helper crash, service not found).
//            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
//                connection.invalidate()
//                continuation.resume(throwing: error)
//            } as? HSOSAScriptServiceProtocol
//
//            guard let proxy else {
//                connection.invalidate()
//                continuation.resume(throwing: NSError(
//                    domain: "HSOSAScriptRunner",
//                    code: -1,
//                    userInfo: [NSLocalizedDescriptionKey: "Failed to obtain XPC service proxy"]
//                ))
//                return
//            }
//
//            proxy.execute(source: source, language: language) { success, resultJSON, rawOrError in
//                connection.invalidate()
//                continuation.resume(returning: (
//                    success: success,
//                    resultJSON: resultJSON,
//                    raw: rawOrError ?? ""
//                ))
//            }
//        }
//    }

    /// No-op: there is no persistent connection to tear down.
    func shutdown() {}
}
