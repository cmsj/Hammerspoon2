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

        let configDir = settings.configLocation.deletingLastPathComponent()
        var configDirExists = ObjCBool(booleanLiteral: false)
        unsafe _ = fileSystem.fileExists(atPath: configDir.path, isDirectory: &configDirExists)

        if !configDirExists.boolValue {
            AKError("Configuration directory does not exist at: \(configDir.path)")
            return
        }

        FileManager.default.changeCurrentDirectoryPath(configDir.path)

        if !fileSystem.fileExists(atPath: settings.configLocation.path) {
            AKError("No config file found at: \(settings.configLocation.path)")
            return
        }
        try engine.evalFromURL(settings.configLocation, wrapInIIFE: true)
    }

    func shutdown() {
        NSApp.terminate(self)
    }
}
