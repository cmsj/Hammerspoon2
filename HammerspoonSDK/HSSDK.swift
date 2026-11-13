//
//  HSSDK.swift
//  HammerspoonSDK
//

import Foundation
import JavaScriptCore

/// The Hammerspoon 2 SDK: the API that Hammerspoon 2's own modules and third-party extensions are
/// built on.
///
/// An extension is a bundle of compiled code (and, optionally, JavaScript) that Hammerspoon 2
/// loads at runtime, when a script calls `require('ext:<name>')`. Its principal class conforms to
/// `HSModuleAPI`, and it links against this framework, which Hammerspoon 2 embeds.
@_documentation(visibility: private)
public enum HSSDK {
    /// The version of the SDK this copy of Hammerspoon 2 provides.
    ///
    /// The major version changes when the SDK changes in a way that breaks extensions built
    /// against an earlier one, and the minor version when it gains API. An extension declares the
    /// version it was built against in the `HSSDKVersion` key of its Info.plist.
    nonisolated public static let version = HSSDKVersion(major: 1, minor: 0)
}

/// A version of the Hammerspoon 2 SDK, such as `1.2`.
@_documentation(visibility: private)
nonisolated public struct HSSDKVersion: Comparable, Sendable, CustomStringConvertible {
    /// Changes when the SDK breaks extensions built against an earlier version
    public let major: Int

    /// Changes when the SDK gains API without breaking existing extensions
    public let minor: Int

    /// Creates a version from its components.
    /// - Parameters:
    ///   - major: The major version
    ///   - minor: The minor version
    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// Creates a version from a string such as `"1.2"`, or returns nil if the string isn't two
    /// non-negative integers separated by a dot.
    /// - Parameter description: The version string
    public init?(_ description: String) {
        let parts = description.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let major = Int(parts[0]), let minor = Int(parts[1]),
              major >= 0, minor >= 0 else { return nil }
        self.init(major: major, minor: minor)
    }

    public var description: String { "\(major).\(minor)" }

    /// Whether an extension built against `required` can run on this version: the major versions
    /// match, and this version has all the API that version had.
    /// - Parameter required: The SDK version the extension was built against
    /// - Returns: true if the extension can run
    public func supports(_ required: HSSDKVersion) -> Bool {
        required.major == major && required.minor <= minor
    }

    public static func < (lhs: HSSDKVersion, rhs: HSSDKVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

// MARK: - Host hooks

/// Hooks the Hammerspoon 2 app sets to connect the SDK to its engine. Not available to extensions.
@_spi(HammerspoonHost)
extension HSSDK {
    /// Receives every message logged through `AKInfo`, `AKError` and the rest, on the main actor.
    public static var logHandler: ((HammerspoonLogType, String) -> Void)?

    /// The engine's current JSContext, for work that happens outside a JS call, such as a
    /// Promise resolving
    public static var engineContextProvider: () -> JSContext? = { nil }
}
