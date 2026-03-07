//
//  HSIPCHandlerTests.swift
//  Hammerspoon 2Tests
//
//  Tests for the IPC protocol handler (__ipcDefaultHandler) in hs.ipc.js.
//  These validate the closure-scoped state pattern that survives JSExport GC.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Tests for the IPC JavaScript protocol handler.
///
/// The handler (__ipcDefaultHandler) uses closure-scoped variables instead of
/// properties on the JSExport proxy to survive garbage collection. These tests
/// verify the protocol logic and state persistence.
@Suite(.serialized)
struct HSIPCHandlerTests {

    // MARK: - Helper

    /// Create a harness with hs.ipc module loaded (including companion JS)
    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSIPCModule.self, as: "ipc")
        return harness
    }

    /// Create a harness and a local port for registration tests.
    /// Returns (harness, portName) where portName can be used as instanceID.
    private func makeHarnessWithPort() -> (JSTestHarness, String) {
        let harness = makeHarness()
        let portName = "TestClient_\(UUID().uuidString)"

        // Create a local port that remotePort() can connect to
        harness.eval("""
            var __testPort = hs.ipc.localPort("\(portName)", function(port, msgID, data) {
                return "ack";
            });
        """)

        return (harness, portName)
    }

    // MARK: - Handler Availability

    @Test("__ipcDefaultHandler is a function")
    func testHandlerExists() {
        let harness = makeHarness()
        harness.expectTrue("typeof __ipcDefaultHandler === 'function'")
    }

    @Test("__ipcPrint is a function")
    func testPrintExists() {
        let harness = makeHarness()
        harness.expectTrue("typeof __ipcPrint === 'function'")
    }

    @Test("Default IPC port creation is attempted")
    func testDefaultPortCreated() {
        let harness = makeHarness()
        // The default port may or may not exist (conflicts if app is running),
        // but the variable should be defined
        harness.expectTrue("typeof hs.ipc.__default !== 'undefined'")
    }

    // MARK: - Registration Error Cases

    @Test("Register with invalid format (no null separator) returns error")
    func testRegisterInvalidFormat() {
        let harness = makeHarness()
        let result = harness.eval("__ipcDefaultHandler(null, 100, 'no-null-separator')")
        #expect((result as? String)?.contains("error") == true)
    }

    @Test("Register with invalid JSON returns error")
    func testRegisterInvalidJSON() {
        let harness = makeHarness()
        let result = harness.eval("__ipcDefaultHandler(null, 100, 'instanceID\\0{invalid json}')")
        #expect((result as? String)?.contains("error") == true)
    }

    // MARK: - Command/Query Error Cases

    @Test("Command with no null separator returns error")
    func testCommandInvalidFormat() {
        let harness = makeHarness()
        let result = harness.eval("__ipcDefaultHandler(null, 500, 'no-null-separator')")
        #expect((result as? String)?.contains("error") == true)
    }

    @Test("Command with unregistered instance returns error")
    func testCommandUnregisteredInstance() {
        let harness = makeHarness()
        let result = harness.eval("__ipcDefaultHandler(null, 500, 'nonexistent\\x001+1')")
        #expect((result as? String)?.contains("error") == true)
        #expect((result as? String)?.contains("not registered") == true)
    }

    @Test("Query with unregistered instance returns error")
    func testQueryUnregisteredInstance() {
        let harness = makeHarness()
        let result = harness.eval("__ipcDefaultHandler(null, 501, 'nonexistent\\x001+1')")
        #expect((result as? String)?.contains("error") == true)
        #expect((result as? String)?.contains("not registered") == true)
    }

    @Test("Unknown message ID returns error")
    func testUnknownMessageID() {
        let harness = makeHarness()
        let result = harness.eval("__ipcDefaultHandler(null, 999, 'anything')")
        #expect((result as? String)?.contains("error") == true)
    }

    // MARK: - Registration Success

    @Test("Register with valid port returns ok")
    func testRegisterSuccess() {
        let (harness, portName) = makeHarnessWithPort()
        let result = harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")
        #expect(result as? String == "ok")

        // Cleanup
        harness.eval("__testPort.delete()")
    }

    @Test("Register stores instance in closure-scoped variable")
    func testRegisterStoresInstance() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        // Verify instance exists in closure-scoped variable
        let exists = harness.eval("__ipcRegisteredInstances['\(portName)'] !== undefined")
        #expect(exists as? Bool == true)

        // Verify remote port is stored separately (prevents GC)
        let portStored = harness.eval("__ipcRemotePorts['\(portName)'] !== undefined")
        #expect(portStored as? Bool == true)

        harness.eval("__testPort.delete()")
    }

    @Test("Register with quiet mode stores setting")
    func testRegisterQuietMode() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{\"quiet\":true}')")

        let quiet = harness.eval("__ipcRegisteredInstances['\(portName)']._cli.quietMode")
        #expect(quiet as? Bool == true)

        harness.eval("__testPort.delete()")
    }

    @Test("Register with console mirroring stores setting")
    func testRegisterConsoleMirroring() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{\"console\":true}')")

        let console = harness.eval("__ipcRegisteredInstances['\(portName)']._cli.console")
        #expect(console as? Bool == true)

        harness.eval("__testPort.delete()")
    }

    @Test("Register with custom args stores them")
    func testRegisterCustomArgs() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{\"customArgs\":[\"--foo\",\"bar\"]}')")

        let args = harness.eval("__ipcRegisteredInstances['\(portName)']._cli.args")
        #expect(args as? [String] == ["--foo", "bar"])

        harness.eval("__testPort.delete()")
    }

    // MARK: - Unregistration

    @Test("Unregister removes instance and port storage")
    func testUnregister() {
        let (harness, portName) = makeHarnessWithPort()

        // Register first
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        // Verify registered
        let before = harness.eval("__ipcRegisteredInstances['\(portName)'] !== undefined")
        #expect(before as? Bool == true)

        // Unregister
        harness.eval("__ipcDefaultHandler(null, 200, '\(portName)')")

        // Verify cleaned up
        let afterInstance = harness.eval("__ipcRegisteredInstances['\(portName)'] === undefined")
        #expect(afterInstance as? Bool == true)

        let afterPort = harness.eval("__ipcRemotePorts['\(portName)'] === undefined")
        #expect(afterPort as? Bool == true)

        harness.eval("__testPort.delete()")
    }

    @Test("Unregister non-existent instance does not error")
    func testUnregisterNonExistent() {
        let harness = makeHarness()
        // Should not throw
        let result = harness.eval("__ipcDefaultHandler(null, 200, 'nonexistent')")
        // Unregister returns undefined (no response needed)
        #expect(harness.hasException == false)
        _ = result // suppress warning
    }

    // MARK: - Query Execution

    @Test("Query returns evaluated result as string")
    func testQueryReturnsResult() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        let result = harness.eval("__ipcDefaultHandler(null, 501, '\(portName)\\x001 + 2')")
        #expect(result as? String == "3")

        harness.eval("__testPort.delete()")
    }

    @Test("Query with undefined result returns empty string")
    func testQueryUndefinedResult() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        let result = harness.eval("__ipcDefaultHandler(null, 501, '\(portName)\\0undefined')")
        #expect(result as? String == "")

        harness.eval("__testPort.delete()")
    }

    @Test("Query with null result returns empty string")
    func testQueryNullResult() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        let result = harness.eval("__ipcDefaultHandler(null, 501, '\(portName)\\0null')")
        #expect(result as? String == "")

        harness.eval("__testPort.delete()")
    }

    @Test("Query evaluates expressions with implicit return")
    func testQueryImplicitReturn() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        let result = harness.eval("__ipcDefaultHandler(null, 501, '\(portName)\\0\"hello\".toUpperCase()')")
        #expect(result as? String == "HELLO")

        harness.eval("__testPort.delete()")
    }

    @Test("Query handles multi-statement code with explicit return")
    func testQueryStatements() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        // var declaration can't be implicit-returned, falls back to statement mode.
        // In statement mode, last expression value is NOT auto-returned (Function behavior),
        // so we need a return statement or use a single expression.
        let result = harness.eval("__ipcDefaultHandler(null, 501, '\(portName)\\0var x = 42; return x')")
        #expect(result as? String == "42")

        harness.eval("__testPort.delete()")
    }

    // MARK: - Command Execution

    @Test("Command returns ok on success")
    func testCommandReturnsOk() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        let result = harness.eval("__ipcDefaultHandler(null, 500, '\(portName)\\x001 + 1')")
        #expect(result as? String == "ok")

        harness.eval("__testPort.delete()")
    }

    @Test("Command returns ok even on eval error")
    func testCommandErrorStillReturnsOk() {
        let (harness, portName) = makeHarnessWithPort()
        harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{}')")

        // Runtime error (not syntax error) should still return "ok" for protocol success
        let result = harness.eval("__ipcDefaultHandler(null, 500, '\(portName)\\0nonexistentVariable.property')")
        #expect(result as? String == "ok")

        harness.eval("__testPort.delete()")
    }

    // MARK: - State Persistence (GC Resilience)

    @Test("Closure-scoped state persists across multiple operations")
    func testStatePersistence() {
        let (harness, portName) = makeHarnessWithPort()

        // Register
        let reg = harness.eval("__ipcDefaultHandler(null, 100, '\(portName)\\0{\"quiet\":true,\"console\":true}')")
        #expect(reg as? String == "ok")

        // Execute multiple queries - state should persist
        for i in 1...5 {
            let result = harness.eval("__ipcDefaultHandler(null, 501, '\(portName)\\x00\(i) * 10')")
            #expect(result as? String == "\(i * 10)")
        }

        // Verify instance still exists after multiple operations
        let stillExists = harness.eval("__ipcRegisteredInstances['\(portName)'] !== undefined")
        #expect(stillExists as? Bool == true)

        // Verify settings persisted
        let quiet = harness.eval("__ipcRegisteredInstances['\(portName)']._cli.quietMode")
        #expect(quiet as? Bool == true)

        harness.eval("__testPort.delete()")
    }

    @Test("Multiple instances can coexist")
    func testMultipleInstances() {
        let harness = makeHarness()
        let port1 = "TestClient1_\(UUID().uuidString)"
        let port2 = "TestClient2_\(UUID().uuidString)"

        // Create two local ports
        harness.eval("""
            var __testPort1 = hs.ipc.localPort("\(port1)", function() { return "ack"; });
            var __testPort2 = hs.ipc.localPort("\(port2)", function() { return "ack"; });
        """)

        // Register both
        let reg1 = harness.eval("__ipcDefaultHandler(null, 100, '\(port1)\\0{\"quiet\":false}')")
        let reg2 = harness.eval("__ipcDefaultHandler(null, 100, '\(port2)\\0{\"quiet\":true}')")
        #expect(reg1 as? String == "ok")
        #expect(reg2 as? String == "ok")

        // Both should exist independently
        let q1 = harness.eval("__ipcRegisteredInstances['\(port1)']._cli.quietMode")
        let q2 = harness.eval("__ipcRegisteredInstances['\(port2)']._cli.quietMode")
        #expect(q1 as? Bool == false)
        #expect(q2 as? Bool == true)

        // Unregister one, other should survive
        harness.eval("__ipcDefaultHandler(null, 200, '\(port1)')")
        let gone = harness.eval("__ipcRegisteredInstances['\(port1)'] === undefined")
        let still = harness.eval("__ipcRegisteredInstances['\(port2)'] !== undefined")
        #expect(gone as? Bool == true)
        #expect(still as? Bool == true)

        harness.eval("__testPort1.delete()")
        harness.eval("__testPort2.delete()")
    }

    // MARK: - Completions

    @Test("completionsForInputString is installed as a function")
    func testCompletionsFunctionExists() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.completionsForInputString === 'function'")
    }

    // MARK: - Print Mirroring

    @Test("__ipcPrint calls original print")
    func testPrintCallsOriginal() {
        let harness = makeHarness()

        // Replace __ipcOriginalPrint with a tracker
        harness.eval("""
            var __printCalled = false;
            __ipcOriginalPrint = function() { __printCalled = true; };
        """)

        harness.eval("__ipcPrint('test')")
        harness.expectTrue("__printCalled")
    }
}
