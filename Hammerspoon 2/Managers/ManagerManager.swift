//
//  ManagerManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 08/10/2025.
//

import Foundation
import AppKit

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
}
