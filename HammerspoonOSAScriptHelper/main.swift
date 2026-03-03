//
//  main.swift
//  HammerspoonOSAScriptHelper
//
//  Created by Chris Jones on 02/03/2026.
//

import Foundation
import Security

class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    /// Accepts a new XPC connection only after verifying that the connecting
    /// process is signed by the same Apple Developer team as this service.
    /// This prevents a confused-deputy attack where a rogue local process
    /// abuses this service's Automation / TCC rights.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        guard isConnectingProcessTrusted(newConnection) else {
            newConnection.invalidate()
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HSOSAScriptServiceProtocol.self)
        newConnection.exportedObject = HSOSAScriptXPCService()
        newConnection.resume()
        return true
    }

    // MARK: - Private

    /// Returns `true` iff the connecting process is signed with the same Apple
    /// Developer team identifier as this XPC service.
    private func isConnectingProcessTrusted(_ connection: NSXPCConnection) -> Bool {
        // 1. Obtain the SecCode of the caller via its audit token.
        var auditToken = connection.auditToken
        let tokenData = Data(bytes: &auditToken, count: MemoryLayout<audit_token_t>.size)
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        var callerCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &callerCode) == errSecSuccess,
              let callerCode else {
            return false
        }

        // 2. Derive our own team ID from our code-signing information.
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess,
              let selfCode else { return false }

        var selfStaticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &selfStaticCode) == errSecSuccess,
              let selfStaticCode else { return false }

        var signingInfoDict: CFDictionary?
        guard SecCodeCopySigningInformation(selfStaticCode,
                                            SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &signingInfoDict) == errSecSuccess,
              let signingInfo = signingInfoDict as? [String: Any],
              let teamID = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty else { return false }

        // 3. Build a code-signing requirement and check the caller against it.
        //    Require the same Apple Developer team certificate to be present.
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }

        return SecCodeCheckValidityWithErrors(callerCode, [], requirement, nil) == errSecSuccess
    }
}

// Create the delegate for the service.
let delegate = ServiceDelegate()

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener.service()
listener.delegate = delegate

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()
