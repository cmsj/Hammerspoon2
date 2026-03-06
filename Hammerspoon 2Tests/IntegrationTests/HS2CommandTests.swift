//
//  HS2CommandTests.swift
//  Hammerspoon 2Tests
//
//  Created on 2025-12-28.
//  Integration tests for hs2 command-line tool
//

import XCTest
@testable import Hammerspoon_2

/// Integration tests for the hs2 command-line tool
///
/// These tests verify that the hs2 CLI tool works correctly by:
/// - Launching Hammerspoon 2.app
/// - Executing hs2 commands
/// - Verifying output and behavior
///
/// Requirements:
/// - Hammerspoon 2.app must be built and available
/// - hs2 binary must be built and available
/// - Tests run sequentially to avoid port conflicts
nonisolated class HS2CommandTests: XCTestCase {

    // MARK: - Properties

    /// Path to Hammerspoon 2.app built binary
    private var hammerspoonAppPath: String {
        // Assumes we're running from Xcode DerivedData
        let derivedData = ProcessInfo.processInfo.environment["BUILD_DIR"] ?? ""
        let path = (derivedData as NSString).appendingPathComponent("../Debug/Hammerspoon 2.app")
        return (path as NSString).standardizingPath
    }

    /// Path to hs2 built binary
    private var hs2BinaryPath: String {
        let derivedData = ProcessInfo.processInfo.environment["BUILD_DIR"] ?? ""
        let path = (derivedData as NSString).appendingPathComponent("../Debug/hs2")
        return (path as NSString).standardizingPath
    }

    /// Process handle for Hammerspoon 2 app
    private var hammerspoonProcess: Process?

    /// Timeout for waiting for Hammerspoon to start
    private let startupTimeout: TimeInterval = 5.0

    /// Timeout for hs2 commands
    private let commandTimeout: TimeInterval = 4.0

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()

        // Verify binaries exist
        let fm = FileManager.default
        let hammerspoonPath = hammerspoonAppPath
        let hs2Path = hs2BinaryPath

        XCTAssertTrue(fm.fileExists(atPath: hammerspoonPath),
                     "Hammerspoon 2.app not found at \(hammerspoonPath)")
        XCTAssertTrue(fm.fileExists(atPath: hs2Path),
                     "hs2 binary not found at \(hs2Path)")

        // Kill any existing Hammerspoon processes
        killExistingHammerspoon()

        // Launch Hammerspoon 2
        startHammerspoon()

        // Wait for it to be ready
        waitForHammerspoonReady()
    }

    override func tearDown() {
        // Stop Hammerspoon
        stopHammerspoon()
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Kill any existing Hammerspoon 2 processes
    private func killExistingHammerspoon() {
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProcess.arguments = ["-9", "Hammerspoon 2"]
        try? killProcess.run()
        killProcess.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Start Hammerspoon 2.app
    private func startHammerspoon() {
        hammerspoonProcess = Process()
        hammerspoonProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        hammerspoonProcess?.arguments = [hammerspoonAppPath]

        do {
            try hammerspoonProcess?.run()
        } catch {
            XCTFail("Failed to launch Hammerspoon 2: \(error)")
        }
    }

    /// Wait for Hammerspoon to be ready to accept IPC connections
    private func waitForHammerspoonReady() {
        let deadline = Date().addingTimeInterval(startupTimeout)

        while Date() < deadline {
            // Try a simple command to see if Hammerspoon responds
            let (_, _, exitCode) = runHS2Command(["-c", "print('ready')"], quiet: true)
            if exitCode == 0 {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTFail("Hammerspoon did not become ready within \(startupTimeout) seconds")
    }

    /// Stop Hammerspoon 2.app
    private func stopHammerspoon() {
        if let process = hammerspoonProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        killExistingHammerspoon()
    }

    /// Run an hs2 command and return stdout, stderr, and exit code
    /// - Parameters:
    ///   - arguments: Command-line arguments for hs2
    ///   - quiet: If true, uses -q flag to suppress debug output
    ///   - timeout: Maximum time to wait for command completion
    /// - Returns: Tuple of (stdout, stderr, exitCode)
    @discardableResult
    private func runHS2Command(_ arguments: [String],
                               quiet: Bool = false,
                               timeout: TimeInterval? = nil) -> (String, String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hs2BinaryPath)

        var args = arguments
        if quiet && !args.contains("-q") {
            args.insert("-q", at: 0)
        }
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            // Wait with timeout
            let timeoutInterval = timeout ?? commandTimeout
            let deadline = Date().addingTimeInterval(timeoutInterval)

            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if process.isRunning {
                process.terminate()
                XCTFail("Command timed out after \(timeoutInterval) seconds")
            }

            process.waitUntilExit()

        } catch {
            XCTFail("Failed to run hs2 command: \(error)")
        }

        // Read pipe data synchronously after process exits to avoid data races
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return (stdout, stderr, process.terminationStatus)
    }

    /// Run hs2 with JavaScript code and return output
    /// - Parameters:
    ///   - code: JavaScript code to execute
    ///   - quiet: If true, uses -q flag
    /// - Returns: Standard output from the command
    private func evalCode(_ code: String, quiet: Bool = true) -> String {
        let (stdout, _, _) = runHS2Command(["-c", code], quiet: quiet)
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Basic Functionality Tests

    func testSimplePrint() {
        let output = evalCode("print('Hello, World!')")
        XCTAssertEqual(output, "Hello, World!", "Should print simple string")
    }

    func testMultipleStatements() {
        let code = """
        print('Line 1');
        print('Line 2');
        print('Line 3');
        """
        let output = evalCode(code)
        XCTAssertEqual(output, "Line 1\nLine 2\nLine 3", "Should execute multiple statements")
    }

    func testMathOperations() {
        let output = evalCode("print(2 + 2)")
        XCTAssertEqual(output, "4", "Should perform math operations")
    }

    func testJavaScriptFunctions() {
        let code = """
        function greet(name) {
            return 'Hello, ' + name;
        }
        print(greet('hs2'));
        """
        let output = evalCode(code)
        XCTAssertEqual(output, "Hello, hs2", "Should support function definitions")
    }

    func testVariables() {
        let code = """
        var x = 10;
        var y = 20;
        print(x + y);
        """
        let output = evalCode(code)
        XCTAssertEqual(output, "30", "Should support variables")
    }

    // MARK: - Hammerspoon Module Access Tests

    func testAccessHSNamespace() {
        let output = evalCode("print(typeof hs)")
        XCTAssertEqual(output, "object", "Should have access to hs namespace")
    }

    func testAccessHSTimer() {
        let output = evalCode("print(typeof hs.timer)")
        XCTAssertEqual(output, "object", "Should have access to hs.timer")
    }

    func testUseHSTimerHelpers() {
        let output = evalCode("print(hs.timer.minutes(5))")
        XCTAssertEqual(output, "300", "Should use hs.timer helper functions")
    }

    func testAccessHSApplication() {
        let output = evalCode("print(typeof hs.application)")
        XCTAssertEqual(output, "object", "Should have access to hs.application")
    }

    // MARK: - Error Handling Tests

    func testSyntaxError() {
        let (_, stderr, exitCode) = runHS2Command(["-c", "this is invalid syntax;;"], quiet: true)
        XCTAssertEqual(exitCode, 0, "Should exit 0 - IPC succeeded even though JS errored")
        XCTAssertTrue(stderr.contains("Error") || stderr.contains("error"),
                     "Should output error message to stderr")
    }

    func testRuntimeError() {
        let code = "throw new Error('Test error');"
        let (_, stderr, exitCode) = runHS2Command(["-c", code], quiet: true)
        XCTAssertEqual(exitCode, 0, "Should exit 0 - IPC succeeded even though JS errored")
        XCTAssertTrue(stderr.contains("Error") || stderr.contains("Test error"),
                     "Should output error message to stderr")
    }

    func testUndefinedVariable() {
        let code = "print(undefinedVariable);"
        let (_, stderr, exitCode) = runHS2Command(["-c", code], quiet: true)
        XCTAssertEqual(exitCode, 0, "Should exit 0 - IPC succeeded even though JS errored")
        XCTAssertTrue(stderr.contains("ReferenceError") || stderr.contains("undefined"),
                     "Should output error about undefined variable")
    }

    // MARK: - Error Recovery Tests

    func testErrorRecovery_SingleError() {
        // Single error command should print error but exit 0
        let (_, stderr, exitCode) = runHS2Command(["-c", "throw new Error('test error')"], quiet: true)
        XCTAssertEqual(exitCode, 0, "Exit code should be 0 (IPC succeeded)")
        XCTAssertTrue(stderr.contains("Error"), "Error should be printed to stderr")
    }

    func testErrorRecovery_ErrorInFirstPosition() {
        // Error in first command should not prevent second command from executing
        let (stdout, stderr, exitCode) = runHS2Command([
            "-c", "throw new Error('first error')",
            "-c", "print('second command')"
        ], quiet: true)

        XCTAssertEqual(exitCode, 0, "Exit code should be 0 (all IPC succeeded)")
        XCTAssertTrue(stderr.contains("first error"), "First error should be in stderr")
        XCTAssertTrue(stdout.contains("second command"), "Second command should execute")
    }

    func testErrorRecovery_ErrorInMiddlePosition() {
        // Error in middle should not prevent other commands from executing
        let (stdout, stderr, exitCode) = runHS2Command([
            "-c", "print('first')",
            "-c", "undefinedVariable",
            "-c", "print('third')"
        ], quiet: true)

        XCTAssertEqual(exitCode, 0, "Exit code should be 0 (all IPC succeeded)")
        XCTAssertTrue(stdout.contains("first"), "First command should execute")
        XCTAssertTrue(stderr.contains("ReferenceError") || stderr.contains("undefined"),
                     "Error should be in stderr")
        XCTAssertTrue(stdout.contains("third"), "Third command should execute")
    }

    func testErrorRecovery_ErrorInLastPosition() {
        // All commands should execute even if last one errors
        let (stdout, stderr, exitCode) = runHS2Command([
            "-c", "print('first')",
            "-c", "print('second')",
            "-c", "throw new Error('last error')"
        ], quiet: true)

        XCTAssertEqual(exitCode, 0, "Exit code should be 0 (all IPC succeeded)")
        XCTAssertTrue(stdout.contains("first"), "First command should execute")
        XCTAssertTrue(stdout.contains("second"), "Second command should execute")
        XCTAssertTrue(stderr.contains("last error"), "Error should be in stderr")
    }

    func testErrorRecovery_SyntaxErrorRecovery() {
        // Syntax errors should also allow continued execution
        let (stdout, stderr, exitCode) = runHS2Command([
            "-c", "invalid syntax {{",
            "-c", "print('after syntax error')"
        ], quiet: true)

        XCTAssertEqual(exitCode, 0, "Exit code should be 0 (IPC succeeded)")
        XCTAssertTrue(stderr.contains("Error") || stderr.contains("Syntax"),
                     "Syntax error should be in stderr")
        XCTAssertTrue(stdout.contains("after syntax error"),
                     "Command after syntax error should execute")
    }

    func testErrorRecovery_MultipleErrors() {
        // Multiple errors should all be reported, all commands execute
        let (stdout, stderr, exitCode) = runHS2Command([
            "-c", "throw new Error('error 1')",
            "-c", "print('middle')",
            "-c", "throw new Error('error 2')"
        ], quiet: true)

        XCTAssertEqual(exitCode, 0, "Exit code should be 0 (all IPC succeeded)")
        XCTAssertTrue(stderr.contains("error 1"), "First error should be in stderr")
        XCTAssertTrue(stderr.contains("error 2"), "Second error should be in stderr")
        XCTAssertTrue(stdout.contains("middle"), "Middle command should execute")
    }

    func testErrorRecovery_SuccessfulCommandsStillWork() {
        // Verify successful commands work as expected
        let (stdout, _, exitCode) = runHS2Command([
            "-c", "print('hello')",
            "-c", "print(1 + 1)"
        ], quiet: true)

        XCTAssertEqual(exitCode, 0, "Exit code should be 0")
        XCTAssertTrue(stdout.contains("hello"), "First output should be present")
        XCTAssertTrue(stdout.contains("2"), "Second output should be present")
    }

    // MARK: - File Execution Tests

    func testExecuteJSFile() {
        // Create temporary JS file
        let tempFile = NSTemporaryDirectory() + "test_\(UUID().uuidString).js"
        let content = """
        print('Hello from file');
        print('Line 2');
        """

        do {
            try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

            let (stdout, _, exitCode) = runHS2Command([tempFile], quiet: true)
            XCTAssertEqual(exitCode, 0, "Should execute file successfully")
            XCTAssertTrue(stdout.contains("Hello from file"), "Should contain first line")
            XCTAssertTrue(stdout.contains("Line 2"), "Should contain second line")

            // Cleanup
            try? FileManager.default.removeItem(atPath: tempFile)
        } catch {
            XCTFail("Failed to create test file: \(error)")
        }
    }

    func testExecuteNonExistentFile() {
        let (_, stderr, exitCode) = runHS2Command(["/nonexistent/file.js"], quiet: true)
        XCTAssertNotEqual(exitCode, 0, "Should fail on nonexistent file")
        XCTAssertTrue(stderr.contains("Error") || stderr.contains("not found") || stderr.contains("No such"),
                     "Should output error about missing file")
    }

    // MARK: - Stdin Tests

    func testReadFromStdin() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hs2BinaryPath)
        process.arguments = ["-s", "-q"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe

        do {
            try process.run()

            // Write to stdin
            let code = "print('From stdin');\n"
            stdinPipe.fileHandleForWriting.write(code.data(using: .utf8)!)
            try? stdinPipe.fileHandleForWriting.close()

            process.waitUntilExit()

            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            XCTAssertEqual(process.terminationStatus, 0, "Should succeed reading from stdin")
            XCTAssertEqual(output, "From stdin", "Should execute code from stdin")
        } catch {
            XCTFail("Failed to test stdin: \(error)")
        }
    }

    // MARK: - Rapid Execution Stress Tests

    func testRapidCommands() {
        // Test that multiple rapid commands don't crash (regression test for memory fix)
        for i in 1...10 {
            let output = evalCode("print('Test \(i)')")
            XCTAssertEqual(output, "Test \(i)", "Command \(i) should succeed")
        }
    }

    func testConcurrentCommands() {
        // Test multiple commands in quick succession
        let expectation = XCTestExpectation(description: "All commands complete")
        expectation.expectedFulfillmentCount = 5

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 1...5 {
            queue.async {
                let output = self.evalCode("print('Concurrent \(i)')")
                XCTAssertTrue(output.contains("Concurrent \(i)"), "Concurrent command \(i) should succeed")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Exit Code Tests

    func testSuccessExitCode() {
        let (_, _, exitCode) = runHS2Command(["-c", "print('success')"], quiet: true)
        XCTAssertEqual(exitCode, 0, "Should exit with 0 on success")
    }

    func testErrorExitCode() {
        let (_, stderr, exitCode) = runHS2Command(["-c", "throw new Error('fail')"], quiet: true)
        XCTAssertEqual(exitCode, 0, "Should exit 0 - IPC succeeded even though JS errored")
        XCTAssertTrue(stderr.contains("Error") || stderr.contains("fail"),
                     "Error should be printed to stderr")
    }

    // MARK: - Command-line Flag Tests

    func testMultipleCommandFlags() {
        let (stdout, _, exitCode) = runHS2Command([
            "-c", "print('First')",
            "-c", "print('Second')",
            "-c", "print('Third')"
        ], quiet: true)

        XCTAssertEqual(exitCode, 0, "Should execute multiple -c commands")
        XCTAssertTrue(stdout.contains("First"), "Should contain first command output")
        XCTAssertTrue(stdout.contains("Second"), "Should contain second command output")
        XCTAssertTrue(stdout.contains("Third"), "Should contain third command output")
    }

    func testHelpFlag() {
        let (stdout, _, _) = runHS2Command(["-h"])
        XCTAssertTrue(stdout.contains("Usage") || stdout.contains("Options") || stdout.contains("help"),
                     "Should display help message")
    }

    // MARK: - Interactive Mode Tests (Limited)

    func testInteractiveModeDetection() {
        // Verify -i flag is accepted and the process starts (it will block on readline)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hs2BinaryPath)
        process.arguments = ["-i"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        try? process.run()
        // Give it a moment to start, then close stdin to make it exit
        Thread.sleep(forTimeInterval: 0.5)
        try? stdinPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        // The REPL banner should be printed
        XCTAssertTrue(output.contains("REPL"), "Interactive mode should print REPL banner")
    }

    // MARK: - Performance Tests

    func testCommandLatency() {
        let startTime = Date()
        _ = evalCode("print('latency test')")
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsed, 2.0, "Simple command should complete quickly")
    }
}
