//
//  main.swift
//  HammerspoonOSAScriptHelper
//
//  Created by Chris Jones on 02/03/2026.
//

import Foundation
import OSAKit
import OSLog

@main
extension HSOSAScriptXPCHelper {
    static func main() throws {
        guard let helper = HSOSAScriptXPCHelper() else {
            print("FATAL: Unable to start XPCListener")
            exit(EXIT_FAILURE)
        }
        withExtendedLifetime(helper) {
            dispatchMain()
        }
    }
}

/// Runs OSA scripts on behalf of Hammerspoon.
///
/// Requests are executed in parallel: each incoming message has its reply handed
/// off to a concurrent queue, so the session is free to deliver the next message
/// while a script is still running. Without this, one script stuck waiting for an
/// AppleEvent reply (which can take up to the 2 minute default AppleEvent timeout)
/// would stall every other script queued behind it.
///
/// Each request is traced with `os_signpost` intervals (subsystem
/// `HammerspoonOSAScriptHelper`, category `requests`), so slow requests can be
/// broken down into their compile/execute/serialise phases in Instruments, or with:
/// `log stream --signpost --predicate 'subsystem == "HammerspoonOSAScriptHelper"'`
class HSOSAScriptXPCHelper {
    var xpcListener: XPCListener
    static nonisolated let logger = Logger(subsystem: "HammerspoonOSAScriptHelper", category: "main")
    static nonisolated let signposter = OSSignposter(subsystem: "HammerspoonOSAScriptHelper", category: "requests")

    /// Scripts run here, rather than on the session's own (serial) queue.
    static nonisolated let executionQueue = DispatchQueue(label: "net.tenshu.Hammerspoon-2.HammerspoonOSAScriptHelper.execution",
                                                          qos: .userInitiated,
                                                          attributes: .concurrent)

    init?() {
        do {
#if DEBUG
            HSOSAScriptXPCHelper.logger.warning("WARNING: Running without XPC peer checking. This is unsafe and should only be done in development.")
            xpcListener = try XPCListener(service: HSOSAScriptServiceName,
                                          incomingSessionHandler: HSOSAScriptXPCHelper.xpcSessionHandler)
#else
            HSOSAScriptXPCHelper.logger.info("Enforcing XPC peer requirements.")
            xpcListener = try XPCListener(service: HSOSAScriptServiceName,
                                          requirement: .isFromSameTeam(),
                                          incomingSessionHandler: HSOSAScriptXPCHelper.xpcSessionHandler)
#endif
        } catch {
            HSOSAScriptXPCHelper.logger.error("Failed to start XPCListener: \(error)")
            return nil
        }
    }

    static nonisolated func errorMessage(from dict: NSDictionary?, fallback: String) -> String {
        guard let dict else { return fallback }
        // OSA/AppleScript error dicts use various keys depending on the engine.
        return (dict[NSLocalizedDescriptionKey] as? String)
        ?? (dict["NSAppleScriptErrorMessage"] as? String)
        ?? (dict["OSAScriptErrorMessage"] as? String)
        ?? (dict.description)
    }

    static let xpcSessionHandler = { @Sendable (request: XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision in
        request.accept { (message: XPCReceivedMessage) -> (any Encodable)? in
            let signpostID = signposter.makeSignpostID()

            guard let request = try? message.decode(as: HSOSARequest.self) else {
                logger.error("Unable to decode request")
                signposter.emitEvent("Undecodable request", id: signpostID)
                return HSOSAResponse(success: false,
                                     rawMessage: "Unable to decode request",
                                     jsonMessage: nil)
            }

            signposter.emitEvent("Request received", id: signpostID, "\(request.language, privacy: .public)")

            // XPCReceivedMessage isn't marked Sendable, but handing it to another
            // queue to reply from is exactly what handoffReply(to:) exists for, and
            // nothing else touches it once this handler returns.
            nonisolated(unsafe) let pendingMessage = message
            return message.handoffReply(to: executionQueue) {
                pendingMessage.reply(run(request, signpostID: signpostID))
            }
        }
        cancellationHandler: { richError in
            HSOSAScriptXPCHelper.logger.error("Session cancelled: \(richError.localizedDescription)")
        }
    }

    /// Compile and execute one request. Safe to call concurrently: every call gets
    /// its own `OSALanguageInstance`, because a component instance (such as the
    /// shared one `OSAScript(source:language:)` uses) must not be used by more than
    /// one thread at a time.
    static nonisolated func run(_ request: HSOSARequest, signpostID: OSSignpostID) -> HSOSAResponse {
        let requestState = signposter.beginInterval("Request", id: signpostID, "\(request.language, privacy: .public)")
        let response = execute(request, signpostID: signpostID)
        signposter.endInterval("Request", requestState, "success: \(response.success)")
        return response
    }

    private static nonisolated func execute(_ request: HSOSARequest, signpostID: OSSignpostID) -> HSOSAResponse {
        guard let osaLanguage = OSALanguage(forName: request.language) else {
            logger.error("Unknown language: \(request.language, privacy: .public)")
            return HSOSAResponse(success: false,
                                 rawMessage: "Unknown language: \(request.language)",
                                 jsonMessage: nil)
        }

        let script = OSAScript(source: request.source,
                               from: nil,
                               languageInstance: OSALanguageInstance(language: osaLanguage),
                               using: [])

        let compiled = signposter.withIntervalSignpost("Compile", id: signpostID) { () -> HSOSAResponse? in
            var compileError: NSDictionary? = nil
            guard script.compileAndReturnError(&compileError) else {
                let message = errorMessage(from: compileError, fallback: "Compilation failed")
                logger.error("Compilation failed: \(message)")
                return HSOSAResponse(success: false, rawMessage: message, jsonMessage: nil)
            }
            return nil
        }
        if let compileFailure = compiled {
            return compileFailure
        }

        var execError: NSDictionary? = nil
        let executed = signposter.withIntervalSignpost("Execute", id: signpostID) {
            script.executeAndReturnError(&execError)
        }
        guard let result = executed else {
            let message = errorMessage(from: execError, fallback: "Execution failed")
            logger.error("Execution failed: \(message)")
            return HSOSAResponse(success: false, rawMessage: message, jsonMessage: nil)
        }

        // Finally, attempt to convert the response into a dictionary of foundation objects
        // and encode that to JSON
        return signposter.withIntervalSignpost("Serialise", id: signpostID) {
            let rawString  = result.stringValue ?? ""
            let jsonObject = result.toJSONCompatibleObject()

            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return HSOSAResponse(success: true, rawMessage: rawString, jsonMessage: jsonString)
            }

            // Serialisation failed (unexpected); fall back to JSON-encoded raw string.
            logger.error("Unable to serialise result to JSON, falling back to raw string")
            if let fallbackData = try? JSONSerialization.data(withJSONObject: rawString, options: [.fragmentsAllowed]),
               let fallbackString = String(data: fallbackData, encoding: .utf8) {
                return HSOSAResponse(success: true, rawMessage: rawString, jsonMessage: fallbackString)
            }

            // Extremely unlikely: as a last resort, return an empty JSON string.
            return HSOSAResponse(success: true, rawMessage: rawString, jsonMessage: "\"\"")
        }
    }
}
