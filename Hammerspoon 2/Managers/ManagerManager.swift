//
//  ManagerManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 08/10/2025.
//

import Foundation
import AppKit

enum OnboardingError: LocalizedError {
    case directoryCreationFailed(path: String, underlying: Error)
    case configCopyFailed(fileName: String, underlying: Error)
    case bootFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path, let underlying):
            return "Couldn't create \(path): \(underlying.localizedDescription)"
        case .configCopyFailed(let fileName, let underlying):
            return "Couldn't copy \(fileName) into your config directory: \(underlying.localizedDescription)"
        case .bootFailed(let underlying):
            return "Your config directory is set up, but loading it failed: \(underlying.localizedDescription)"
        }
    }
}

@_documentation(visibility: private)
class ManagerManager {
    // Singleton instance using default dependencies
    static let shared = ManagerManager()

    // Dependencies (protocols for testability)
    let engine: JSEngineProtocol
    let settings: SettingsManagerProtocol
    let fileSystem: FileSystemProtocol

    /// Initializer with dependency injection
    /// - Parameters:
    ///   - engine: The JavaScript engine to use (defaults to JSEngine.shared)
    ///   - settings: The settings manager to use (defaults to SettingsManager.shared)
    ///   - fileSystem: The file system to use (defaults to FileManager.default)
    init(engine: JSEngineProtocol = JSEngine.shared,
         settings: SettingsManagerProtocol = SettingsManager.shared,
         fileSystem: FileSystemProtocol = FileManager.default) {
        self.engine = engine
        self.settings = settings
        self.fileSystem = fileSystem
    }

    func reload() throws {
        if settings.relaunchOnReload {
            relaunch()
        } else {
            try boot()
        }
    }

    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.05; done; open '\(escaped)'"]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    func boot() throws {
        try engine.resetContext()

        setupConfigDirectory()

        let configDir = settings.configLocation.deletingLastPathComponent()
        FileManager.default.changeCurrentDirectoryPath(configDir.path)

        if !fileSystem.fileExists(atPath: settings.configLocation.path) {
            AKError("No config file found at: \(settings.configLocation.path)")
            return
        }
        try engine.evalFromURL(settings.configLocation, wrapInIIFE: false)
    }

    // Creates the config directory if absent, then seeds any bundled UserAsset
    // files that are not already present (so user customisations are preserved).
    private func setupConfigDirectory() {
        let configDir = settings.configLocation.deletingLastPathComponent()
        let fm = FileManager.default

        guard !fileSystem.fileExists(atPath: configDir.path) else {
            // Config directory exists, take no further action
            return
        }

        do {
            try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
            AKDebug("Created config directory: \(configDir.path)")
        } catch {
            AKError("Failed to create config directory at \(configDir.path): \(error.localizedDescription)")
            return
        }

        guard let sharedSupport = Bundle.main.sharedSupportURL else {
            AKError("Could not locate SharedSupport directory in bundle")
            return
        }

        let seedFiles: [(bundleName: String, destName: String)] = [
            ("seed-package.json", "package.json"),
            ("seed-bundle.js",    "bundle.js"),
        ]

        for (bundleName, destName) in seedFiles {
            let dest = configDir.appendingPathComponent(destName)
            guard !fileSystem.fileExists(atPath: dest.path) else { continue }

            let src = sharedSupport.appendingPathComponent(bundleName)
            guard fileSystem.fileExists(atPath: src.path) else {
                AKError("Seed file missing from bundle: \(bundleName)")
                continue
            }

            do {
                try fm.copyItem(at: src, to: dest)
                AKDebug("Seeded \(destName) into config directory")
            } catch {
                AKError("Failed to copy \(destName) to config directory: \(error.localizedDescription)")
            }
        }
    }

    func shutdown() {
        engine.shutdown()
        NSApp.terminate(self)
    }

    /// Finishes first-run onboarding: creates the chosen config directory if
    /// needed, seeds it with the bundled default config files (without
    /// overwriting anything already there), points settings at it, and boots.
    /// - Parameter configDirectory: The directory the user chose to store their config in
    func completeOnboarding(configDirectory: URL) throws {
        if !fileSystem.fileExists(atPath: configDirectory.path) {
            do {
                try fileSystem.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            } catch {
                throw OnboardingError.directoryCreationFailed(path: configDirectory.path, underlying: error)
            }
        }

        if let templateDirectory = Bundle.main.resourceURL?.appendingPathComponent("DefaultConfig"),
           let templateFiles = try? fileSystem.contentsOfDirectory(at: templateDirectory) {
            for templateFile in templateFiles {
                let destination = configDirectory.appendingPathComponent(templateFile.lastPathComponent)
                if !fileSystem.fileExists(atPath: destination.path) {
                    do {
                        try fileSystem.copyItem(at: templateFile, to: destination)
                    } catch {
                        throw OnboardingError.configCopyFailed(fileName: templateFile.lastPathComponent, underlying: error)
                    }
                }
            }
        }

        settings.configLocation = configDirectory.appendingPathComponent("init.js")
        settings.hasCompletedOnboarding = true

        do {
            try boot()
        } catch {
            throw OnboardingError.bootFailed(underlying: error)
        }
    }
}
