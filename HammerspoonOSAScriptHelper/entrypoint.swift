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
        guard let _ = HSOSAScriptXPCHelper() else {
            print("FATAL: Unable to start XPCListener")
            exit(EXIT_FAILURE)
        }
        dispatchMain()
    }
}

class HSOSAScriptXPCHelper {
    var xpcListener: XPCListener
    static nonisolated let logger = Logger(subsystem: "HammerspoonOSAScriptHelper", category: "main")

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
        request.accept { message in
            HSOSAScriptXPCHelper.logger.info("New request accepted...")

            // First, check that we can decode the incoming message to the expected HSOSARequest type
            guard let request = try? message.decode(as: HSOSARequest.self) else {
                HSOSAScriptXPCHelper.logger.error("Unable to decode request")
                return HSOSAResponse(success: false,
                                     rawMessage: "Unable to decode request",
                                     jsonMessage: nil)
            }

            // Second, figure out which language the user asked us to run
            guard let osaLanguage = OSALanguage(forName: request.language) else {
                HSOSAScriptXPCHelper.logger.error("Unknown language: \(request.language)")
                return HSOSAResponse(success: false,
                                     rawMessage: "Unknown language: \(request.language)",
                                     jsonMessage: nil)
            }

            HSOSAScriptXPCHelper.logger.info("Detected language: \(osaLanguage.name ?? "UNKNOWN")")

            // Third, compile the supplied script
            let script = OSAScript(source: request.source, language: osaLanguage)
            var compileError: NSDictionary? = nil
            guard script.compileAndReturnError(&compileError) else {
                HSOSAScriptXPCHelper.logger.error("Compilation failed")
                return HSOSAResponse(success: false,
                                     rawMessage: errorMessage(from: compileError, fallback: "Compilation failed"),
                                     jsonMessage: nil)
            }

            HSOSAScriptXPCHelper.logger.info("Compiled...")

            // Fourth, execute the supplied script
            var execError: NSDictionary? = nil
            guard let result = script.executeAndReturnError(&execError) else {
                HSOSAScriptXPCHelper.logger.error("Execution failed: \(execError?.description ?? "<no error>")")
                return HSOSAResponse(success: false,
                                     rawMessage: errorMessage(from: execError, fallback: "Execution failed"),
                                     jsonMessage: nil)
            }

            HSOSAScriptXPCHelper.logger.info("Executed...")
            // Finally, attempt to convert the response into a dictionary of foundation objects
            // and encode that to JSON
            let rawString  = result.stringValue ?? ""
            let jsonObject = result.toJSONCompatibleObject()

            do {
                let jsonData   = try JSONSerialization.data(
                    withJSONObject: jsonObject, options: [.fragmentsAllowed])
                let jsonString = String(data: jsonData, encoding: .utf8)
                HSOSAScriptXPCHelper.logger.info("Returning result")
                return HSOSAResponse(success: true, rawMessage: rawString, jsonMessage: jsonString)
            } catch {
                // Serialisation failed (unexpected); fall back to JSON-encoded raw string.
                if let fallbackData = try? JSONSerialization.data(
                    withJSONObject: rawString, options: [.fragmentsAllowed]),
                   let fallbackString = String(data: fallbackData, encoding: .utf8) {
                    return HSOSAResponse(success: true, rawMessage: rawString, jsonMessage: fallbackString)
                } else {
                    // Extremely unlikely: as a last resort, return an empty JSON string.
                    return HSOSAResponse(success: true, rawMessage: rawString, jsonMessage: "\"\"")
                }
            }
        }
        cancellationHandler: { richError in
            HSOSAScriptXPCHelper.logger.error("Request Cancelled: \(richError.localizedDescription)")
        }
    }
}
