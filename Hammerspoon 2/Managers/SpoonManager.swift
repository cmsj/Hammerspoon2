//
//  SpoonManager.swift
//  Hammerspoon 2
//

import Foundation

/// Metadata read from a Spoon's spoon.json manifest
struct SpoonMetadata: Decodable {
    let name: String
    let author: String
    let version: String
    let description: String

    var hasNonEmptyFields: Bool {
        [name, author, version, description].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Reasons a directory might not be a well-formed Spoon
enum SpoonValidationError: LocalizedError {
    case missingSpoonJSON
    case invalidSpoonJSON(underlying: String)
    case emptyRequiredFields
    case missingInitJS

    var errorDescription: String? {
        switch self {
        case .missingSpoonJSON:
            return "has no spoon.json"
        case .invalidSpoonJSON(let underlying):
            return "has an invalid spoon.json (must contain name, author, version, and description): \(underlying)"
        case .emptyRequiredFields:
            return "has an invalid spoon.json (name, author, version, and description must all be non-empty)"
        case .missingInitJS:
            return "has no init.js"
        }
    }
}

enum SpoonImportError: LocalizedError {
    case notASpoon2Bundle

    var errorDescription: String? {
        switch self {
        case .notASpoon2Bundle:
            return "is not a .spoon2 bundle"
        }
    }
}

/// Validates well-formed Spoons and imports .spoon2 bundles into the user's config directory.
///
/// Used from two places: `ModuleRoot.loadSpoon()` validates an already-installed Spoon before
/// loading it, and `AppDelegate` imports a .spoon2 bundle when the user double-clicks one in
/// Finder. Both share the same definition of "well-formed" via `validateSpoon(at:)`.
@_documentation(visibility: private)
class SpoonManager {
    static let shared = SpoonManager()

    let fileSystem: FileSystemProtocol
    let settings: SettingsManagerProtocol

    init(fileSystem: FileSystemProtocol = FileManager.default,
         settings: SettingsManagerProtocol = SettingsManager.shared) {
        self.fileSystem = fileSystem
        self.settings = settings
    }

    /// Validates that `directory` is a well-formed Spoon: a spoon.json with non-empty name,
    /// author, version, and description fields, plus an init.js alongside it.
    /// - Parameter directory: The Spoon's directory (or a .spoon2 bundle)
    /// - Returns: The parsed spoon.json metadata
    func validateSpoon(at directory: URL) throws -> SpoonMetadata {
        let spoonJSONURL = directory.appendingPathComponent("spoon.json")
        let initJSURL = directory.appendingPathComponent("init.js")

        guard fileSystem.fileExists(atPath: spoonJSONURL.path) else {
            throw SpoonValidationError.missingSpoonJSON
        }

        let json: String
        do {
            json = try fileSystem.contentsOf(url: spoonJSONURL)
        } catch {
            throw SpoonValidationError.invalidSpoonJSON(underlying: error.localizedDescription)
        }

        let metadata: SpoonMetadata
        do {
            metadata = try JSONDecoder().decode(SpoonMetadata.self, from: Data(json.utf8))
        } catch {
            throw SpoonValidationError.invalidSpoonJSON(underlying: error.localizedDescription)
        }

        guard metadata.hasNonEmptyFields else {
            throw SpoonValidationError.emptyRequiredFields
        }

        guard fileSystem.fileExists(atPath: initJSURL.path) else {
            throw SpoonValidationError.missingInitJS
        }

        return metadata
    }

    /// Imports a .spoon2 bundle into `<configDir>/Spoons/`, creating that directory if needed
    /// and overwriting any existing Spoon with the same name (so double-clicking an updated
    /// .spoon2 reinstalls it). The bundle's own filename, minus the .spoon2 extension, becomes
    /// the installed Spoon's name - the same name `hs.loadSpoon()` should be called with.
    /// - Parameter bundleURL: The .spoon2 bundle the user opened
    /// - Returns: The name the Spoon was installed under, and its parsed spoon.json metadata
    @discardableResult
    func importSpoon(from bundleURL: URL) throws -> (name: String, metadata: SpoonMetadata) {
        guard bundleURL.pathExtension.lowercased() == "spoon2" else {
            throw SpoonImportError.notASpoon2Bundle
        }

        let metadata = try validateSpoon(at: bundleURL)

        let spoonName = bundleURL.deletingPathExtension().lastPathComponent
        let spoonsDir = settings.configLocation
            .deletingLastPathComponent()
            .appendingPathComponent("Spoons")
        let destination = spoonsDir.appendingPathComponent(spoonName)

        if !fileSystem.fileExists(atPath: spoonsDir.path) {
            try fileSystem.createDirectory(at: spoonsDir, withIntermediateDirectories: true)
        }
        if fileSystem.fileExists(atPath: destination.path) {
            try fileSystem.removeItem(at: destination)
        }
        try fileSystem.copyItem(at: bundleURL, to: destination)

        return (spoonName, metadata)
    }
}
