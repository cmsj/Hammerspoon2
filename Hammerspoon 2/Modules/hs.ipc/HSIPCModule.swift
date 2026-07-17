//
//  HSIPCModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// Module for enabling CLI access to Hammerspoon 2 via the `hs` command-line tool.
///
/// The IPC server must be explicitly started from your configuration — it does not run by default.
/// Once started, the `hs` command-line tool connects over TCP to evaluate JavaScript interactively
/// and optionally stream log messages.
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
/// hs.ipc.installBinary()   // copies hs to /usr/local/bin/hs
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
    ///     console.log("IPC ready on port " + hs.ipc.port)
    /// }
    /// ```
    @objc var isListening: Bool { get }

    /// The TCP port the IPC server is listening on. Returns `0` if not listening.
    ///
    /// - Example:
    /// ```js
    /// console.log("IPC port: " + hs.ipc.port)
    /// ```
    @objc var port: Int32 { get }

    /// Start the IPC server.
    ///
    /// Connections are only accepted from localhost (127.0.0.1). Calling `start()` when already
    /// running logs a warning and does nothing.
    ///
    /// - Parameter port: {number} TCP port to listen on. Defaults to `51423` if omitted.
    /// - Example:
    /// ```js
    /// hs.ipc.start()        // listen on default port 51423
    /// hs.ipc.start(9999)    // listen on port 9999
    /// ```
    @objc func start(_ port: JSValue)

    /// Stop the IPC server and disconnect all connected clients.
    ///
    /// - Example:
    /// ```js
    /// hs.ipc.stop()
    /// ```
    @objc func stop()

    /// Install the `hs` command-line tool to the given directory.
    ///
    /// Copies the `hs` binary from the Hammerspoon 2 app bundle to the specified directory.
    /// Any existing `hs` file at that path is replaced. The directory must be on your `$PATH`
    /// for `hs` to work without a full path.
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

    @objc var port: Int32 { server?.currentPort ?? 0 }

    @objc func start(_ portVal: JSValue) {
        guard server == nil else {
            AKWarning("hs.ipc.start(): Already listening on port \(port)")
            return
        }
        let portNum: UInt16 = portVal.isNumber ? UInt16(clamping: portVal.toInt32()) : 51423
        let newServer = HSIPCServer()
        do {
            try newServer.start(port: portNum)
            server = newServer
        } catch {
            AKError("hs.ipc.start(): Failed to start on port \(portNum): \(error.localizedDescription)")
        }
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

        if fm.fileExists(atPath: destURL.path) {
            do {
                try fm.removeItem(at: destURL)
            } catch {
                AKError("hs.ipc.installBinary(): Failed to remove existing file at \(destURL.path): \(error.localizedDescription)")
                return false
            }
        }

        do {
            try fm.copyItem(at: sourceURL, to: destURL)
            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: destURL.path)
        } catch {
            AKError("hs.ipc.installBinary(): Failed to install to \(destURL.path): \(error.localizedDescription)")
            return false
        }

        AKInfo("hs.ipc: Installed 'hs' binary to \(destURL.path)")
        return true
    }

    @objc func uninstallBinary(_ directoryVal: JSValue) -> Bool {
        let directory = directoryVal.isString ? directoryVal.toString()! : "/usr/local/bin"
        let destURL = URL(fileURLWithPath: directory).appendingPathComponent("hs")

        guard FileManager.default.fileExists(atPath: destURL.path) else {
            AKWarning("hs.ipc.uninstallBinary(): No 'hs' binary found at \(destURL.path)")
            return false
        }

        do {
            try FileManager.default.removeItem(at: destURL)
        } catch {
            AKError("hs.ipc.uninstallBinary(): Failed to remove \(destURL.path): \(error.localizedDescription)")
            return false
        }

        AKInfo("hs.ipc: Removed 'hs' binary from \(destURL.path)")
        return true
    }

    @objc func isBinaryInstalled(_ directoryVal: JSValue) -> Bool {
        let directory = directoryVal.isString ? directoryVal.toString()! : "/usr/local/bin"
        let path = URL(fileURLWithPath: directory).appendingPathComponent("hs").path
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Private

    private func bundledHSBinaryURL() -> URL? {
        // Production: embedded next to the main executable in Contents/MacOS/
        if let url = Bundle.main.url(forAuxiliaryExecutable: "hs") {
            return url
        }
        // Development fallback: look next to the Hammerspoon 2 executable
        if let execURL = Bundle.main.executableURL {
            let devURL = execURL.deletingLastPathComponent().appendingPathComponent("hs")
            if FileManager.default.fileExists(atPath: devURL.path) {
                return devURL
            }
        }
        return nil
    }
}
