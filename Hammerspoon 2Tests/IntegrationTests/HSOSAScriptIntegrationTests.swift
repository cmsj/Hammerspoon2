//
//  HSOSAScriptIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Integration tests for hs.osascript module
///
/// These tests verify AppleScript and OSA JavaScript execution via the XPC helper,
/// including result type mapping, error handling, and file-based script execution.
///
/// Tests that communicate with the XPC helper require the
/// HammerspoonOSAScriptHelper service to be available, which it is when running
/// tests inside Xcode with the built app bundle present.
@Suite(.serialized) struct HSOSAScriptIntegrationTests {

    // MARK: - Test Lifecycle

    init() async {
        await JSTestHarness.drainMainActorQueue()
    }

    // MARK: - Module API Tests

    @Test("hs.osascript is accessible as an object")
    func testModuleAccess() {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        harness.expectTrue("typeof hs.osascript === 'object'")
    }

    @Test("hs.osascript exposes all expected functions")
    func testModuleFunctions() {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        harness.expectTrue("typeof hs.osascript.applescript === 'function'")
        harness.expectTrue("typeof hs.osascript.javascript === 'function'")
        harness.expectTrue("typeof hs.osascript.applescriptFromFile === 'function'")
        harness.expectTrue("typeof hs.osascript.javascriptFromFile === 'function'")
        harness.expectTrue("typeof hs.osascript._execute === 'function'")
    }

    // MARK: - Promise Return Type Tests

    @Test("applescript() returns a Promise")
    func testAppleScriptReturnsPromise() {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        harness.expectTrue("hs.osascript.applescript('return 1') instanceof Promise")
    }

    @Test("javascript() returns a Promise")
    func testJavaScriptReturnsPromise() {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        harness.expectTrue("hs.osascript.javascript('1') instanceof Promise")
    }

    // MARK: - Result Structure Tests

    @Test("Result object always contains success, result, and raw fields")
    func testResultStructure() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") {
            resolved = true
        }

        harness.eval("""
        var r;
        hs.osascript.applescript('return "test"').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r !== undefined && r !== null")
        harness.expectTrue("'success' in r")
        harness.expectTrue("'result' in r")
        harness.expectTrue("'raw' in r")
        harness.expectTrue("typeof r.success === 'boolean'")
        harness.expectTrue("typeof r.raw === 'string'")
    }

    // MARK: - AppleScript Type Mapping Tests

    @Test("applescript() maps a string return value correctly")
    func testAppleScriptReturnsString() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('return "hello from applescript"').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", "hello from applescript")
        harness.expectEqual("r.raw", "hello from applescript")
    }

    @Test("applescript() maps an integer return value correctly")
    func testAppleScriptReturnsInteger() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('return 42').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", 42)
    }

    @Test("applescript() maps boolean true correctly")
    func testAppleScriptReturnsBooleanTrue() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('return true').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectTrue("r.result === true")
    }

    @Test("applescript() maps boolean false correctly")
    func testAppleScriptReturnsBooleanFalse() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('return false').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectTrue("r.result === false")
    }

    @Test("applescript() maps a list return value to a JS array")
    func testAppleScriptReturnsList() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('return {1, 2, 3}').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectTrue("Array.isArray(r.result)")
        harness.expectEqual("r.result.length", 3)
        harness.expectEqual("r.result[0]", 1)
        harness.expectEqual("r.result[1]", 2)
        harness.expectEqual("r.result[2]", 3)
    }

    @Test("applescript() maps a record return value to a JS object")
    func testAppleScriptReturnsRecord() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        // Use identifiers that are not recognized AE keywords so they are stored
        // in the 'usrf' field as unicode strings (which the parser can extract).
        // 'name' is the reserved AE property pnam and would be dropped by the parser.
        harness.eval("""
        var r;
        hs.osascript.applescript('return {firstName: "Alice", personAge: 30}').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectTrue("typeof r.result === 'object' && r.result !== null")
        harness.expectEqual("r.result.firstName", "Alice")
        harness.expectEqual("r.result.personAge", 30)
    }

    @Test("applescript() maps missing value to null")
    func testAppleScriptReturnsMissingValue() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('return missing value').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectTrue("r.result === null")
    }

    // MARK: - AppleScript Error Handling Tests

    @Test("applescript() resolves with success=false on syntax error")
    func testAppleScriptSyntaxError() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('this is not valid applescript @@@').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve even on error")
        harness.expectTrue("r.success === false")
        harness.expectTrue("r.result === null")
        harness.expectTrue("r.raw.length > 0")
    }

    @Test("applescript() resolves with success=false on runtime error")
    func testAppleScriptRuntimeError() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('error "intentional test error"').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve even on runtime error")
        harness.expectTrue("r.success === false")
        harness.expectTrue("r.result === null")
        harness.expectTrue("r.raw.length > 0")
    }

    @Test("Promise never rejects — even for script errors")
    func testPromiseNeverRejects() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        var rejected = false
        harness.registerCallback("onResolve") { resolved = true }
        harness.registerCallback("onReject") { rejected = true }

        harness.eval("""
        hs.osascript.applescript('this is not valid @@@')
            .then(function() { __test_callback('onResolve'); })
            .catch(function() { __test_callback('onReject'); });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved || rejected }
        #expect(completed, "Promise should settle")
        #expect(resolved, "Promise should resolve, not reject")
        #expect(!rejected, "Promise must NOT reject")
    }

    // MARK: - OSA JavaScript Tests

    @Test("javascript() evaluates arithmetic and returns the result")
    func testJavaScriptArithmetic() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.javascript('1 + 1').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", 2)
    }

    @Test("javascript() returns a string result")
    func testJavaScriptString() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.javascript('"hello from osa js"').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", "hello from osa js")
    }

    @Test("javascript() resolves with success=false on error")
    func testJavaScriptError() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.javascript('throw new Error("intentional error")').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve even on JS error")
        harness.expectTrue("r.success === false")
        harness.expectTrue("r.result === null")
        harness.expectTrue("r.raw.length > 0")
    }

    @Test("javascript() can query Finder's name via OSA JXA")
    func testJavaScriptFinderName() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.javascript('Application("Finder").name()').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", "Finder")
    }

    // MARK: - File-Based Tests

    @Test("applescriptFromFile() resolves with success=false for non-existent file")
    func testAppleScriptFromFileMissing() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescriptFromFile('/nonexistent/path/script.applescript').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 2.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === false")
        harness.expectTrue("r.result === null")
        harness.expectTrue("r.raw.indexOf('Failed to read file:') !== -1")
    }

    @Test("javascriptFromFile() resolves with success=false for non-existent file")
    func testJavaScriptFromFileMissing() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.javascriptFromFile('/nonexistent/path/script.js').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 2.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === false")
        harness.expectTrue("r.result === null")
        harness.expectTrue("r.raw.indexOf('Failed to read file:') !== -1")
    }

    @Test("applescriptFromFile() executes a valid script file")
    func testAppleScriptFromFile() async {
        let tmpPath = NSTemporaryDirectory() + "hs_osa_test_\(UUID().uuidString).applescript"
        try? "return \"from file\"".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescriptFromFile('\(tmpPath)').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", "from file")
    }

    @Test("javascriptFromFile() executes a valid script file")
    func testJavaScriptFromFile() async {
        let tmpPath = NSTemporaryDirectory() + "hs_osa_test_\(UUID().uuidString).js"
        try? "2 + 2".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.javascriptFromFile('\(tmpPath)').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", 4)
    }

    // MARK: - Low-level _execute Tests

    @Test("_execute() with 'AppleScript' language behaves like applescript()")
    func testExecuteAppleScript() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript._execute('return "via execute"', 'AppleScript').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", "via execute")
    }

    @Test("_execute() with 'JavaScript' language behaves like javascript()")
    func testExecuteJavaScript() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript._execute('3 * 3', 'JavaScript').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectEqual("r.result", 9)
    }

    // MARK: - Real-World Use Case Tests

    @Test("Get macOS system version via AppleScript")
    func testGetSystemVersion() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var r;
        hs.osascript.applescript('return system version of (system info)').then(function(result) {
            r = result;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 5.0) { resolved }
        #expect(completed, "Promise should resolve")
        harness.expectTrue("r.success === true")
        harness.expectTrue("typeof r.result === 'string' && r.result.length > 0")
    }

    @Test("Sequential script execution completes in order")
    func testSequentialExecution() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var results = [];
        hs.osascript.applescript('return 1')
            .then(function(r1) {
                results.push(r1.result);
                return hs.osascript.applescript('return 2');
            })
            .then(function(r2) {
                results.push(r2.result);
                return hs.osascript.applescript('return 3');
            })
            .then(function(r3) {
                results.push(r3.result);
                __test_callback('onResolve');
            });
        """)

        let completed = await harness.waitForAsync(timeout: 15.0) { resolved }
        #expect(completed, "All chained scripts should complete")
        harness.expectEqual("results.length", 3)
        harness.expectEqual("results[0]", 1)
        harness.expectEqual("results[1]", 2)
        harness.expectEqual("results[2]", 3)
    }

    @Test("A failed call does not prevent subsequent calls from succeeding")
    func testErrorDoesNotPoisonSubsequentCalls() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var secondResult;
        hs.osascript.applescript('invalid @@@').then(function(r1) {
            // r1.success === false; now run a valid script
            return hs.osascript.applescript('return 99');
        }).then(function(r2) {
            secondResult = r2;
            __test_callback('onResolve');
        });
        """)

        let completed = await harness.waitForAsync(timeout: 10.0) { resolved }
        #expect(completed, "Second call should complete")
        harness.expectTrue("secondResult.success === true")
        harness.expectEqual("secondResult.result", 99)
    }

    @Test("Multiple concurrent calls all resolve")
    func testConcurrentCalls() async {
        let harness = JSTestHarness()
        harness.loadModule(HSOSAScriptModule.self, as: "osascript")

        var resolved = false
        harness.registerCallback("onResolve") { resolved = true }

        harness.eval("""
        var results = [];
        function onResult(r) {
            results.push(r.result);
            if (results.length === 3) {
                __test_callback('onResolve');
            }
        }
        hs.osascript.applescript('return 10').then(onResult);
        hs.osascript.applescript('return 20').then(onResult);
        hs.osascript.applescript('return 30').then(onResult);
        """)

        let completed = await harness.waitForAsync(timeout: 15.0) { resolved }
        #expect(completed, "All three concurrent calls should complete")
        harness.expectEqual("results.length", 3)
        // Results can arrive in any order, but all three values must be present
        harness.expectTrue("results.indexOf(10) !== -1")
        harness.expectTrue("results.indexOf(20) !== -1")
        harness.expectTrue("results.indexOf(30) !== -1")
    }
}
