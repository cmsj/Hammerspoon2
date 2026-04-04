//
//  HSIPCIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created on 2025-12-27.
//  Integration tests for hs.ipc module
//

import XCTest
@testable import Hammerspoon_2

nonisolated class HSIPCIntegrationTests: XCTestCase {
    nonisolated(unsafe) var harness: JSTestHarness!

    override func setUp() async throws {
        try await super.setUp()
        let h = await MainActor.run {
            let harness = JSTestHarness()
            harness.loadModuleRoot()
            // Load hs.ipc.js into the test harness context (loadModuleRoot
            // evaluates companion JS via JSEngine.shared, a different context)
            if let ipcJS = Bundle.main.url(forResource: "hs.ipc", withExtension: "js") {
                _ = try? harness.eval(String(contentsOf: ipcJS, encoding: .utf8))
            }
            return harness
        }
        harness = h
    }

    override func tearDown() async throws {
        harness = nil
        try await super.tearDown()
    }

    // MARK: - Module Loading Tests

    @MainActor func testModuleLoads() {
        // Verify hs.ipc module loads without errors
        let result = harness.eval("typeof hs.ipc")
        XCTAssertEqual(result as? String, "object", "hs.ipc should be an object")
    }

    @MainActor func testModuleHasExpectedProperties() {
        // Check for expected functions
        let hasLocalPort = harness.eval("typeof hs.ipc.localPort") as? String
        XCTAssertEqual(hasLocalPort, "function", "hs.ipc.localPort should be a function")

        let hasRemotePort = harness.eval("typeof hs.ipc.remotePort") as? String
        XCTAssertEqual(hasRemotePort, "function", "hs.ipc.remotePort should be a function")

        let hasCliInstall = harness.eval("typeof hs.ipc.cliInstall") as? String
        XCTAssertEqual(hasCliInstall, "function", "hs.ipc.cliInstall should be a function")

        let hasCliUninstall = harness.eval("typeof hs.ipc.cliUninstall") as? String
        XCTAssertEqual(hasCliUninstall, "function", "hs.ipc.cliUninstall should be a function")

        let hasCliStatus = harness.eval("typeof hs.ipc.cliStatus") as? String
        XCTAssertEqual(hasCliStatus, "function", "hs.ipc.cliStatus should be a function")
    }

    // MARK: - Local Port Tests

    @MainActor func testLocalPortCreation() {
        // Create a local port
        let code = """
        var testPort = hs.ipc.localPort("TestPort_\(UUID().uuidString)", function(port, msgID, data) {
            return "pong";
        });
        testPort !== null && testPort !== undefined;
        """

        let result = harness.eval(code)
        XCTAssertEqual(result as? Bool, true, "Local port should be created successfully")

        // Cleanup
        _ = harness.eval("testPort.delete()")
    }

    @MainActor func testLocalPortProperties() {
        let portName = "TestPort_\(UUID().uuidString)"
        let code = """
        var testPort = hs.ipc.localPort("\(portName)", function(port, msgID, data) {
            return "response";
        });
        var result = {
            name: testPort.name,
            isValid: testPort.isValid,
            isRemote: testPort.isRemote
        };
        testPort.delete();
        result;
        """

        if let result = harness.eval(code) as? [String: Any] {
            XCTAssertEqual(result["name"] as? String, portName, "Port name should match")
            XCTAssertEqual(result["isValid"] as? Bool, true, "Port should be valid")
            XCTAssertEqual(result["isRemote"] as? Bool, false, "Port should not be remote")
        } else {
            XCTFail("Failed to get port properties")
        }
    }

    // MARK: - Message Roundtrip Tests

    @MainActor func testMessageRoundtrip() {
        let portName = "TestPort_\(UUID().uuidString)"
        let code = """
        var receivedMsg = null;
        var localPort = hs.ipc.localPort("\(portName)", function(port, msgID, data) {
            receivedMsg = data;
            return "response";
        });

        // Give port time to register
        var remote = hs.ipc.remotePort("\(portName)");
        if (remote) {
            var response = remote.sendMessage("test message", 100, 2.0, false);
            remote.delete();
        }

        var result = receivedMsg;
        localPort.delete();
        result;
        """

        let result = harness.eval(code)
        XCTAssertEqual(result as? String, "test message", "Message should be received correctly")
    }

    // MARK: - CLI Installation Tests
    // These tests require the hs2 binary to be present in the app bundle.
    // The "Development" scheme does not build hs2, so skip when unavailable.

    @MainActor func testCLIInstallation() throws {
        let bundlePath = Bundle.main.bundlePath
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: (bundlePath as NSString).appendingPathComponent("Contents/MacOS/hs2")) ||
            FileManager.default.fileExists(atPath: (bundlePath as NSString).appendingPathComponent("Contents/Frameworks/hs2/hs2")),
            "hs2 binary not present in app bundle (not built by Development scheme)"
        )

        let tempDir = NSTemporaryDirectory() + "hs2test_\(UUID().uuidString)"
        let code = """
        hs.ipc.cliInstall("\(tempDir)", true);
        """

        let result = harness.eval(code)
        XCTAssertEqual(result as? Bool, true, "CLI installation should succeed")

        // Verify symlinks created
        let binPath = (tempDir as NSString).appendingPathComponent("bin/hs2")
        let manPath = (tempDir as NSString).appendingPathComponent("share/man/man1/hs2.1")

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: binPath), "Binary symlink should exist")
        XCTAssertTrue(fm.fileExists(atPath: manPath), "Man page symlink should exist")

        // Cleanup
        let uninstallCode = """
        hs.ipc.cliUninstall("\(tempDir)", true);
        """
        _ = harness.eval(uninstallCode)

        try? fm.removeItem(atPath: tempDir)
    }

    @MainActor func testCLIStatus() throws {
        let bundlePath = Bundle.main.bundlePath
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: (bundlePath as NSString).appendingPathComponent("Contents/MacOS/hs2")) ||
            FileManager.default.fileExists(atPath: (bundlePath as NSString).appendingPathComponent("Contents/Frameworks/hs2/hs2")),
            "hs2 binary not present in app bundle (not built by Development scheme)"
        )

        let tempDir = NSTemporaryDirectory() + "hs2test_\(UUID().uuidString)"

        // Initially not installed
        let statusBefore = harness.eval("hs.ipc.cliStatus('\(tempDir)', true)")
        XCTAssertEqual(statusBefore as? Bool, false, "CLI should not be installed initially")

        // Install
        _ = harness.eval("hs.ipc.cliInstall('\(tempDir)', true)")

        // Now should be installed
        let statusAfter = harness.eval("hs.ipc.cliStatus('\(tempDir)', true)")
        XCTAssertEqual(statusAfter as? Bool, true, "CLI should be installed after cliInstall")

        // Cleanup
        _ = harness.eval("hs.ipc.cliUninstall('\(tempDir)', true)")
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    // MARK: - Default Port Tests

    @MainActor func testDefaultPortExists() {
        // The default "Hammerspoon2" port is created automatically by hs.ipc.js.
        // If Hammerspoon is already running, the port name is taken and __ipcDefaultPort will be null.
        let isNull = harness.eval("__ipcDefaultPort === null") as? Bool ?? false
        if isNull {
            // Port name conflict — skip assertion but don't fail
            print("Note: Default IPC port is null (Hammerspoon may be running)")
            return
        }
        let result = harness.eval("__ipcDefaultPort !== null && __ipcDefaultPort !== undefined")
        XCTAssertEqual(result as? Bool, true, "Default IPC port should exist when no port name conflict")
    }

    @MainActor func testCompletionsFunction() {
        // Test the completionsForInputString function (defined in hs.ipc.js)
        // Access hs.ipc first to trigger lazy module loading, so for...in can find it
        _ = harness.eval("hs.ipc")
        let result = harness.eval("completionsForInputString('hs.')")

        if let completions = result as? [String] {
            XCTAssertTrue(completions.count > 0, "Should return some completions for 'hs.'")
            XCTAssertTrue(completions.allSatisfy { $0.hasPrefix("hs.") }, "All completions should start with 'hs.'")
        } else {
            XCTFail("completionsForInputString should return an array")
        }
    }

    // MARK: - Port Deletion Tests

    @MainActor func testPortDeletion() {
        let portName = "TestPort_\(UUID().uuidString)"
        let code = """
        var testPort = hs.ipc.localPort("\(portName)", function(port, msgID, data) {
            return "response";
        });
        testPort.delete();
        testPort.isValid;
        """

        let result = harness.eval(code)
        XCTAssertEqual(result as? Bool, false, "Port should be invalid after delete()")
    }

    // MARK: - CLI Symlink Target Tests

    @MainActor func testCLIInstallSymlinkTargets() throws {
        let bundlePath = Bundle.main.bundlePath
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: (bundlePath as NSString).appendingPathComponent("Contents/MacOS/hs2")) ||
            FileManager.default.fileExists(atPath: (bundlePath as NSString).appendingPathComponent("Contents/Frameworks/hs2/hs2")),
            "hs2 binary not present in app bundle (not built by Development scheme)"
        )

        let tempDir = NSTemporaryDirectory() + "hs2test_\(UUID().uuidString)"

        // Install
        let installResult = harness.eval("hs.ipc.cliInstall('\(tempDir)', true)")
        XCTAssertEqual(installResult as? Bool, true, "CLI installation should succeed")

        let fm = FileManager.default
        let binPath = (tempDir as NSString).appendingPathComponent("bin/hs2")
        let manPath = (tempDir as NSString).appendingPathComponent("share/man/man1/hs2.1")

        // Verify symlinks point to locations inside the app bundle
        if let binTarget = try? fm.destinationOfSymbolicLink(atPath: binPath) {
            XCTAssertTrue(binTarget.contains("Hammerspoon"), "Binary symlink should point into app bundle")
            XCTAssertTrue(binTarget.hasSuffix("hs2"), "Binary symlink should point to hs2 binary")
        } else {
            XCTFail("Binary symlink should be readable")
        }

        if let manTarget = try? fm.destinationOfSymbolicLink(atPath: manPath) {
            XCTAssertTrue(manTarget.contains("Hammerspoon"), "Man page symlink should point into app bundle")
            XCTAssertTrue(manTarget.hasSuffix("hs2.1"), "Man page symlink should point to hs2.1")
        } else {
            XCTFail("Man page symlink should be readable")
        }

        // Cleanup
        _ = harness.eval("hs.ipc.cliUninstall('\(tempDir)', true)")
        try? fm.removeItem(atPath: tempDir)
    }
}
