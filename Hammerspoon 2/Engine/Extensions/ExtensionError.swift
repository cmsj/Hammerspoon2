//
//  ExtensionError.swift
//  Hammerspoon 2
//

import Foundation
import HammerspoonSDK

/// Why an extension couldn't be loaded with `require('ext:<name>')`. Each case reaches JavaScript
/// as an `Error` with the description as its message and `code` set, so scripts can tell them
/// apart.
nonisolated enum ExtensionError: Error, Equatable, CustomStringConvertible {
    /// Extensions are turned off in Settings
    case disabled
    /// The name isn't a valid extension name
    case invalidName(String)
    /// There is no bundle for the extension in the extensions directory
    case notFound(name: String, expectedAt: URL)
    /// The bundle's Info.plist is missing something, or doesn't match its name
    case invalidBundle(name: String, reason: String)
    /// The extension was built against an SDK this copy of Hammerspoon 2 doesn't provide
    case incompatibleSDK(name: String, required: HSSDKVersion, available: HSSDKVersion)
    /// The bundle isn't signed, or its signature doesn't match its contents
    case invalidSignature(name: String, reason: String)
    /// The user didn't allow the extension to load
    case notApproved(name: String)
    /// The bundle's code couldn't be loaded
    case loadFailed(name: String, reason: String)
    /// The bundle loaded, but its principal class isn't an `HSModuleAPI` module
    case invalidPrincipalClass(name: String, className: String)
    /// The bundle defines Objective-C classes that already exist, so it can't be used safely
    case classCollision(name: String, classes: [String])
    /// The bundle's JSExport methods would leak every object they return to JavaScript
    case retainedResultMethods(name: String, selectors: [String])

    /// The value of the JavaScript error's `code` property
    var code: String {
        switch self {
        case .disabled: "ERR_EXTENSIONS_DISABLED"
        case .invalidName: "ERR_EXTENSION_INVALID_NAME"
        case .notFound: "ERR_EXTENSION_NOT_FOUND"
        case .invalidBundle: "ERR_EXTENSION_INVALID_BUNDLE"
        case .incompatibleSDK: "ERR_EXTENSION_INCOMPATIBLE_SDK"
        case .invalidSignature: "ERR_EXTENSION_INVALID_SIGNATURE"
        case .notApproved: "ERR_EXTENSION_NOT_APPROVED"
        case .loadFailed: "ERR_EXTENSION_LOAD_FAILED"
        case .invalidPrincipalClass: "ERR_EXTENSION_INVALID_PRINCIPAL_CLASS"
        case .classCollision: "ERR_EXTENSION_CLASS_COLLISION"
        case .retainedResultMethods: "ERR_EXTENSION_RETAINED_RESULT_METHODS"
        }
    }

    var description: String {
        switch self {
        case .disabled:
            "Extensions are turned off. To use them, turn on \"Allow extensions\" in the Advanced tab of Settings."
        case .invalidName(let name):
            "\"\(name)\" isn't a valid extension name. Names can only contain letters, digits, dots, hyphens and underscores, and must start with a letter or digit."
        case .notFound(let name, let expectedAt):
            "Can't find the extension \(name). It should be at \(expectedAt.path)"
        case .invalidBundle(let name, let reason):
            "The extension \(name) isn't a valid extension bundle: \(reason)"
        case .incompatibleSDK(let name, let required, let available):
            "The extension \(name) was built for Hammerspoon 2 SDK \(required), but this copy of Hammerspoon 2 provides SDK \(available). Install a version of the extension built for SDK \(available.major).x."
        case .invalidSignature(let name, let reason):
            "The extension \(name) can't be loaded because its code signature isn't valid: \(reason)"
        case .notApproved(let name):
            "The extension \(name) wasn't allowed to load. Reload your config to be asked again."
        case .loadFailed(let name, let reason):
            "The extension \(name) couldn't be loaded: \(reason)"
        case .invalidPrincipalClass(let name, let className):
            "The extension \(name)'s principal class, \(className), doesn't conform to HSModuleAPI."
        case .classCollision(let name, let classes):
            "The extension \(name) defines Objective-C classes that already exist (\(classes.joined(separator: ", "))), so it can't be used. Give its classes a unique prefix with @objc(Name), then restart Hammerspoon 2."
        case .retainedResultMethods(let name, let selectors):
            "The extension \(name) has JSExport methods whose names start with alloc, new, copy or mutableCopy (\(selectors.joined(separator: ", "))), which leak every object they return to JavaScript. Rename them, then restart Hammerspoon 2."
        }
    }
}
