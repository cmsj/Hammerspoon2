//
//  ExtensionManifest.swift
//  Hammerspoon 2
//

import Foundation
import HammerspoonSDK

/// What an extension bundle says about itself in its Info.plist, checked before any of its code
/// is loaded.
///
/// An extension named `com.example.foo` lives at `<extensions directory>/com.example.foo.hsmodule`,
/// and its Info.plist has:
/// - `HSModuleName`: its name, which must match the bundle's file name
/// - `HSSDKVersion`: the SDK version it was built against, such as `"1.0"`
/// - `NSPrincipalClass`: the class of its module, which conforms to `HSModuleAPI`
///
/// It may also have a JavaScript enhancement script, `Resources/<name>.js`.
nonisolated struct ExtensionManifest: Equatable {
    /// The file extension of extension bundles
    static let bundleExtension = "hsmodule"

    let name: String
    let bundleURL: URL
    let sdkVersion: HSSDKVersion
    let principalClassName: String

    /// The JavaScript enhancement script, if the extension has one
    let enhancementScriptURL: URL?

    /// Whether `name` can be an extension name: letters, digits, dots, hyphens and underscores,
    /// starting with a letter or digit, so it's always a plain file name.
    static func isValidName(_ name: String) -> Bool {
        let alphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let allowed = alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard let first = name.unicodeScalars.first, alphanumerics.contains(first) else { return false }
        return name.unicodeScalars.count <= 200 && name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Where the bundle for an extension named `name` would be
    static func bundleURL(forName name: String, in directory: URL) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension(bundleExtension)
    }

    /// Reads and checks the manifest of the extension named `name`.
    /// - Parameters:
    ///   - name: The extension's name
    ///   - directory: The extensions directory
    ///   - hostSDKVersion: The SDK version this copy of Hammerspoon 2 provides
    /// - Throws: `ExtensionError` if the name is invalid, there's no bundle, or its Info.plist is
    ///   missing something, doesn't match, or asks for an SDK this copy doesn't provide
    /// - Returns: The manifest
    static func read(name: String, in directory: URL, hostSDKVersion: HSSDKVersion = HSSDK.version) throws(ExtensionError) -> ExtensionManifest {
        guard isValidName(name) else { throw .invalidName(name) }

        let url = bundleURL(forName: name, in: directory)
        var isDirectory: ObjCBool = false
        guard unsafe FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .notFound(name: name, expectedAt: url)
        }

        // Read the Info.plist directly rather than through Bundle, which caches bundles by path
        // for the life of the process, so a replaced bundle's new Info.plist would never be seen.
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = unsafe try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw .invalidBundle(name: name, reason: "it has no readable Contents/Info.plist")
        }

        guard let declaredName = plist["HSModuleName"] as? String else {
            throw .invalidBundle(name: name, reason: "its Info.plist has no HSModuleName")
        }
        guard declaredName == name else {
            throw .invalidBundle(name: name, reason: "its Info.plist says its name is \(declaredName), which doesn't match its file name")
        }
        guard let versionString = plist["HSSDKVersion"] as? String else {
            throw .invalidBundle(name: name, reason: "its Info.plist has no HSSDKVersion")
        }
        guard let sdkVersion = HSSDKVersion(versionString) else {
            throw .invalidBundle(name: name, reason: "its HSSDKVersion, \(versionString), isn't a version like 1.0")
        }
        guard hostSDKVersion.supports(sdkVersion) else {
            throw .incompatibleSDK(name: name, required: sdkVersion, available: hostSDKVersion)
        }
        guard let principalClassName = plist["NSPrincipalClass"] as? String, !principalClassName.isEmpty else {
            throw .invalidBundle(name: name, reason: "its Info.plist has no NSPrincipalClass")
        }
        guard plist["CFBundleExecutable"] is String else {
            throw .invalidBundle(name: name, reason: "its Info.plist has no CFBundleExecutable")
        }

        let scriptURL = url.appendingPathComponent("Contents/Resources/\(name).js")
        let hasScript = FileManager.default.fileExists(atPath: scriptURL.path)

        return ExtensionManifest(name: name,
                                 bundleURL: url,
                                 sdkVersion: sdkVersion,
                                 principalClassName: principalClassName,
                                 enhancementScriptURL: hasScript ? scriptURL : nil)
    }
}
