//
//  HSShortcutsModule.swift
//  Hammerspoon 2
//

import AppKit
import Foundation
import JavaScriptCore
import ScriptingBridge
import HammerspoonSDK

// MARK: - ScriptingBridge Protocols

@objc private protocol ShortcutsBridgeApp {
    @objc optional var shortcuts: SBElementArray { get }
}

extension SBApplication: ShortcutsBridgeApp {}

// MARK: - JavaScript API

/// Run and interact with macOS Shortcuts from JavaScript.
///
/// This module bridges to the Shortcuts app, letting you enumerate available
/// shortcuts and run them from your Hammerspoon configuration.
///
/// ## Listing shortcuts
/// ```js
/// const all = hs.shortcuts.list()
/// all.forEach(s => console.log(s.name + " (accepts input: " + s.acceptsInput + ")"))
/// ```
///
/// ## Running a shortcut
/// ```js
/// hs.shortcuts.run("My Shortcut").then(output => {
///     if (output) console.log("Output: " + output)
/// }).catch(err => console.log("Error: " + err))
/// ```
///
/// ## Opening a shortcut for editing
/// ```js
/// hs.shortcuts.open("My Shortcut")
/// ```
@objc protocol HSShortcutsModuleAPI: JSExport {

    /// Returns an array of all available shortcuts.
    ///
    /// Each entry is a plain object with the following keys:
    ///
    /// | Key | Type | Description |
    /// |-----|------|-------------|
    /// | `name` | `string` | The display name of the shortcut |
    /// | `id` | `string` | A UUID uniquely identifying the shortcut |
    /// | `acceptsInput` | `boolean` | Whether the shortcut expects input when run |
    /// | `actionCount` | `number` | How many actions the shortcut contains |
    ///
    /// The shortcuts are read from Shortcuts Events, so Hammerspoon needs the Automation
    /// permission for it; macOS asks the first time. An empty array means there are no
    /// shortcuts: when they can't be read (the permission is denied, or nobody answers its
    /// prompt within 2 minutes), `list()` throws instead.
    ///
    /// - Returns: An array of shortcut descriptor objects.
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     hs.shortcuts.list().forEach(s => console.log(s.name))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func list() -> [[String: Any]]

    /// Runs a Shortcuts shortcut by name and returns any output.
    ///
    /// Executes the shortcut in the background via the `shortcuts` CLI tool.
    /// If the shortcut produces output (via a "Stop and Output" action), the
    /// Promise resolves with that string. If the shortcut produces no output,
    /// the Promise resolves with `null`. The Promise rejects if the shortcut
    /// cannot be found or exits with a non-zero status.
    ///
    /// - Parameter name: The exact display name of the shortcut to run.
    /// - Returns: {Promise<string|null>} A Promise resolving to the shortcut output string, or `null` if the shortcut produced no output.
    /// - Example:
    /// ```js
    /// hs.shortcuts.run("My Shortcut")
    ///     .then(output => console.log("Done, output: " + output))
    ///     .catch(err => console.log("Failed: " + err))
    /// ```
    @objc func run(_ name: String) -> JSPromise?

    /// Opens a shortcut in the Shortcuts app for viewing or editing.
    ///
    /// Uses the `shortcuts://open-shortcut` URL scheme to bring Shortcuts to
    /// the foreground and navigate directly to the named shortcut.
    ///
    /// - Parameter name: The display name of the shortcut to open.
    /// - Example:
    /// ```js
    /// hs.shortcuts.open("My Shortcut")
    /// ```
    @objc func open(_ name: String)
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSShortcutsModule: NSObject, HSModuleAPI, HSShortcutsModuleAPI {
    var moduleName = "hs.shortcuts"
    let engineID: UUID
    private var runningProcesses: [Process] = []
    private var isShutdown = false

    /// Hands `open()`'s URL to the system. Tests replace it to check the URL without the
    /// Shortcuts app coming up.
    var urlOpener: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// The app `list()` asks for the shortcuts. Tests point it at an app that isn't there to
    /// check that a failure throws.
    var shortcutsEventsBundleID = "com.apple.shortcuts.events"

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        isShutdown = true
        for process in runningProcesses { process.terminate() }
        runningProcesses.removeAll()
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = runningProcesses.count
        return "<\(moduleName): \(n) running process\(n == 1 ? "" : "es")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Public API

    @objc func list() -> [[String: Any]] {
        guard let app = SBApplication(bundleIdentifier: shortcutsEventsBundleID) else {
            return listFailed("Failed to connect to Shortcuts Events")
        }

        guard let shortcuts = (app as ShortcutsBridgeApp).shortcuts else {
            return listFailed("No shortcuts property returned by Shortcuts Events")
        }

        var result: [[String: Any]] = []
        for element in shortcuts {
            let obj = element as AnyObject
            let shortcutName = obj.value(forKey: "name") as? String ?? ""
            let shortcutID = obj.value(forKey: "id") as? String ?? ""
            let acceptsInput = obj.value(forKey: "acceptsInput") as? Bool ?? false
            let actionCount = obj.value(forKey: "actionCount") as? Int ?? 0
            result.append([
                "name": shortcutName,
                "id": shortcutID,
                "acceptsInput": acceptsInput,
                "actionCount": actionCount
            ])
        }
        // A failed Apple Event leaves the element array empty, which would look like a library
        // with no shortcuts; only the app knows about the error.
        if let error = app.lastError() {
            return listFailed(Self.describeAppleEventError(error))
        }
        AKDebug("hs.shortcuts.list(): Returned \(result.count) shortcuts")
        return result
    }

    @objc func run(_ name: String) -> JSPromise? {
        guard let context = JSContext.current() else {
            AKError("hs.shortcuts.run(): Called outside a JS context")
            return nil
        }
        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                do {
                    let (output, exitCode) = try await self.runCLI(shortcutName: name)
                    guard !self.isShutdown else { return }
                    if exitCode == 0 {
                        let value: Any = output?.isEmpty == false ? output as Any : NSNull()
                        holder.resolveWith(value)
                    } else {
                        let message = output?.isEmpty == false
                        // swiftlint:disable:next force_unwrapping
                            ? output!
                            : "Shortcut '\(name)' failed with exit code \(exitCode)"
                        AKDebug("hs.shortcuts.run(): '\(name)' rejected: \(message)")
                        holder.rejectWithMessage(message)
                    }
                } catch {
                    guard !self.isShutdown else { return }
                    AKError("hs.shortcuts.run(): '\(name)' threw: \(error.localizedDescription)")
                    holder.rejectWithMessage("Failed to run shortcut '\(name)': \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func open(_ name: String) {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "open-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else {
            AKError("hs.shortcuts.open(): Failed to construct URL for '\(name)'")
            return
        }
        urlOpener(url)
        AKDebug("hs.shortcuts.open(): Opened '\(name)'")
    }

    // MARK: - Private Helpers

    /// Logs why `list()` failed and throws it to the JS caller.
    private func listFailed(_ reason: String) -> [[String: Any]] {
        let message = "hs.shortcuts.list(): \(reason)"
        AKError(message)
        if let context = JSContext.current() {
            context.exception = JSValue(newErrorFromMessage: message, in: context)
        }
        return []
    }

    private static func describeAppleEventError(_ error: Error) -> String {
        switch (error as NSError).code {
        case -1743: // errAEEventNotPermitted
            return "Not allowed to control Shortcuts Events; allow it in System Settings > Privacy & Security > Automation"
        case -1712: // errAETimeout
            return "Shortcuts Events did not answer in time (is an Automation permission prompt waiting?)"
        default:
            return "Shortcuts Events returned an error: \(error.localizedDescription) (\((error as NSError).code))"
        }
    }

    private func runCLI(shortcutName: String) async throws -> (String?, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", shortcutName]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        runningProcesses.append(process)

        // Drain both pipes concurrently on background threads so the child process
        // never blocks on a full pipe buffer before it exits.
        async let outData = Self.readPipe(outputPipe)
        async let errData = Self.readPipe(errorPipe)
        let (out, err) = await (outData, errData)
        process.waitUntilExit()   // by now the process has already exited (pipes at EOF)
        runningProcesses.removeAll { $0 === process }

        let outStr = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let errStr = String(data: err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // On success return stdout; on failure return stderr (or stdout if stderr is empty)
        let output = process.terminationStatus == 0 ? outStr : (errStr?.isEmpty == false ? errStr : outStr)
        return (output, process.terminationStatus)
    }

    nonisolated private static func readPipe(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
    }
}
