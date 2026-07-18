//
//  HSIPCModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// Module for enabling CLI access to Hammerspoon 2 via the `hs` command-line tool.
///
/// The IPC server must be explicitly started from your configuration — it does not run by default.
/// Once started, the `hs` command-line tool connects via XPC and evaluates JavaScript
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
/// hs.ipc.installBinary()   // symlinks hs to /usr/local/bin/hs
/// ```
///
/// Then in a terminal:
/// ```bash
/// hs
/// hs> hs.reload()
/// undefined
/// hs> 2 + 2
/// 4
/// ```
///
/// Run with live log output:
/// ```bash
/// hs --log-level info
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

    /// Install the `hs` command-line tool to the given directory as a symlink.
    ///
    /// Creates a symlink in the target directory that points to the `hs` binary inside the
    /// Hammerspoon 2 app bundle. Using a symlink means the CLI automatically reflects any
    /// app update without reinstalling. Any existing `hs` file at that path is replaced.
    ///
    /// The directory must be on your `$PATH` for `hs` to work without a full path.
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
    /// hs.ipc.installBinary()                   // install to /usr/local/bin/hs
    /// hs.ipc.installBinary("/opt/homebrew/bin") // install to /opt/homebrew/bin/hs
    /// ```
    @objc func installBinary(_ directory: JSValue) -> Bool

    /// Remove the `hs` command-line tool from the given directory.
    ///
    /// - Parameter directory: {string} Directory to remove from. Defaults to `/usr/local/bin`.
    /// - Returns: `true` on success, `false` if not found or on error.
    /// - Example:
    /// ```js
    /// hs.ipc.uninstallBinary()
    /// hs.ipc.uninstallBinary("/opt/homebrew/bin")
    /// ```
    @objc func uninstallBinary(_ directory: JSValue) -> Bool

    /// Check whether the `hs` command-line tool exists at the given directory.
    ///
    /// - Parameter directory: {string} Directory to check. Defaults to `/usr/local/bin`.
    /// - Returns: `true` if an `hs` binary exists at that path.
    /// - Example:
    /// ```js
    /// if (hs.ipc.isBinaryInstalled()) {
    ///     console.log("hs CLI is available")
    /// }
    /// ```
    @objc func isBinaryInstalled(_ directory: JSValue) -> Bool
}

// MARK: - Implementation

@safe @MainActor
@_documentation(visibility: private)
@objc class HSIPCModule: NSObject, HSModuleAPI, HSIPCModuleAPI {
    var name = "hs.ipc"
    let engineID: UUID

    private var server: HSIPCServer?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        server?.stop()
        server = nil
    }

    isolated deinit {
        shutdown()
        AKDebug("Deinit of \(name): \(engineID)")
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
            AKError("hs.ipc.installBinary(): Cannot find 'hs' binary in the app bundle. Ensure the 'hs' target has been built.")
            return false
        }

        let destURL = URL(fileURLWithPath: directory).appendingPathComponent("hs")
        let fm = FileManager.default

        if let attrs = try? fm.attributesOfItem(atPath: destURL.path) {
            guard (attrs[.type] as? FileAttributeType) == .typeSymbolicLink else {
                AKError("hs.ipc.installBinary(): \(destURL.path) already exists and is not a symlink. Remove it manually before installing.")
                return false
            }
            do {
                try fm.removeItem(at: destURL)
            } catch {
                AKError("hs.ipc.installBinary(): Failed to remove existing symlink at \(destURL.path): \(error.localizedDescription)")
                return false
            }
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
        let destURL = URL(fileURLWithPath: directory).appendingPathComponent("hs")
        let fm = FileManager.default

        guard let attrs = try? fm.attributesOfItem(atPath: destURL.path) else {
            AKWarning("hs.ipc.uninstallBinary(): Nothing found at \(destURL.path)")
            return false
        }
        guard (attrs[.type] as? FileAttributeType) == .typeSymbolicLink else {
            AKError("hs.ipc.uninstallBinary(): \(destURL.path) exists but is not a symlink. Remove it manually.")
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
        let path = URL(fileURLWithPath: directory).appendingPathComponent("hs").path
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Private

    private func bundledHSBinaryURL() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "hs") {
            return url
        }
        if let execURL = Bundle.main.executableURL {
            let devURL = execURL.deletingLastPathComponent().appendingPathComponent("hs")
            if FileManager.default.fileExists(atPath: devURL.path) {
                return devURL
            }
        }
        return nil
    }
}
