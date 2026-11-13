//
//  ExtensionSignature.swift
//  Hammerspoon 2
//

import Foundation
import Security

/// Who signed an extension bundle, read from a code signature that has been checked against the
/// bundle's contents.
///
/// Hammerspoon 2 turns off library validation so it can load code that Apple and its own team
/// didn't sign, so this is the check that stands in for it: an extension must have a valid
/// signature, though an ad-hoc one will do, and the user approves each signature (by its cdhash)
/// before its code is loaded.
nonisolated struct ExtensionSignature: Equatable {
    /// The code directory hash, in hex, which identifies exactly this build of the extension
    let cdHash: String

    /// The signing team, or nil for an ad-hoc signature
    let teamIdentifier: String?

    /// The common name of the signing certificate, such as
    /// "Developer ID Application: Example Ltd (ABCDE12345)", or nil for an ad-hoc signature
    let signerName: String?

    /// Whether the signature is ad-hoc, i.e. it doesn't identify who signed it
    var isAdHoc: Bool { signerName == nil }

    /// Checks the bundle's signature against its contents, and reads who signed it.
    /// - Parameters:
    ///   - url: The bundle
    ///   - name: The extension's name, for error messages
    /// - Throws: `ExtensionError.invalidSignature` if the bundle isn't signed, or anything in it
    ///   doesn't match its signature
    /// - Returns: The signature
    static func verify(bundleAt url: URL, name: String) throws(ExtensionError) -> ExtensionSignature {
        let code = try staticCode(at: url, name: name)
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else {
            throw .invalidSignature(name: name, reason: message(for: status))
        }
        return try read(code, name: name)
    }

    /// Reads the signature without checking it against the bundle's contents, which is much
    /// cheaper. Used to notice that a bundle has changed since it was loaded.
    /// - Parameter url: The bundle
    /// - Returns: The signature, or nil if the bundle has none
    static func readUnverified(bundleAt url: URL) -> ExtensionSignature? {
        guard let code = try? staticCode(at: url, name: url.lastPathComponent) else { return nil }
        return try? read(code, name: url.lastPathComponent)
    }

    private static func staticCode(at url: URL, name: String) throws(ExtensionError) -> SecStaticCode {
        var code: SecStaticCode?
        let status = unsafe SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code else {
            throw .invalidSignature(name: name, reason: message(for: status))
        }
        return code
    }

    private static func read(_ code: SecStaticCode, name: String) throws(ExtensionError) -> ExtensionSignature {
        var information: CFDictionary?
        let status = unsafe SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard status == errSecSuccess, let info = information as? [String: Any] else {
            throw .invalidSignature(name: name, reason: message(for: status))
        }
        guard let cdHash = info[kSecCodeInfoUnique as String] as? Data else {
            throw .invalidSignature(name: name, reason: "it isn't signed")
        }
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let signerName = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        return ExtensionSignature(cdHash: cdHash.map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }.joined(),
                                  teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
                                  signerName: signerName)
    }

    private static func message(for status: OSStatus) -> String {
        if status == errSecCSUnsigned {
            return "it isn't signed"
        }
        let description = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "\(description) (\(status))"
    }
}
