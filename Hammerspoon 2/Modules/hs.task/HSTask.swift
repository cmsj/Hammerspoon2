//
//  HSTask.swift
//  Hammerspoon 2
//
//  Created by Claude on 03/02/2026.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

/// Object representing an external process task
@objc protocol HSTaskAPI: HSTypeAPI, JSExport {
    /// The process ID of the running task
    /// - Returns: The PID, or -1 if the task is not running
    @objc func pid() -> Int32

    /// Check if the task is currently running
    /// - Returns: true if the task is running, false otherwise
    @objc func isRunning() -> Bool

    /// Start the task
    /// - Returns: The task object for chaining
    @objc func start() -> HSTask

    /// Terminate the task
    @objc func terminate()

    /// Interrupt the task (send SIGINT)
    @objc func interrupt()

    /// Pause the task (send SIGSTOP)
    @objc func pause()

    /// Resume the task (send SIGCONT)
    @objc func resume()

    /// Wait for the task to complete (blocking)
    @objc func waitUntilExit()

    /// Write data to the task's stdin
    /// - Parameter data: The string data to write
    @objc func sendInput(_ data: String)

    /// Close the task's stdin
    @objc func closeInput()

    /// Get the task's environment variables
    /// - Returns: A dictionary of environment variables
    @objc func environment() -> [String: String]

    /// Set an environment variable for the task (must be called before start())
    /// - Parameters:
    ///   - key: The environment variable name
    ///   - value: The environment variable value
    @objc func setEnvironmentVariable(_ key: String, _ value: String)

    /// Get the working directory of the task
    /// - Returns: The current working directory path
    @objc func workingDirectory() -> String?

    /// Set the working directory for the task (must be called before start())
    /// - Parameter path: The directory path
    @objc func setWorkingDirectory(_ path: String)

    /// Get the termination status of the task
    /// - Returns: The exit code, or nil if the task hasn't terminated
    @objc func terminationStatus() -> NSNumber?

    /// Get the termination reason
    /// - Returns: A string describing why the task terminated, or nil if still running
    @objc func terminationReason() -> String?
}

@_documentation(visibility: private)
@objc class HSTask: NSObject, HSTaskAPI {
    @objc var typeName = "HSTask"

    private let launchPath: String
    private let arguments: [String]
    private var env: [String: String]
    private var workingDir: String?
    private let terminationCallback: JSValue?
    private let streamingCallback: JSValue?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?

    private var hasStarted = false
    private var exitCode: Int32?
    private var exitReason: String?

    init(launchPath: String, arguments: [String], environment: [String: String]?, terminationCallback: JSValue?, streamingCallback: JSValue?) {
        self.launchPath = launchPath
        self.arguments = arguments
        self.env = environment ?? ProcessInfo.processInfo.environment
        self.terminationCallback = terminationCallback
        self.streamingCallback = streamingCallback
        super.init()
    }

    isolated deinit {
        if let process = process, process.isRunning {
            process.terminate()
        }
        print("deinit of HSTask: \(launchPath)")
    }

    @objc func pid() -> Int32 {
        return process?.processIdentifier ?? -1
    }

    @objc func isRunning() -> Bool {
        return process?.isRunning ?? false
    }

    @objc func start() -> HSTask {
        guard !hasStarted else {
            AKWarning("hs.task:start(): Task has already been started")
            return self
        }

        hasStarted = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = env

        if let workingDir = workingDir {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }

        // Set up pipes for stdin, stdout, stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.stdinPipe = stdinPipe

        // Set up streaming callbacks if provided
        if let streamingCallback = streamingCallback {
            setupStreamingCallbacks(stdout: stdoutPipe, stderr: stderrPipe, callback: streamingCallback)
        }

        // Set up termination handler
        process.terminationHandler = { [weak self] process in
            guard let self = self else { return }

            Task { @MainActor in
                self.exitCode = process.terminationStatus
                self.exitReason = self.getTerminationReasonString(process.terminationReason)

                // Call termination callback if provided
                if let callback = self.terminationCallback, callback.isFunction {
                    callback.call(withArguments: [process.terminationStatus, self.exitReason ?? "unknown"])
                    
                    // Check for JavaScript errors
                    if let context = callback.context,
                       let exception = context.exception,
                       !exception.isUndefined {
                        AKError("hs.task: Error in termination callback: \(exception.toString() ?? "unknown error")")
                        context.exception = nil
                    }
                }
            }
        }

        // Launch the process
        do {
            try process.run()
        } catch {
            AKError("hs.task:start(): Failed to start task: \(error.localizedDescription)")
        }

        return self
    }

    @objc func terminate() {
        process?.terminate()
    }

    @objc func interrupt() {
        process?.interrupt()
    }

    @objc func pause() {
        guard let process = process, process.isRunning else { return }
        kill(process.processIdentifier, SIGSTOP)
    }

    @objc func resume() {
        guard let process = process, process.isRunning else { return }
        kill(process.processIdentifier, SIGCONT)
    }

    @objc func waitUntilExit() {
        process?.waitUntilExit()
    }

    @objc func sendInput(_ data: String) {
        guard let stdinPipe = stdinPipe else {
            AKWarning("hs.task:sendInput(): stdin pipe not available")
            return
        }

        if let dataToWrite = data.data(using: .utf8) {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: dataToWrite)
            } catch {
                AKError("hs.task:sendInput(): Failed to write to stdin: \(error.localizedDescription)")
            }
        }
    }

    @objc func closeInput() {
        do {
            try stdinPipe?.fileHandleForWriting.close()
        } catch {
            AKError("hs.task:closeInput(): Failed to close stdin: \(error.localizedDescription)")
        }
    }

    @objc func environment() -> [String: String] {
        return env
    }

    @objc func setEnvironmentVariable(_ key: String, _ value: String) {
        guard !hasStarted else {
            AKWarning("hs.task:setEnvironmentVariable(): Cannot set environment after task has started")
            return
        }
        env[key] = value
    }

    @objc func workingDirectory() -> String? {
        return workingDir
    }

    @objc func setWorkingDirectory(_ path: String) {
        guard !hasStarted else {
            AKWarning("hs.task:setWorkingDirectory(): Cannot set working directory after task has started")
            return
        }
        workingDir = path
    }

    @objc func terminationStatus() -> NSNumber? {
        guard let exitCode = exitCode else { return nil }
        return NSNumber(value: exitCode)
    }

    @objc func terminationReason() -> String? {
        return exitReason
    }

    // MARK: - Private helpers

    private func setupStreamingCallbacks(stdout: Pipe, stderr: Pipe, callback: JSValue) {
        // Set up stdout reading
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak callback] handle in
            guard let self = self, let callback = callback else { return }

            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    callback.call(withArguments: ["stdout", output])

                    // Check for JavaScript errors
                    if let context = callback.context,
                       let exception = context.exception,
                       !exception.isUndefined {
                        AKError("hs.task: Error in streaming callback: \(exception.toString() ?? "unknown error")")
                        context.exception = nil
                    }
                }
            }
        }

        // Set up stderr reading
        stderr.fileHandleForReading.readabilityHandler = { [weak self, weak callback] handle in
            guard let self = self, let callback = callback else { return }

            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    callback.call(withArguments: ["stderr", output])

                    // Check for JavaScript errors
                    if let context = callback.context,
                       let exception = context.exception,
                       !exception.isUndefined {
                        AKError("hs.task: Error in streaming callback: \(exception.toString() ?? "unknown error")")
                        context.exception = nil
                    }
                }
            }
        }
    }

    private func getTerminationReasonString(_ reason: Process.TerminationReason) -> String {
        switch reason {
        case .exit:
            return "exit"
        case .uncaughtSignal:
            return "uncaughtSignal"
        @unknown default:
            return "unknown"
        }
    }
}
