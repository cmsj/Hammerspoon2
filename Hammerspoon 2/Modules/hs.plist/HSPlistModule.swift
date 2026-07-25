//
//  HSPlistModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/07/2026.
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

/// Module for reading and writing macOS property list (plist) files.
///
/// Property lists are a structured data format used extensively on Apple platforms
/// for storing configuration, preferences, and serialized data. This module supports
/// both XML and binary plist formats.
///
/// JavaScript ↔ plist type mapping:
/// - JavaScript strings ↔ plist strings
/// - JavaScript numbers ↔ plist integers and reals
/// - JavaScript booleans ↔ plist true/false
/// - JavaScript arrays ↔ plist arrays
/// - JavaScript objects ↔ plist dictionaries
/// - JavaScript null is not supported by the plist format and will cause write operations to fail
/// - Plist Date and Data values are returned as opaque objects and may not be directly usable in JavaScript
@objc protocol HSPlistModuleAPI: JSExport {

    /// Read a plist file and return its contents as a JavaScript value.
    ///
    /// Supports both XML and binary plist formats. Returns a JavaScript object for
    /// dictionary-rooted plists, an array for array-rooted plists, or a string or
    /// number for scalar-rooted plists.
    ///
    /// - Parameter path: Path to the plist file
    /// - Returns: {any} The plist contents, or null if the file could not be read or parsed
    /// - Example:
    /// ```js
    /// const prefs = hs.plist.fromFile("/Users/me/Library/Preferences/com.example.app.plist")
    /// console.log(prefs.SomeKey)
    /// ```
    @objc func fromFile(_ path: String) -> NSObject?

    /// Read a plist from an XML string and return its contents as a JavaScript value.
    ///
    /// - Parameter plistString: An XML plist string
    /// - Returns: {any} The plist contents, or null if the string could not be parsed
    /// - Example:
    /// ```js
    /// const xml = '<?xml version="1.0" encoding="UTF-8"?>' +
    ///     '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' +
    ///     '<plist version="1.0"><dict><key>Name</key><string>Test</string></dict></plist>'
    /// const data = hs.plist.fromString(xml)
    /// console.log(data.Name)
    /// ```
    @objc func fromString(_ plistString: String) -> NSObject?

    /// Write a JavaScript object to a plist file on disk.
    ///
    /// Keys must be strings. Values may be strings, numbers, booleans, arrays, or
    /// nested objects. JavaScript null values are not plist-compatible and will cause
    /// the write to fail.
    ///
    /// - Parameters:
    ///   - path: Destination file path
    ///   - data: A JavaScript object to serialize as a property list
    ///   - binary: If true, write binary plist format; if false (default), write XML plist format
    /// - Returns: true if the file was written successfully
    /// - Example:
    /// ```js
    /// hs.plist.toFile("/tmp/test.plist", { name: "Hammerspoon", version: 2 })
    /// hs.plist.toFile("/tmp/test.plist", { name: "Hammerspoon" }, true)
    /// ```
    @objc func toFile(_ path: String, _ data: [String: Any], _ binary: Bool) -> Bool

    /// Serialize a JavaScript object to a plist string.
    ///
    /// With binary set to false (default), returns an XML plist string suitable for
    /// storing in text files or passing to `readString`. With binary set to true,
    /// returns a base64-encoded binary plist string.
    ///
    /// - Parameters:
    ///   - data: A JavaScript object to serialize as a property list
    ///   - binary: If true, produce base64-encoded binary plist output; if false (default), produce an XML string
    /// - Returns: The serialized plist string, or null if serialization failed
    /// - Example:
    /// ```js
    /// const xml = hs.plist.toString({ name: "Hammerspoon", version: 2 })
    /// const b64 = hs.plist.toString({ name: "Hammerspoon" }, true)
    /// ```
    @objc func toString(_ data: [String: Any], _ binary: Bool) -> String?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSPlistModule: NSObject, HSModuleAPI, HSPlistModuleAPI {
    var name = "hs.plist"
    let engineID: UUID

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {}

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - Reading

    @objc func fromFile(_ path: String) -> NSObject? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            AKError("hs.plist.fromFile(): Failed to read file at: \(path)")
            return nil
        }
        return deserializePlist(data: data, context: "read")
    }

    @objc func fromString(_ plistString: String) -> NSObject? {
        guard let data = plistString.data(using: .utf8) else {
            AKError("hs.plist.fromString(): Failed to convert string to UTF-8 data")
            return nil
        }
        return deserializePlist(data: data, context: "readString")
    }

    private func deserializePlist(data: Data, context: String) -> NSObject? {
        var format: PropertyListSerialization.PropertyListFormat = .xml
        do {
            let result = try unsafe PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            )
            return result as? NSObject
        } catch {
            AKError("hs.plist.\(context)(): Failed to parse plist: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Writing

    @objc func toFile(_ path: String, _ data: [String: Any], _ binary: Bool) -> Bool {
        guard let plistData = serializePlist(data: data, binary: binary, context: "write") else {
            return false
        }
        do {
            try plistData.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            AKError("hs.plist.toFile(): Failed to write file at \(path): \(error.localizedDescription)")
            return false
        }
    }

    @objc func toString(_ data: [String: Any], _ binary: Bool) -> String? {
        guard let plistData = serializePlist(data: data, binary: binary, context: "toString") else {
            return nil
        }
        if binary {
            return plistData.base64EncodedString()
        } else {
            return String(data: plistData, encoding: .utf8)
        }
    }

    private func serializePlist(data: [String: Any], binary: Bool, context: String) -> Data? {
        let format: PropertyListSerialization.PropertyListFormat = binary ? .binary : .xml
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: data,
                format: format,
                options: 0
            )
        } catch {
            AKError("hs.plist.\(context)(): Failed to serialize plist: \(error.localizedDescription)")
            return nil
        }
    }
}
