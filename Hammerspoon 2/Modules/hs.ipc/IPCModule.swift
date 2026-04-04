//
//  IPCModule.swift
//  Hammerspoon 2
//
//  Created on 2025-12-27.
//  IPC Module Implementation
//

import Foundation
import JavaScriptCore

/// Protocol for JavaScript export
@objc protocol HSIPCModuleAPI: JSExport {
    /// Create a local (server) message port
    /// - Parameters:
    ///   - name: The port name to register
    ///   - callback: A JavaScript function called when messages arrive
    /// - Returns: The created message port, or nil on failure
    @objc func localPort(_ name: String, _ callback: JSValue) -> HSMessagePort?

    /// Create a remote (client) message port
    /// - Parameter name: The name of the remote port to connect to
    /// - Returns: The created message port, or nil if the port doesn't exist
    @objc func remotePort(_ name: String) -> HSMessagePort?

    /// Install hs2 CLI tool via symlinks
    /// - Parameters:
    ///   - path: The installation prefix path, or nil for /usr/local
    ///   - silent: If true, suppress log messages
    /// - Returns: True if installation succeeded
    @objc func cliInstall(_ path: String?, _ silent: Bool) -> Bool

    /// Uninstall hs2 CLI tool symlinks
    /// - Parameters:
    ///   - path: The installation prefix path, or nil for /usr/local
    ///   - silent: If true, suppress log messages
    /// - Returns: True if uninstallation succeeded
    @objc func cliUninstall(_ path: String?, _ silent: Bool) -> Bool

    /// Check hs2 CLI tool installation status
    /// - Parameters:
    ///   - path: The installation prefix path, or nil for /usr/local
    ///   - silent: If true, suppress log messages
    /// - Returns: True if hs2 CLI is installed correctly
    @objc func cliStatus(_ path: String?, _ silent: Bool) -> Bool
}

/// IPC Module - Inter-process communication via CFMessagePort
@MainActor
@objc class HSIPCModule: NSObject, HSModuleAPI, HSIPCModuleAPI {
    // MARK: - HSModuleAPI

    var name = "hs.ipc"

    /// Weak references to all created ports for cleanup on shutdown
    private let activePorts = NSHashTable<HSMessagePort>.weakObjects()

    required override init() {
        super.init()
        AKTrace("IPC Module initialized")
    }

    func shutdown() {
        AKTrace("IPC Module shutting down")
        for port in activePorts.allObjects {
            port.delete()
        }
        activePorts.removeAllObjects()
    }

    // MARK: - Message Port API

    /// Create a local (server) message port
    /// - Parameters:
    ///   - name: The port name to register
    ///   - callback: A JavaScript function called when messages arrive
    /// - Returns: The created message port, or nil on failure
    @objc func localPort(_ name: String, _ callback: JSValue) -> HSMessagePort? {
        guard callback.isObject, !callback.isNull, !callback.isUndefined else {
            AKError("localPort: callback must be a callable function")
            return nil
        }

        let port = HSMessagePort(localPortName: name, callback: callback)
        if let port = port {
            activePorts.add(port)
        }
        return port
    }

    /// Create a remote (client) message port
    @objc func remotePort(_ name: String) -> HSMessagePort? {
        let port = HSMessagePort(remotePortName: name)
        if let port = port {
            activePorts.add(port)
        }
        return port
    }

    // MARK: - CLI Installation API

    /// Install hs2 CLI tool via symlinks
    @objc func cliInstall(_ path: String?, _ silent: Bool) -> Bool {
        let installPath = path ?? "/usr/local"
        let binPath = (installPath as NSString).appendingPathComponent("bin")
        let manPath = (installPath as NSString).appendingPathComponent("share/man/man1")

        // Get bundle paths
        let bundlePath = Bundle.main.bundlePath
        guard let binarySource = findHS2Binary(in: bundlePath),
              let manSource = findManPage(in: bundlePath) else {
            if !silent {
                AKError("cliInstall: Could not locate hs2 binary or man page in bundle")
            }
            return false
        }

        let binaryDest = (binPath as NSString).appendingPathComponent("hs2")
        let manDest = (manPath as NSString).appendingPathComponent("hs2.1")

        let fm = FileManager.default

        // Create directories if needed
        do {
            try fm.createDirectory(atPath: binPath, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: manPath, withIntermediateDirectories: true)
        } catch {
            if !silent {
                AKError("cliInstall: Failed to create directories: \(error.localizedDescription)")
            }
            return false
        }

        // Check if binary symlink exists
        var createdBinarySymlink = false
        if fm.fileExists(atPath: binaryDest) {
            // Check if it's our symlink
            if let existing = try? fm.destinationOfSymbolicLink(atPath: binaryDest),
               existing == binarySource {
                if !silent {
                    AKInfo("hs2 binary already installed at \(binaryDest)")
                }
            } else {
                if !silent {
                    AKError("cliInstall: File already exists at \(binaryDest)")
                }
                return false
            }
        } else {
            // Create binary symlink
            do {
                try fm.createSymbolicLink(atPath: binaryDest, withDestinationPath: binarySource)
                createdBinarySymlink = true
                if !silent {
                    AKInfo("Installed hs2 binary symlink: \(binaryDest) -> \(binarySource)")
                }
            } catch {
                if !silent {
                    AKError("cliInstall: Failed to create binary symlink: \(error.localizedDescription)")
                }
                return false
            }
        }

        // Check if man page symlink exists
        if fm.fileExists(atPath: manDest) {
            // Check if it's our symlink
            if let existing = try? fm.destinationOfSymbolicLink(atPath: manDest),
               existing == manSource {
                if !silent {
                    AKInfo("hs2 man page already installed at \(manDest)")
                }
            } else {
                if !silent {
                    AKError("cliInstall: File already exists at \(manDest)")
                }
                // Roll back binary symlink if we created it
                if createdBinarySymlink {
                    try? fm.removeItem(atPath: binaryDest)
                }
                return false
            }
        } else {
            // Create man page symlink
            do {
                try fm.createSymbolicLink(atPath: manDest, withDestinationPath: manSource)
                if !silent {
                    AKInfo("Installed hs2 man page symlink: \(manDest) -> \(manSource)")
                }
            } catch {
                if !silent {
                    AKError("cliInstall: Failed to create man page symlink: \(error.localizedDescription)")
                }
                // Roll back binary symlink if we created it
                if createdBinarySymlink {
                    try? fm.removeItem(atPath: binaryDest)
                }
                return false
            }
        }

        return true
    }

    /// Uninstall hs2 CLI tool symlinks
    @objc func cliUninstall(_ path: String?, _ silent: Bool) -> Bool {
        let installPath = path ?? "/usr/local"
        let binPath = (installPath as NSString).appendingPathComponent("bin")
        let manPath = (installPath as NSString).appendingPathComponent("share/man/man1")

        let binaryDest = (binPath as NSString).appendingPathComponent("hs2")
        let manDest = (manPath as NSString).appendingPathComponent("hs2.1")

        let fm = FileManager.default
        var success = true

        // Get our bundle path for validation
        let bundlePath = Bundle.main.bundlePath
        guard let binarySource = findHS2Binary(in: bundlePath),
              let manSource = findManPage(in: bundlePath) else {
            if !silent {
                AKError("cliUninstall: Could not locate hs2 binary or man page in bundle")
            }
            return false
        }

        // Remove binary symlink
        if fm.fileExists(atPath: binaryDest) {
            // Verify it points to our binary
            if let existing = try? fm.destinationOfSymbolicLink(atPath: binaryDest),
               existing == binarySource {
                do {
                    try fm.removeItem(atPath: binaryDest)
                    if !silent {
                        AKInfo("Removed hs2 binary symlink: \(binaryDest)")
                    }
                } catch {
                    if !silent {
                        AKError("cliUninstall: Failed to remove binary symlink: \(error.localizedDescription)")
                    }
                    success = false
                }
            } else {
                if !silent {
                    AKError("cliUninstall: Binary symlink does not point to current bundle")
                }
                success = false
            }
        } else {
            if !silent {
                AKInfo("Binary symlink not found at \(binaryDest)")
            }
        }

        // Remove man page symlink
        if fm.fileExists(atPath: manDest) {
            // Verify it points to our man page
            if let existing = try? fm.destinationOfSymbolicLink(atPath: manDest),
               existing == manSource {
                do {
                    try fm.removeItem(atPath: manDest)
                    if !silent {
                        AKInfo("Removed hs2 man page symlink: \(manDest)")
                    }
                } catch {
                    if !silent {
                        AKError("cliUninstall: Failed to remove man page symlink: \(error.localizedDescription)")
                    }
                    success = false
                }
            } else {
                if !silent {
                    AKError("cliUninstall: Man page symlink does not point to current bundle")
                }
                success = false
            }
        } else {
            if !silent {
                AKInfo("Man page symlink not found at \(manDest)")
            }
        }

        return success
    }

    /// Check hs2 CLI tool installation status
    @objc func cliStatus(_ path: String?, _ silent: Bool) -> Bool {
        let installPath = path ?? "/usr/local"
        let binPath = (installPath as NSString).appendingPathComponent("bin")
        let manPath = (installPath as NSString).appendingPathComponent("share/man/man1")

        let binaryDest = (binPath as NSString).appendingPathComponent("hs2")
        let manDest = (manPath as NSString).appendingPathComponent("hs2.1")

        let fm = FileManager.default

        // Get our bundle path for validation
        let bundlePath = Bundle.main.bundlePath
        guard let binarySource = findHS2Binary(in: bundlePath),
              let manSource = findManPage(in: bundlePath) else {
            if !silent {
                AKError("cliStatus: Could not locate hs2 binary or man page in bundle")
            }
            return false
        }

        // Check binary symlink
        var binaryInstalled = false
        if fm.fileExists(atPath: binaryDest) {
            if let existing = try? fm.destinationOfSymbolicLink(atPath: binaryDest),
               existing == binarySource {
                binaryInstalled = true
                if !silent {
                    AKInfo("hs2 binary installed: \(binaryDest) -> \(binarySource)")
                }
            } else {
                if !silent {
                    AKError("hs2 binary exists but points elsewhere: \(binaryDest)")
                }
            }
        } else {
            if !silent {
                AKInfo("hs2 binary not installed at \(binaryDest)")
            }
        }

        // Check man page symlink
        var manInstalled = false
        if fm.fileExists(atPath: manDest) {
            if let existing = try? fm.destinationOfSymbolicLink(atPath: manDest),
               existing == manSource {
                manInstalled = true
                if !silent {
                    AKInfo("hs2 man page installed: \(manDest) -> \(manSource)")
                }
            } else {
                if !silent {
                    AKError("hs2 man page exists but points elsewhere: \(manDest)")
                }
            }
        } else {
            if !silent {
                AKInfo("hs2 man page not installed at \(manDest)")
            }
        }

        return binaryInstalled && manInstalled
    }

    // MARK: - Helper Methods

    /// Find hs2 binary in bundle
    private func findHS2Binary(in bundlePath: String) -> String? {
        // Try standard location: Contents/Frameworks/hs2/hs2
        let standardPath = (bundlePath as NSString)
            .appendingPathComponent("Contents/Frameworks/hs2/hs2")

        if FileManager.default.fileExists(atPath: standardPath) {
            return standardPath
        }

        // Alternative: Contents/MacOS/hs2
        let altPath = (bundlePath as NSString)
            .appendingPathComponent("Contents/MacOS/hs2")

        if FileManager.default.fileExists(atPath: altPath) {
            return altPath
        }

        return nil
    }

    /// Find man page in bundle
    private func findManPage(in bundlePath: String) -> String? {
        // Try standard location: Contents/Resources/man/hs2.1
        let standardPath = (bundlePath as NSString)
            .appendingPathComponent("Contents/Resources/man/hs2.1")

        if FileManager.default.fileExists(atPath: standardPath) {
            return standardPath
        }

        // Alternative: Contents/Resources/hs2.1
        let altPath = (bundlePath as NSString)
            .appendingPathComponent("Contents/Resources/hs2.1")

        if FileManager.default.fileExists(atPath: altPath) {
            return altPath
        }

        return nil
    }
}
