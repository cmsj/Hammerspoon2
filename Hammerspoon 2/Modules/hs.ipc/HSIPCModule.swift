//
//  HSIPCModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// Module for enabling CLI access to Hammerspoon 2 via the `hs2` command-line tool.
///
/// The IPC server must be explicitly started from your configuration — it does not run by default.
/// Once started, the `hs2` command-line tool connects via XPC and evaluates JavaScript
/// interactively, with optional live log streaming.
///
/// Communication is secured with a same-team code-signing requirement in release builds,
/// so only binaries signed with the same Team ID can connect.
///
/// ## Quick start
///
/// ```js
/// // In your Hammerspoon 2 config (init.js):
/// hs.ipc.start()
/// ```
///
/// Install the CLI tool once:
/// ```js
/// hs.ipc.installBinary()   // symlinks hs2 to /usr/local/bin/hs2
/// ```
///
/// Then in a terminal:
/// ```bash
/// hs2
/// hs2> hs.reload()
/// undefined
/// hs2> 2 + 2
/// 4
/// ```
///
/// Run with live log output:
/// ```bash
/// hs2 --log-level info
/// ```
@objc protocol HSIPCModuleAPI: JSExport {

    /// Whether the IPC server is currently accepting connections.
    ///
    /// - Example:
    /// ```js
    /// if (hs.ipc.isListening) {
    ///     console.log("IPC ready")
    /// }
    /// ```
    @objc var isListening: Bool { get }

    /// Start the IPC server.
    ///
    /// The server listens on a named XPC Mach service (`net.tenshu.Hammerspoon-2.ipc`).
    /// In release builds, only processes signed with the same Team ID can connect.
    /// Calling `start()` when already running logs a warning and does nothing.
    ///
    /// - Example:
    /// ```js
    /// hs.ipc.start()
    /// ```
    @objc func start()

    /// Stop the IPC server and disconnect all connected clients.
    ///
    /// - Example:
    /// ```js
    /// hs.ipc.stop()
    /// ```
    @objc func stop()

    /// Install the `hs2` command-line tool to the given directory as a symlink.
    ///
    /// Creates a symlink in the target directory that points to the `hs2` binary inside the
    /// Hammerspoon 2 app bundle. Using a symlink means the CLI automatically reflects any
    /// app update without reinstalling. Any existing `hs2` file at that path is replaced.
    ///
    /// The directory must be on your `$PATH` for `hs2` to work without a full path.
    ///
    /// **Permissions:** `/usr/local/bin` is typically user-writable on Intel Macs with Homebrew.
    /// On Apple Silicon, prefer `/opt/homebrew/bin`. On a stock Mac (no Homebrew), both
    /// directories require root — if this method returns `false`, run the logged command in
    /// a terminal with `sudo`.
    ///
    /// - Parameter directory: {string} Directory to install into. Defaults to `/usr/local/bin`.
    /// - Returns: `true` on success, `false` on error (details logged to the console).
    /// - Example:
    /// ```js
    /// hs.ipc.installBinary()                   // install to /usr/local/bin/hs2
    /// hs.ipc.installBinary("/opt/homebrew/bin") // install to /opt/homebrew/bin/hs2
    /// ```
    @objc func installBinary(_ directory: JSValue) -> Bool

    /// Remove the `hs2` command-line tool from the given directory.
    ///
    /// - Parameter directory: {string} Directory to remove from. Defaults to `/usr/local/bin`.
    /// - Returns: `true` on success, `false` if not found or on error.
    /// - Example:
    /// ```js
    /// hs.ipc.uninstallBinary()
    /// hs.ipc.uninstallBinary("/opt/homebrew/bin")
    /// ```
    @objc func uninstallBinary(_ directory: JSValue) -> Bool

    /// Check whether the `hs2` command-line tool exists at the given directory.
    ///
    /// - Parameter directory: {string} Directory to check. Defaults to `/usr/local/bin`.
    /// - Returns: `true` if an `hs2` binary exists at that path.
    /// - Example:
    /// ```js
    /// if (hs.ipc.isBinaryInstalled()) {
    ///     console.log("hs2 CLI is available")
    /// }
    /// ```
    @objc func isBinaryInstalled(_ directory: JSValue) -> Bool
}

// MARK: - Implementation

@safe @MainActor
@_documentation(visibility: private)
@objc class HSIPCModule: NSObject, HSModuleAPI, HSIPCModuleAPI {
    var moduleName = "hs.ipc"
    let engineID: UUID

    private var server: HSIPCServer?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        server?.stop()
        server = nil
    }

    isolated deinit {
        shutdown()
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        return "<\(moduleName): \(isListening ? "listening" : "not listening")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - HSIPCModuleAPI

    @objc var isListening: Bool { server?.isListening ?? false }

    @objc func start() {
        if server == nil {
            server = HSIPCServer()
        }
        server?.start()
    }

    @objc func stop() {
        server?.stop()
        server = nil
    }

    @objc func installBinary(_ directoryVal: JSValue) -> Bool {
        let directory = directoryVal.isString ? directoryVal.toString()! : "/usr/local/bin"

        guard let sourceURL = bundledHSBinaryURL() else {
            AKError("hs.ipc.installBinary(): Cannot find 'hs2' binary in the app bundle. Ensure the 'hs2' target has been built.")
            return false
        }

        let destURL = URL(fileURLWithPath: directory).appendingPathComponent("hs2")
        let fm = FileManager.default

        if (try? fm.attributesOfItem(atPath: destURL.path)) != nil {
            AKError("hs.ipc.installBinary(): \(destURL.path) already exists. Remove it manually before installing.")
            return false
        }

        do {
            try fm.createSymbolicLink(at: destURL, withDestinationURL: sourceURL)
        } catch {
            AKError("""
                hs.ipc.installBinary(): Failed to create symlink at \(destURL.path): \(error.localizedDescription)
                If this is a permissions error, run the following in Terminal:
                  sudo ln -sf "\(sourceURL.path)" "\(destURL.path)"
                """)
            return false
        }

        AKInfo("hs.ipc: Created symlink \(destURL.path) → \(sourceURL.path)")
        return true
    }

    @objc func uninstallBinary(_ directoryVal: JSValue) -> Bool {
        let directory = directoryVal.isString ? directoryVal.toString()! : "/usr/local/bin"
        let destURL = URL(fileURLWithPath: directory).appendingPathComponent("hs2")
        let fm = FileManager.default

        guard let attrs = try? fm.attributesOfItem(atPath: destURL.path) else {
            AKWarning("hs.ipc.uninstallBinary(): Nothing found at \(destURL.path)")
            return false
        }
        guard (attrs[.type] as? FileAttributeType) == .typeSymbolicLink,
              let target = try? fm.destinationOfSymbolicLink(atPath: destURL.path),
              let sourceURL = bundledHSBinaryURL(),
              URL(fileURLWithPath: target, relativeTo: destURL.deletingLastPathComponent()).standardized.path == sourceURL.standardized.path else {
            AKError("hs.ipc.uninstallBinary(): \(destURL.path) is not a symlink to this Hammerspoon installation. Remove it manually.")
            return false
        }

        do {
            try fm.removeItem(at: destURL)
        } catch {
            AKError("hs.ipc.uninstallBinary(): Failed to remove \(destURL.path): \(error.localizedDescription)")
            return false
        }

        AKInfo("hs.ipc: Removed symlink at \(destURL.path)")
        return true
    }

    @objc func isBinaryInstalled(_ directoryVal: JSValue) -> Bool {
        let directory = directoryVal.isString ? directoryVal.toString()! : "/usr/local/bin"
        let destURL = URL(fileURLWithPath: directory).appendingPathComponent("hs2")
        let fm = FileManager.default

        guard let attrs = try? fm.attributesOfItem(atPath: destURL.path),
              (attrs[.type] as? FileAttributeType) == .typeSymbolicLink,
              let target = try? fm.destinationOfSymbolicLink(atPath: destURL.path),
              let sourceURL = bundledHSBinaryURL() else { return false }

        // Resolve relative to the symlink's directory so both absolute and relative
        // symlink destinations compare correctly against the bundle path.
        let resolvedTarget = URL(fileURLWithPath: target,
                                 relativeTo: destURL.deletingLastPathComponent()).standardized
        return resolvedTarget.path == sourceURL.standardized.path
    }

    // MARK: - Private

    private func bundledHSBinaryURL() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "hs2") {
            return url
        }
        if let execURL = Bundle.main.executableURL {
            let devURL = execURL.deletingLastPathComponent().appendingPathComponent("hs2")
            if FileManager.default.fileExists(atPath: devURL.path) {
                return devURL
            }
        }
        return nil
    }
}
