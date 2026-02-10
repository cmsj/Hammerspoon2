//
//  HSTaskIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 10/02/2026.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Integration tests for hs.task module
///
/// These tests verify task creation, process execution, callbacks, and JavaScript enhancements.
/// Tests use real system commands (/bin/echo, /bin/sh, etc.) to verify actual process behavior.
struct HSTaskIntegrationTests {

    // MARK: - Basic Task Creation Tests

    @Test("hs.task.new() creates a task object")
    func testNewTask() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.eval("""
        var task = hs.task.new('/bin/echo', ['hello']);
        """)

        harness.expectTrue("typeof task === 'object'")
        harness.expectTrue("typeof task.start === 'function'")
        harness.expectTrue("typeof task.terminate === 'function'")
    }

    @Test("hs.task object has all expected methods")
    func testTaskObjectAPI() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.eval("var t = hs.task.new('/bin/echo', ['test'])")

        // Lifecycle methods
        harness.expectTrue("typeof t.start === 'function'")
        harness.expectTrue("typeof t.terminate === 'function'")
        harness.expectTrue("typeof t.kill9 === 'function'")
        harness.expectTrue("typeof t.interrupt === 'function'")
        harness.expectTrue("typeof t.pause === 'function'")
        harness.expectTrue("typeof t.resume === 'function'")
        harness.expectTrue("typeof t.waitUntilExit === 'function'")

        // stdin/stdout methods
        harness.expectTrue("typeof t.sendInput === 'function'")
        harness.expectTrue("typeof t.closeInput === 'function'")

        // State query methods
        harness.expectTrue("typeof t.terminationStatus === 'function'")
        harness.expectTrue("typeof t.terminationReason === 'function'")

        // Properties
        harness.expectTrue("typeof t.isRunning === 'boolean'")
        harness.expectTrue("typeof t.pid === 'number'")
    }

    // MARK: - Task Execution Tests

    @Test("Task executes and fires termination callback")
    func testTaskExecution() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var callbackFired = false
        var receivedExitCode: Int = -999
        harness.registerCallback("taskComplete") { (exitCode: Int) in
            callbackFired = true
            receivedExitCode = exitCode
        }

        harness.eval("""
        var task = hs.task.new('/bin/echo', ['hello'], function(exitCode, reason) {
            taskComplete(exitCode);
        });
        task.start();
        """)

        let success = harness.waitFor(timeout: 2.0) { callbackFired }
        #expect(success, "Task termination callback should fire")
        #expect(receivedExitCode == 0, "Exit code should be 0 for successful task")
    }

    @Test("Task captures stdout via streaming callback")
    func testStdoutStreaming() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var stdoutReceived = false
        var capturedOutput = ""
        harness.registerCallback("onOutput") { (output: String) in
            stdoutReceived = true
            capturedOutput = output
        }

        harness.eval("""
        var task = hs.task.new(
            '/bin/echo',
            ['Hello from stdout'],
            null,
            null,
            function(stream, data) {
                if (stream === 'stdout') {
                    onOutput(data);
                }
            }
        );
        task.start();
        """)

        let success = harness.waitFor(timeout: 2.0) { stdoutReceived }
        #expect(success, "Should receive stdout output")
        #expect(capturedOutput.contains("Hello from stdout"), "Output should contain expected text")
    }

    @Test("Task captures stderr via streaming callback")
    func testStderrStreaming() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var stderrReceived = false
        var capturedError = ""
        harness.registerCallback("onError") { (output: String) in
            stderrReceived = true
            capturedError = output
        }

        harness.eval("""
        var task = hs.task.new(
            '/bin/sh',
            ['-c', 'echo "Error message" >&2'],
            null,
            null,
            function(stream, data) {
                if (stream === 'stderr') {
                    onError(data);
                }
            }
        );
        task.start();
        """)

        let success = harness.waitFor(timeout: 2.0) { stderrReceived }
        #expect(success, "Should receive stderr output")
        #expect(capturedError.contains("Error message"), "Error output should contain expected text")
    }

    // MARK: - Task State Tests

    @Test("isRunning reflects task state correctly")
    func testIsRunning() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var taskCompleted = false
        harness.registerCallback("onComplete") {
            taskCompleted = true
        }

        harness.eval("""
        var task = hs.task.new('/bin/sleep', ['0.2'], function() {
            __test_callback('onComplete');
        });
        """)

        // Before starting
        harness.expectTrue("task.isRunning === false")

        // Start the task
        harness.eval("task.start()")

        // Should be running now
        Thread.sleep(forTimeInterval: 0.05)
        harness.expectTrue("task.isRunning === true")

        // Wait for completion
        let success = harness.waitFor(timeout: 2.0) { taskCompleted }
        #expect(success, "Task should complete")

        // Should not be running anymore
        Thread.sleep(forTimeInterval: 0.1)
        harness.expectTrue("task.isRunning === false")
    }

    @Test("pid returns valid process ID")
    func testPid() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var taskStarted = false
        harness.registerCallback("onStart") {
            taskStarted = true
        }

        harness.eval("""
        var task = hs.task.new('/bin/sleep', ['0.1']);
        """)

        // Before starting, pid should be -1
        harness.expectEqual("task.pid", Int32(-1))

        // Start and capture pid
        harness.eval("""
        task.start();
        var capturedPid = task.pid;
        """)

        // After starting, should have valid pid
        harness.expectTrue("capturedPid > 0")

        // Wait for task to complete
        Thread.sleep(forTimeInterval: 0.3)
    }

    @Test("terminationStatus returns exit code")
    func testTerminationStatus() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var taskCompleted = false
        harness.registerCallback("onComplete") {
            taskCompleted = true
        }

        harness.eval("""
        var task = hs.task.new('/bin/sh', ['-c', 'exit 42'], function() {
            __test_callback('onComplete');
        });
        """)

        // Before termination
        harness.expectTrue("task.terminationStatus() === null")

        // Start and wait
        harness.eval("task.start()")
        let success = harness.waitFor(timeout: 2.0) { taskCompleted }
        #expect(success, "Task should complete")

        // After termination
        Thread.sleep(forTimeInterval: 0.1)
        harness.expectEqual("task.terminationStatus()", 42)
    }

    @Test("terminationReason returns exit for normal termination")
    func testTerminationReason() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var taskCompleted = false
        harness.registerCallback("onComplete") {
            taskCompleted = true
        }

        harness.eval("""
        var task = hs.task.new('/bin/echo', ['test'], function() {
            __test_callback('onComplete');
        });
        task.start();
        """)

        let success = harness.waitFor(timeout: 2.0) { taskCompleted }
        #expect(success, "Task should complete")

        Thread.sleep(forTimeInterval: 0.1)
        harness.expectEqual("task.terminationReason()", "exit")
    }

    // MARK: - Signal Control Tests

    @Test("terminate stops a running task")
    func testTerminate() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var taskTerminated = false
        harness.registerCallback("onTerminate") {
            taskTerminated = true
        }

        harness.eval("""
        var task = hs.task.new('/bin/sleep', ['10'], function() {
            __test_callback('onTerminate');
        });
        task.start();
        """)

        Thread.sleep(forTimeInterval: 0.1)
        harness.expectTrue("task.isRunning === true")

        // Terminate the task
        harness.eval("task.terminate()")

        let success = harness.waitFor(timeout: 2.0) { taskTerminated }
        #expect(success, "Task should terminate")
    }

    @Test("pause and resume control task execution")
    func testPauseResume() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.eval("""
        var outputCount = 0;
        var task = hs.task.new(
            '/bin/sh',
            ['-c', 'for i in 1 2 3 4 5; do echo $i; sleep 0.1; done'],
            null,
            null,
            function(stream, data) {
                outputCount++;
            }
        );
        task.start();
        """)

        Thread.sleep(forTimeInterval: 0.15)

        // Pause the task
        harness.eval("task.pause()")
        let countWhilePaused = harness.eval("outputCount") as? Int ?? -1

        Thread.sleep(forTimeInterval: 0.25)

        // Count should not increase much while paused
        let countAfterPause = harness.eval("outputCount") as? Int ?? -1
        #expect(countAfterPause <= countWhilePaused + 1, "Output should not increase while paused")

        // Resume the task
        harness.eval("task.resume()")
        Thread.sleep(forTimeInterval: 0.3)

        // Count should increase after resume
        let countAfterResume = harness.eval("outputCount") as? Int ?? -1
        #expect(countAfterResume > countAfterPause, "Output should increase after resume")

        // Cleanup
        harness.eval("if (task.isRunning) task.terminate()")
        Thread.sleep(forTimeInterval: 0.1)
    }

    // MARK: - stdin Tests

    @Test("sendInput writes to task stdin")
    func testSendInput() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var echoReceived = false
        var echoedText = ""
        harness.registerCallback("onEcho") { (output: String) in
            echoReceived = true
            echoedText = output
        }

        harness.eval("""
        var task = hs.task.new(
            '/bin/cat',
            [],
            null,
            null,
            function(stream, data) {
                onEcho(data);
            }
        );
        task.start();
        task.sendInput('Hello stdin\\n');
        """)

        let success = harness.waitFor(timeout: 2.0) { echoReceived }
        #expect(success, "Should receive echoed input")
        #expect(echoedText.contains("Hello stdin"), "Echoed text should match input")

        // Cleanup
        harness.eval("task.closeInput()")
        Thread.sleep(forTimeInterval: 0.2)
    }

    @Test("closeInput closes stdin and signals EOF")
    func testCloseInput() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var taskExited = false
        harness.registerCallback("onExit") {
            taskExited = true
        }

        harness.eval("""
        var task = hs.task.new('/bin/cat', [], function() {
            __test_callback('onExit');
        });
        task.start();
        task.sendInput('test\\n');
        """)

        Thread.sleep(forTimeInterval: 0.1)
        harness.expectTrue("task.isRunning === true")

        // Close stdin - cat should exit
        harness.eval("task.closeInput()")

        let success = harness.waitFor(timeout: 2.0) { taskExited }
        #expect(success, "Task should exit after stdin closes")
    }

    // MARK: - Environment and Working Directory Tests

    @Test("Task respects custom environment variables")
    func testEnvironmentVariables() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var outputReceived = false
        var capturedOutput = ""
        harness.registerCallback("onOutput") { (output: String) in
            outputReceived = true
            capturedOutput = output
        }

        harness.eval("""
        var task = hs.task.new(
            '/usr/bin/env',
            ['bash', '-c', 'echo $MY_TEST_VAR'],
            null,
            { MY_TEST_VAR: 'CustomValue123' },
            function(stream, data) {
                onOutput(data);
            }
        );
        task.start();
        """)

        let success = harness.waitFor(timeout: 2.0) { outputReceived }
        #expect(success, "Should receive output")
        #expect(capturedOutput.contains("CustomValue123"), "Should see custom environment variable value")
    }

    @Test("Task respects custom working directory")
    func testWorkingDirectory() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var outputReceived = false
        var capturedPath = ""
        harness.registerCallback("onOutput") { (output: String) in
            outputReceived = true
            capturedPath = output
        }

        harness.eval("""
        var task = hs.task.new(
            '/bin/pwd',
            [],
            null,
            null,
            function(stream, data) {
                onOutput(data);
            }
        );
        task.workingDirectory = '/tmp';
        task.start();
        """)

        let success = harness.waitFor(timeout: 2.0) { outputReceived }
        #expect(success, "Should receive output")
        #expect(capturedPath.trimmingCharacters(in: .whitespacesAndNewlines) == "/tmp", "Working directory should be /tmp")
    }

    @Test("Cannot modify environment after task starts")
    func testEnvironmentImmutableAfterStart() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.eval("""
        var task = hs.task.new('/bin/echo', ['test']);
        task.environment = { TEST: 'before' };
        task.start();
        task.environment = { TEST: 'after' };
        """)

        // Should see a warning but not crash
        // The test just verifies it doesn't crash
        Thread.sleep(forTimeInterval: 0.2)
    }

    @Test("Cannot modify working directory after task starts")
    func testWorkingDirectoryImmutableAfterStart() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.eval("""
        var task = hs.task.new('/bin/echo', ['test']);
        task.workingDirectory = '/tmp';
        task.start();
        task.workingDirectory = '/var';
        """)

        // Should see a warning but not crash
        Thread.sleep(forTimeInterval: 0.2)
    }

    // MARK: - JavaScript Enhancement Tests - async/await API

    @Test("hs.task.run() exists as async function")
    func testRunExists() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.expectTrue("typeof hs.task.run === 'function'")
    }

    @Test("hs.task.run() returns Promise with stdout/stderr/exitCode")
    func testRunReturnsPromise() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var capturedStdout = ""
        var capturedExitCode: Int = -1
        harness.registerCallback("onResolve") { (stdout: String) in
            promiseResolved = true
            capturedStdout = stdout
        }
        harness.registerCallback("onExitCode") { (exitCode: Int) in
            capturedExitCode = exitCode
        }

        harness.eval("""
        hs.task.run('/bin/echo', ['Hello async']).then(function(result) {
            onResolve(result.stdout);
            onExitCode(result.exitCode);
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Promise should resolve")
        #expect(capturedStdout.contains("Hello async"), "Should capture stdout")
        #expect(capturedExitCode == 0, "Exit code should be 0")
    }

    @Test("hs.task.run() rejects on non-zero exit code")
    func testRunRejectsOnFailure() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseRejected = false
        var capturedExitCode: Int = -1
        harness.registerCallback("onReject") { (exitCode: Int) in
            promiseRejected = true
            capturedExitCode = exitCode
        }

        harness.eval("""
        hs.task.run('/bin/sh', ['-c', 'exit 5']).catch(function(error) {
            onReject(error.exitCode);
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseRejected }
        #expect(success, "Promise should reject on failure")
        #expect(capturedExitCode == 5, "Should capture non-zero exit code")
    }

    @Test("hs.task.run() supports onOutput streaming callback")
    func testRunOnOutput() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var streamingFired = false
        var streamedData = ""
        harness.registerCallback("onStream") { (data: String) in
            streamingFired = true
            streamedData = data
        }

        harness.eval("""
        hs.task.run('/bin/echo', ['Streaming test'], {
            onOutput: function(stream, data) {
                onStream(data);
            }
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { streamingFired }
        #expect(success, "Streaming callback should fire")
        #expect(streamedData.contains("Streaming test"), "Should stream output")
    }

    @Test("hs.task.run() supports workingDirectory option")
    func testRunWorkingDirectory() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var capturedPath = ""
        harness.registerCallback("onResolve") { (stdout: String) in
            promiseResolved = true
            capturedPath = stdout
        }

        harness.eval("""
        hs.task.run('/bin/pwd', [], {
            workingDirectory: '/tmp'
        }).then(function(result) {
            onResolve(result.stdout);
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Promise should resolve")
        #expect(capturedPath.trimmingCharacters(in: .whitespacesAndNewlines) == "/tmp", "Should use custom working directory")
    }

    @Test("hs.task.run() supports environment option")
    func testRunEnvironment() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var capturedEnv = ""
        harness.registerCallback("onResolve") { (stdout: String) in
            promiseResolved = true
            capturedEnv = stdout
        }

        harness.eval("""
        hs.task.run('/usr/bin/env', ['bash', '-c', 'echo $CUSTOM_VAR'], {
            environment: { CUSTOM_VAR: 'test123' }
        }).then(function(result) {
            onResolve(result.stdout);
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Promise should resolve")
        #expect(capturedEnv.contains("test123"), "Should use custom environment")
    }

    // MARK: - JavaScript Enhancement Tests - Helper Functions

    @Test("hs.task.async() is alias for run()")
    func testAsyncAlias() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.expectTrue("hs.task.async === hs.task.run")
    }

    @Test("hs.task.shell() executes shell commands")
    func testShell() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var capturedOutput = ""
        harness.registerCallback("onResolve") { (stdout: String) in
            promiseResolved = true
            capturedOutput = stdout
        }

        harness.eval("""
        hs.task.shell('echo "Shell command test" && pwd').then(function(result) {
            onResolve(result.stdout);
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Shell command should complete")
        #expect(capturedOutput.contains("Shell command test"), "Should execute shell command")
    }

    @Test("hs.task.parallel() runs tasks concurrently")
    func testParallel() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var resultsCount: Int = 0
        harness.registerCallback("onResolve") { (count: Int) in
            promiseResolved = true
            resultsCount = count
        }

        harness.eval("""
        hs.task.parallel([
            { path: '/bin/echo', args: ['task1'] },
            { path: '/bin/echo', args: ['task2'] },
            { path: '/bin/echo', args: ['task3'] }
        ]).then(function(results) {
            onResolve(results.length);
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Parallel tasks should complete")
        #expect(resultsCount == 3, "Should return 3 results")
    }

    @Test("hs.task.sequence() runs tasks sequentially")
    func testSequence() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var resultsCount: Int = 0
        harness.registerCallback("onResolve") { (count: Int) in
            promiseResolved = true
            resultsCount = count
        }

        harness.eval("""
        hs.task.sequence([
            { path: '/bin/echo', args: ['seq1'] },
            { path: '/bin/echo', args: ['seq2'] },
            { path: '/bin/echo', args: ['seq3'] }
        ]).then(function(results) {
            onResolve(results.length);
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Sequential tasks should complete")
        #expect(resultsCount == 3, "Should return 3 results")
    }

    // MARK: - JavaScript Enhancement Tests - Builder API

    @Test("hs.task.builder() creates TaskBuilder")
    func testBuilderCreation() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.eval("var builder = hs.task.builder('/bin/echo')")

        harness.expectTrue("typeof builder === 'object'")
        harness.expectTrue("typeof builder.withArgs === 'function'")
        harness.expectTrue("typeof builder.withEnvironment === 'function'")
        harness.expectTrue("typeof builder.inDirectory === 'function'")
        harness.expectTrue("typeof builder.onOutput === 'function'")
        harness.expectTrue("typeof builder.run === 'function'")
        harness.expectTrue("typeof builder.build === 'function'")
    }

    @Test("TaskBuilder.withArgs() adds arguments")
    func testBuilderWithArgs() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var capturedOutput = ""
        harness.registerCallback("onResolve") { (stdout: String) in
            promiseResolved = true
            capturedOutput = stdout
        }

        harness.eval("""
        hs.task.builder('/bin/echo')
            .withArgs('arg1', 'arg2', 'arg3')
            .run()
            .then(function(result) {
                onResolve(result.stdout);
            });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Builder task should complete")
        #expect(capturedOutput.contains("arg1 arg2 arg3"), "Should pass all arguments")
    }

    @Test("TaskBuilder.withEnvironment() sets environment")
    func testBuilderWithEnvironment() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var capturedEnv = ""
        harness.registerCallback("onResolve") { (stdout: String) in
            promiseResolved = true
            capturedEnv = stdout
        }

        harness.eval("""
        hs.task.builder('/usr/bin/env')
            .withArgs('bash', '-c', 'echo $BUILDER_VAR')
            .withEnvironment({ BUILDER_VAR: 'builder_test' })
            .run()
            .then(function(result) {
                onResolve(result.stdout);
            });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Builder task should complete")
        #expect(capturedEnv.contains("builder_test"), "Should use builder environment")
    }

    @Test("TaskBuilder.inDirectory() sets working directory")
    func testBuilderInDirectory() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        var capturedPath = ""
        harness.registerCallback("onResolve") { (stdout: String) in
            promiseResolved = true
            capturedPath = stdout
        }

        harness.eval("""
        hs.task.builder('/bin/pwd')
            .inDirectory('/tmp')
            .run()
            .then(function(result) {
                onResolve(result.stdout);
            });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Builder task should complete")
        #expect(capturedPath.trimmingCharacters(in: .whitespacesAndNewlines) == "/tmp", "Should use builder working directory")
    }

    @Test("TaskBuilder.onOutput() sets streaming callback")
    func testBuilderOnOutput() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var streamingFired = false
        var streamedData = ""
        harness.registerCallback("onStream") { (data: String) in
            streamingFired = true
            streamedData = data
        }

        harness.eval("""
        hs.task.builder('/bin/echo')
            .withArgs('builder output test')
            .onOutput(function(stream, data) {
                onStream(data);
            })
            .run();
        """)

        let success = harness.waitFor(timeout: 2.0) { streamingFired }
        #expect(success, "Builder streaming should fire")
        #expect(streamedData.contains("builder output test"), "Should stream builder output")
    }

    @Test("TaskBuilder.build() creates task without running")
    func testBuilderBuild() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        harness.eval("""
        var task = hs.task.builder('/bin/echo')
            .withArgs('not started yet')
            .build();
        """)

        // Task should exist but not be running
        harness.expectTrue("typeof task === 'object'")
        harness.expectTrue("task.isRunning === false")

        // Should be able to start it
        harness.eval("task.start()")
        Thread.sleep(forTimeInterval: 0.2)
    }

    @Test("TaskBuilder supports method chaining")
    func testBuilderChaining() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var promiseResolved = false
        harness.registerCallback("onResolve") {
            promiseResolved = true
        }

        harness.eval("""
        hs.task.builder('/bin/echo')
            .withArgs('chaining')
            .withEnvironment({ TEST: 'chain' })
            .inDirectory('/tmp')
            .onOutput(function() {})
            .run()
            .then(function() {
                __test_callback('onResolve');
            });
        """)

        let success = harness.waitFor(timeout: 2.0) { promiseResolved }
        #expect(success, "Chained builder should complete")
    }

    // MARK: - Real-World Use Case Tests

    @Test("Command pipeline pattern works")
    func testCommandPipeline() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var pipelineComplete = false
        var resultCount: Int = 0
        harness.registerCallback("onComplete") { (count: Int) in
            pipelineComplete = true
            resultCount = count
        }

        harness.eval("""
        hs.task.sequence([
            { path: '/bin/echo', args: ['step 1'] },
            { path: '/bin/echo', args: ['step 2'] },
            { path: '/bin/echo', args: ['step 3'] }
        ])
        .then(function(results) {
            onComplete(results.length);
        })
        .catch(function(error) {
            console.error('Pipeline failed:', error);
        });
        """)

        let success = harness.waitFor(timeout: 2.0) { pipelineComplete }
        #expect(success, "Pipeline should complete")
        #expect(resultCount == 3, "All pipeline steps should execute")
    }

    @Test("Background task monitoring pattern works")
    func testBackgroundMonitoring() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var outputLines = 0
        harness.registerCallback("onLine") {
            outputLines += 1
        }

        harness.eval("""
        var monitoredTask = hs.task.new(
            '/bin/sh',
            ['-c', 'for i in 1 2 3; do echo "line $i"; sleep 0.05; done'],
            null,
            null,
            function(stream, data) {
                if (stream === 'stdout') {
                    __test_callback('onLine');
                }
            }
        );
        monitoredTask.start();
        """)

        let success = harness.waitFor(timeout: 2.0) { outputLines >= 3 }
        #expect(success, "Should monitor background task output")
        #expect(outputLines >= 3, "Should capture all output lines")
    }

    @Test("Error handling pattern with retries works")
    func testErrorHandlingWithRetries() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var finalResult = false
        var attemptCount: Int = 0
        harness.registerCallback("onFinal") { (attempts: Int) in
            finalResult = true
            attemptCount = attempts
        }

        harness.eval("""
        var attempts = 0;
        var maxRetries = 3;

        function runWithRetry() {
            attempts++;
            return hs.task.run('/bin/sh', ['-c', 'exit 1'])
                .catch(function(error) {
                    if (attempts < maxRetries) {
                        return runWithRetry();
                    } else {
                        onFinal(attempts);
                        throw error;
                    }
                });
        }

        runWithRetry();
        """)

        let success = harness.waitFor(timeout: 3.0) { finalResult }
        #expect(success, "Retry pattern should complete")
        #expect(attemptCount == 3, "Should retry specified number of times")
    }

    @Test("Interactive input pattern works")
    func testInteractiveInput() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")

        var linesReceived = 0
        harness.registerCallback("onLine") {
            linesReceived += 1
        }

        harness.eval("""
        var interactiveTask = hs.task.new(
            '/bin/cat',
            [],
            null,
            null,
            function(stream, data) {
                __test_callback('onLine');
            }
        );
        interactiveTask.start();
        interactiveTask.sendInput('First line\\n');
        interactiveTask.sendInput('Second line\\n');
        interactiveTask.sendInput('Third line\\n');
        """)

        let success = harness.waitFor(timeout: 2.0) { linesReceived >= 3 }
        #expect(success, "Should receive all sent lines")

        harness.eval("interactiveTask.closeInput()")
        Thread.sleep(forTimeInterval: 0.2)
    }

    @Test("Timeout pattern with task termination works")
    func testTimeoutPattern() {
        let harness = JSTestHarness()
        harness.loadModule(HSTaskModule.self, as: "task")
        harness.loadModule(HSTimerModule.self, as: "timer")

        var timeoutFired = false
        harness.registerCallback("onTimeout") {
            timeoutFired = true
        }

        harness.eval("""
        var longTask = hs.task.new('/bin/sleep', ['10']);
        longTask.start();

        var timeout = hs.timer.doAfter(0.2, function() {
            if (longTask.isRunning) {
                longTask.terminate();
                __test_callback('onTimeout');
            }
        });
        """)

        let success = harness.waitFor(timeout: 1.0) { timeoutFired }
        #expect(success, "Timeout should fire and terminate task")
    }
}
