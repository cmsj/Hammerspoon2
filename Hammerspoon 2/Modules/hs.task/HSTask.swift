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
    /// Start the task
    /// - Returns: The task object for chaining
    @objc func start() -> HSTask

    /// Terminate the task (send SIGTERM)
    @objc func terminate()

    /// Terminate the task with extreme prejudice (send SIGKILL)
    @objc func kill9()

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

    /// Check if the task is currently running
    /// - Note: true if the task is running, false otherwise
    @objc var isRunning: Bool { get }

    /// The process ID of the running task
    /// - Note: The value will be -1 if the task is not running
    @objc var pid: Int32 { get }

    /// The environment variables for the task
    /// - Note: Can only be modified before calling start()
    @objc var environment: [String: String] { get set }

    /// The working directory for the task
    /// - Note: Can only be modified before calling start()
    @objc var workingDirectory: String? { get set }

    /// Get the termination status of the task
    /// - Returns: The exit code, or nil if the task hasn't terminated
    @objc func terminationStatus() -> NSNumber?

    /// Get the termination reason
    /// - Returns: A string describing why the task terminated, or nil if still running
    @objc func terminationReason() -> String?

    /// SKIP_DOCS
    @objc func _shutdown()
}

@_documentation(visibility: private)
@objc class HSTask: NSObject, HSTaskAPI {
    @objc var typeName = "HSTask"

    private let launchPath: String
    private let arguments: [String]
    private var _environment: [String: String]
    private var _workingDirectory: String?
    private let terminationCallback: JSValue?
    private let streamingCallback: JSValue?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?

    private var hasStarted = false
    private var exitCode: Int32?
    private var exitReason: String?

    /// The environment variables for the task
    @objc var environment: [String: String] {
        get { _environment }
        set {
            guard !hasStarted else {
                AKWarning("hs.task.environment: Cannot modify environment after task has started")
                return
            }
            _environment = newValue
        }
    }

    /// The working directory for the task
    @objc var workingDirectory: String? {
        get { _workingDirectory }
        set {
            guard !hasStarted else {
                AKWarning("hs.task.workingDirectory: Cannot modify working directory after task has started")
                return
            }
            _workingDirectory = newValue
        }
    }

    @objc var pid: Int32 {
        process?.processIdentifier ?? -1
    }

    @objc var isRunning: Bool {
        return process?.isRunning ?? false
    }

    init(launchPath: String, arguments: [String], environment: [String: String]?, terminationCallback: JSValue?, streamingCallback: JSValue?) {
        self.launchPath = launchPath
        self.arguments = arguments
        self._environment = environment ?? ProcessInfo.processInfo.environment
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

    @objc func start() -> HSTask {
        guard !hasStarted else {
            AKWarning("hs.task:start(): Task has already been started")
            return self
        }

        hasStarted = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = _environment

        if let workingDir = _workingDirectory {
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
        if streamingCallback != nil {
            setupStreamingCallbacks(stdout: stdoutPipe, stderr: stderrPipe)
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

    // This is called when HS is restarting/exiting, to clean up this HSTask.
    // We will send it a SIGTERM, then attempt to wait a few seconds and send a SIGKILL.
    // FIXME: When HS is exiting, the SIGKILL tasks likely won't ever get called.
    @objc func _shutdown() {
        guard let process, process.isRunning else { return }

        let pid = process.processIdentifier

        terminate()
        Task.detached {
            try? await Task.sleep(for: .seconds(5))

            kill(pid, SIGKILL)
        }
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

    @objc func kill9() {
        guard let process = process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
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

    @objc func terminationStatus() -> NSNumber? {
        guard let exitCode = exitCode else { return nil }
        return NSNumber(value: exitCode)
    }

    @objc func terminationReason() -> String? {
        return exitReason
    }

    // MARK: - Private helpers

    private func setupStreamingCallbacks(stdout: Pipe, stderr: Pipe) {
        // Set up stdout reading
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }

            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    guard let callback = self.streamingCallback else { return }
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
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }

            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    guard let callback = self.streamingCallback else { return }
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
