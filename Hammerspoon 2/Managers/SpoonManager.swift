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

/// What, if anything, already exists at the destination an import is about to write to
enum SpoonImportConflict {
    /// Nothing exists at the destination - safe to import directly
    case none
    /// A well-formed Spoon is already installed there
    case existingSpoon(SpoonMetadata)
    /// Something exists there, but it isn't a well-formed Spoon
    case existingUnreadable
}

/// Describes what importing a .spoon2 bundle would do, without touching the filesystem.
/// Produced by `planImport(from:)`; hand it to `performImport(_:)` to actually carry it out,
/// after resolving `conflict` with the user if it isn't `.none`.
struct SpoonImportPlan {
    let bundleURL: URL
    let spoonsDir: URL
    let destination: URL
    let name: String
    let newMetadata: SpoonMetadata
    let conflict: SpoonImportConflict
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

    /// Validates a .spoon2 bundle and works out where it would be installed, without touching
    /// the filesystem. If a Spoon (or anything else) already exists at that destination, it's
    /// reported via `SpoonImportPlan.conflict` rather than acted on - the caller decides
    /// whether to confirm with the user before calling `performImport(_:)`.
    /// - Parameter bundleURL: The .spoon2 bundle the user opened
    /// - Returns: A plan describing the would-be import
    func planImport(from bundleURL: URL) throws -> SpoonImportPlan {
        guard bundleURL.pathExtension.lowercased() == "spoon2" else {
            throw SpoonImportError.notASpoon2Bundle
        }

        let newMetadata = try validateSpoon(at: bundleURL)

        let spoonName = bundleURL.deletingPathExtension().lastPathComponent
        let spoonsDir = settings.configLocation
            .deletingLastPathComponent()
            .appendingPathComponent("Spoons")
        let destination = spoonsDir.appendingPathComponent(spoonName)

        let conflict: SpoonImportConflict
        if !fileSystem.fileExists(atPath: destination.path) {
            conflict = .none
        } else if let existingMetadata = try? validateSpoon(at: destination) {
            conflict = .existingSpoon(existingMetadata)
        } else {
            conflict = .existingUnreadable
        }

        return SpoonImportPlan(
            bundleURL: bundleURL,
            spoonsDir: spoonsDir,
            destination: destination,
            name: spoonName,
            newMetadata: newMetadata,
            conflict: conflict
        )
    }

    /// Carries out a plan produced by `planImport(from:)`: creates `<configDir>/Spoons/` if
    /// needed, removes anything already at the plan's destination, and copies the bundle in.
    /// Call this only after resolving `plan.conflict` with the user, if it isn't `.none`.
    /// - Parameter plan: A plan previously produced by `planImport(from:)`
    func performImport(_ plan: SpoonImportPlan) throws {
        if !fileSystem.fileExists(atPath: plan.spoonsDir.path) {
            try fileSystem.createDirectory(at: plan.spoonsDir, withIntermediateDirectories: true)
        }
        if fileSystem.fileExists(atPath: plan.destination.path) {
            try fileSystem.removeItem(at: plan.destination)
        }
        try fileSystem.copyItem(at: plan.bundleURL, to: plan.destination)
    }
}
