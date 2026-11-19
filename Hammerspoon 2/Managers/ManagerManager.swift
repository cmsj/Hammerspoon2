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
    let configProblemNotifier: ConfigProblemNotifierProtocol

    /// Initializer with dependency injection
    /// - Parameters:
    ///   - engine: The JavaScript engine to use (defaults to JSEngine.shared)
    ///   - settings: The settings manager to use (defaults to SettingsManager.shared)
    ///   - fileSystem: The file system to use (defaults to FileManager.default)
    ///   - configProblemNotifier: Tells the user about config problems (defaults to ConfigProblemNotifier.shared)
    init(engine: JSEngineProtocol = JSEngine.shared,
         settings: SettingsManagerProtocol = SettingsManager.shared,
         fileSystem: FileSystemProtocol = FileManager.default,
         configProblemNotifier: ConfigProblemNotifierProtocol = ConfigProblemNotifier.shared) {
        self.engine = engine
        self.settings = settings
        self.fileSystem = fileSystem
        self.configProblemNotifier = configProblemNotifier
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

    /// Creates a fresh JS context and loads the user's config into it. Problems with the config
    /// itself are shown to the user as a notification, rather than thrown.
    /// - Throws: If the JS context couldn't be created
    func boot() throws {
        // Whatever was wrong last time may have been fixed
        configProblemNotifier.withdraw()

        try engine.resetContext()

        let configDir = settings.configLocation.deletingLastPathComponent()
        // swiftlint:disable:next compiler_protocol_init
        var configDirExists = ObjCBool(booleanLiteral: false)
        unsafe _ = fileSystem.fileExists(atPath: configDir.path, isDirectory: &configDirExists)

        if !configDirExists.boolValue {
            AKError("Configuration directory does not exist at: \(configDir.path)")
            configProblemNotifier.notify(.missingDirectory(configDir))
            return
        }

        FileManager.default.changeCurrentDirectoryPath(configDir.path)

        if !fileSystem.fileExists(atPath: settings.configLocation.path) {
            AKError("No config file found at: \(settings.configLocation.path)")
            configProblemNotifier.notify(.missingFile(settings.configLocation))
            return
        }
        AKDebug("Loading user config from: \(settings.configLocation)...")
        do {
            try engine.evalFromURL(settings.configLocation, wrapInIIFE: false) { [configProblemNotifier] error in
                // A config using top-level await failed after its first await
                AKError("User config failed to load")
                configProblemNotifier.notify(.scriptError(error.msg))
            }
        } catch let error as HammerspoonError where error.kind == .jsException {
            // The exception itself has already been logged to the Console
            AKError("User config failed to load")
            configProblemNotifier.notify(.scriptError(error.msg))
            return
        } catch {
            AKError("Unable to read config file at \(settings.configLocation.path): \(error.localizedDescription)")
            configProblemNotifier.notify(.unreadableFile(settings.configLocation, reason: error.localizedDescription))
            return
        }
        AKDebug("User config complete")
    }

    /// Quit the app. Teardown happens in `prepareForTermination()`, which the app delegate calls
    /// for every quit path (menu items, Cmd-Q, relaunch, logout).
    func shutdown() {
        NSApp.terminate(self)
    }

    /// Tear down the JS engine and make sure any processes started by hs.task have exited.
    /// This blocks until those processes exit or are sent SIGKILL, for at most a few seconds.
    func prepareForTermination() {
        engine.shutdown()
        HSTaskReaper.shared.drain()
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
