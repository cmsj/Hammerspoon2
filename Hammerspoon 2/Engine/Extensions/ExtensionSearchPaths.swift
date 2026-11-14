//
//  ExtensionSearchPaths.swift
//  Hammerspoon 2
//

import Foundation

/// The folders `require('ext:<name>')` looks for extension bundles in.
struct ExtensionSearchPaths {
    /// An installed Spoon's Extensions folder
    struct SpoonDirectory {
        let spoon: String
        let directory: URL
    }

    /// The user's own Extensions folder, next to their config file. An extension here is used in
    /// preference to any Spoon's copy of it.
    let userDirectory: URL

    /// The Extensions folder of each installed Spoon that has one
    let spoonDirectories: [SpoonDirectory]

    init(userDirectory: URL, spoonDirectories: [SpoonDirectory] = []) {
        self.userDirectory = userDirectory
        self.spoonDirectories = spoonDirectories
    }

    /// The name of the folder inside a Spoon that holds its extensions
    static let spoonExtensionsFolder = "Extensions"

    /// The user's Extensions folder, and the Extensions folder of every Spoon installed in
    /// `spoonsDirectory`
    static func installed(userDirectory: URL, spoonsDirectory: URL) -> ExtensionSearchPaths {
        let spoons = (try? FileManager.default.contentsOfDirectory(
            at: spoonsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        let spoonDirectories = spoons
            .filter { SpoonManager.isValidSpoonName($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { spoon -> SpoonDirectory? in
                let directory = spoon.appendingPathComponent(spoonExtensionsFolder, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard unsafe FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { return nil }
                return SpoonDirectory(spoon: spoon.lastPathComponent, directory: directory)
            }
        return ExtensionSearchPaths(userDirectory: userDirectory, spoonDirectories: spoonDirectories)
    }

    /// Where the extension named `name` is: the user's Extensions folder if it's there, or else
    /// the one Spoon that provides it.
    /// - Parameter name: The extension's name
    /// - Throws: `ExtensionError.notFound` if nothing provides it, or `.ambiguous` if more than one
    ///   Spoon does and the user's folder doesn't
    /// - Returns: The folder its bundle is in, and the Spoon that folder belongs to, if any
    func locate(_ name: String) throws(ExtensionError) -> (directory: URL, spoon: String?) {
        if Self.hasBundle(name, in: userDirectory) {
            return (userDirectory, nil)
        }
        let providers = spoonDirectories.filter { Self.hasBundle(name, in: $0.directory) }
        switch providers.count {
        case 0:
            throw .notFound(name: name, expectedAt: ExtensionManifest.bundleURL(forName: name, in: userDirectory))
        case 1:
            return (providers[0].directory, providers[0].spoon)
        default:
            throw .ambiguous(name: name, spoons: providers.map(\.spoon))
        }
    }

    private static func hasBundle(_ name: String, in directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let url = ExtensionManifest.bundleURL(forName: name, in: directory)
        return unsafe FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
