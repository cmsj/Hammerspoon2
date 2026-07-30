//
//  HSSerialIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import Darwin
@testable import Hammerspoon_2

// MARK: - Helpers

/// A pseudo-terminal pair used as a stand-in for real serial hardware.
///
/// `HSSerialPort` opens `slavePath` exactly as it would open a real `/dev/cu.*` device
/// (POSIX open + termios), while the test drives the far end directly via `masterFD`.
/// This lets the read/write/lifecycle code paths be exercised for real, without requiring
/// any physical serial hardware to be attached to the test machine.
private final class TempPTY {
    let masterFD: Int32
    let slavePath: String

    init() throws {
        let master = posix_openpt(O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard master >= 0 else {
            throw NSError(domain: "TempPTY", code: 1, userInfo: [NSLocalizedDescriptionKey: "posix_openpt failed"])
        }
        guard grantpt(master) == 0, unlockpt(master) == 0, let namePtr = ptsname(master) else {
            Darwin.close(master)
            throw NSError(domain: "TempPTY", code: 2, userInfo: [NSLocalizedDescriptionKey: "failed to prepare pty slave"])
        }
        self.masterFD = master
        self.slavePath = String(cString: namePtr)
    }

    deinit {
        Darwin.close(masterFD)
    }

    func writeToMaster(_ string: String) {
        guard let bytes = string.data(using: .isoLatin1) else { return }
        _ = [UInt8](bytes).withUnsafeBufferPointer { ptr in
            Darwin.write(masterFD, ptr.baseAddress, ptr.count)
        }
    }

    /// Non-blocking read; returns nil if no data is currently available.
    func readFromMaster() -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = buffer.withUnsafeMutableBytes { ptr in
            Darwin.read(masterFD, ptr.baseAddress, ptr.count)
        }
        guard count > 0 else { return nil }
        return String(bytes: buffer[0..<count], encoding: .isoLatin1)
    }

    /// Polls `readFromMaster()` until data appears or `timeout` elapses.
    func waitForDataFromMaster(timeout: TimeInterval = 2.0) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = readFromMaster() { return data }
            usleep(5000)
        }
        return nil
    }
}

// MARK: - Test suite

@MainActor
@Suite("hs.serial tests")
struct HSSerialTests {

    // MARK: - Module API structure

    @Suite("hs.serial module API structure tests")
    struct HSSerialModuleStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")
            return harness
        }

        @Test("availablePortNames is a function")
        func testAvailablePortNamesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial.availablePortNames") == "function")
        }

        @Test("availablePortPaths is a function")
        func testAvailablePortPathsIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial.availablePortPaths") == "function")
        }

        @Test("availablePortDetails is a function")
        func testAvailablePortDetailsIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial.availablePortDetails") == "function")
        }

        @Test("createPortNamed is a function")
        func testCreatePortNamedIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial.createPortNamed") == "function")
        }

        @Test("createPortAtPath is a function")
        func testCreatePortAtPathIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial.createPortAtPath") == "function")
        }

        @Test("addWatcher is a function")
        func testAddWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial.addWatcher") == "function")
        }

        @Test("removeWatcher is a function")
        func testRemoveWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial.removeWatcher") == "function")
        }

        @Test("_addWatcher is a function")
        func testPrivateAddWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial._addWatcher") == "function")
        }

        @Test("_removeWatcher is a function")
        func testPrivateRemoveWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.serial._removeWatcher") == "function")
        }

        @Test("_watcherEmitter is initialized by hs.serial.js")
        func testWatcherEmitterInitialized() {
            makeHarness().expectTrue(
                "hs.serial._watcherEmitter !== null && hs.serial._watcherEmitter !== undefined"
            )
        }

        @Test("availablePortNames returns an array")
        func testAvailablePortNamesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.serial.availablePortNames())")
            #expect(!harness.hasException)
        }

        @Test("availablePortPaths returns an array")
        func testAvailablePortPathsReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.serial.availablePortPaths())")
            #expect(!harness.hasException)
        }

        @Test("availablePortDetails returns an object")
        func testAvailablePortDetailsReturnsObject() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.serial.availablePortDetails()") == "object")
            #expect(!harness.hasException)
        }

        @Test("createPortNamed with an unknown name returns null")
        func testCreatePortNamedUnknown() {
            let harness = makeHarness()
            harness.eval("var p = hs.serial.createPortNamed('definitely-not-a-real-port-\(UUID().uuidString)')")
            harness.expectTrue("p === null || p === undefined")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Port object structure

    @Suite("hs.serial port API structure tests")
    struct HSSerialPortStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")
            return harness
        }

        private func makePort(_ harness: JSTestHarness) {
            harness.eval("var p = hs.serial.createPortAtPath('/dev/cu.doesnotexist-\(UUID().uuidString)')")
        }

        @Test("createPortAtPath returns an object")
        func testCreatePortAtPathReturnsObject() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalTypeOf("p") == "object")
            #expect(!harness.hasException)
        }

        @Test("port has a string identifier")
        func testPortHasIdentifier() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalTypeOf("p.identifier") == "string")
            harness.expectTrue("p.identifier.length > 0")
        }

        @Test("two ports have different identifiers")
        func testPortsHaveUniqueIdentifiers() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var a = hs.serial.createPortAtPath('/dev/cu.a')
                    var b = hs.serial.createPortAtPath('/dev/cu.b')
                    return a.identifier !== b.identifier
                })()
            """)
            #expect(!harness.hasException)
        }

        @Test("name and path are strings matching construction arguments")
        func testNameAndPath() {
            let harness = makeHarness()
            harness.eval("var p = hs.serial.createPortAtPath('/dev/cu.mydevice')")
            #expect(harness.evalString("p.path") == "/dev/cu.mydevice")
            #expect(harness.evalString("p.name") == "cu.mydevice")
        }

        @Test("isOpen defaults to false")
        func testIsOpenDefault() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalBool("p.isOpen") == false)
        }

        @Test("baudRate defaults to 115200")
        func testBaudRateDefault() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalInt("p.baudRate") == 115200)
        }

        @Test("dataBits defaults to 8")
        func testDataBitsDefault() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalInt("p.dataBits") == 8)
        }

        @Test("stopBits defaults to 1")
        func testStopBitsDefault() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalInt("p.stopBits") == 1)
        }

        @Test("parity defaults to none")
        func testParityDefault() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalString("p.parity") == "none")
        }

        @Test("dtr, rts, flow control and echo default to false")
        func testBooleanDefaults() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalBool("p.dtr") == false)
            #expect(harness.evalBool("p.rts") == false)
            #expect(harness.evalBool("p.usesRTSCTSFlowControl") == false)
            #expect(harness.evalBool("p.usesDTRDSRFlowControl") == false)
            #expect(harness.evalBool("p.shouldEchoReceivedData") == false)
            #expect(harness.evalBool("p.allowNonStandardBaudRates") == false)
        }

        @Test("port has open, close, sendData, setCallback and destroy functions")
        func testPortHasMethods() {
            let harness = makeHarness()
            makePort(harness)
            #expect(harness.evalTypeOf("p.open") == "function")
            #expect(harness.evalTypeOf("p.close") == "function")
            #expect(harness.evalTypeOf("p.sendData") == "function")
            #expect(harness.evalTypeOf("p.setCallback") == "function")
            #expect(harness.evalTypeOf("p.destroy") == "function")
        }
    }

    // MARK: - Configuration validation

    @Suite("hs.serial port configuration tests")
    struct HSSerialPortConfigurationTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")
            harness.eval("var p = hs.serial.createPortAtPath('/dev/cu.doesnotexist-\(UUID().uuidString)')")
            return harness
        }

        @Test("baudRate accepts a standard value")
        func testBaudRateAcceptsStandard() {
            let harness = makeHarness()
            harness.eval("p.baudRate = 9600")
            #expect(harness.evalInt("p.baudRate") == 9600)
        }

        @Test("baudRate rejects a non-standard value without allowNonStandardBaudRates")
        func testBaudRateRejectsNonStandard() {
            let harness = makeHarness()
            harness.eval("p.baudRate = 123456")
            #expect(harness.evalInt("p.baudRate") == 115200)
        }

        @Test("baudRate accepts a non-standard value when allowNonStandardBaudRates is true")
        func testBaudRateAllowsNonStandard() {
            let harness = makeHarness()
            harness.eval("p.allowNonStandardBaudRates = true; p.baudRate = 123456")
            #expect(harness.evalInt("p.baudRate") == 123456)
        }

        @Test("dataBits rejects out-of-range values")
        func testDataBitsRejectsInvalid() {
            let harness = makeHarness()
            harness.eval("p.dataBits = 3")
            #expect(harness.evalInt("p.dataBits") == 8)
            harness.eval("p.dataBits = 9")
            #expect(harness.evalInt("p.dataBits") == 8)
        }

        @Test("dataBits accepts values 5 through 8")
        func testDataBitsAcceptsValid() {
            let harness = makeHarness()
            for bits in 5...8 {
                harness.eval("p.dataBits = \(bits)")
                #expect(harness.evalInt("p.dataBits") == bits)
            }
        }

        @Test("stopBits rejects values other than 1 or 2")
        func testStopBitsRejectsInvalid() {
            let harness = makeHarness()
            harness.eval("p.stopBits = 3")
            #expect(harness.evalInt("p.stopBits") == 1)
        }

        @Test("stopBits accepts 2")
        func testStopBitsAcceptsTwo() {
            let harness = makeHarness()
            harness.eval("p.stopBits = 2")
            #expect(harness.evalInt("p.stopBits") == 2)
        }

        @Test("parity rejects an unknown value")
        func testParityRejectsInvalid() {
            let harness = makeHarness()
            harness.eval("p.parity = 'nonsense'")
            #expect(harness.evalString("p.parity") == "none")
        }

        @Test("parity accepts odd and even")
        func testParityAcceptsValid() {
            let harness = makeHarness()
            harness.eval("p.parity = 'odd'")
            #expect(harness.evalString("p.parity") == "odd")
            harness.eval("p.parity = 'even'")
            #expect(harness.evalString("p.parity") == "even")
        }

        @Test("dtr, rts and flow control flags round-trip")
        func testBooleanRoundTrip() {
            let harness = makeHarness()
            harness.eval("""
                p.dtr = true
                p.rts = true
                p.usesRTSCTSFlowControl = true
                p.usesDTRDSRFlowControl = true
                p.shouldEchoReceivedData = true
            """)
            #expect(harness.evalBool("p.dtr") == true)
            #expect(harness.evalBool("p.rts") == true)
            #expect(harness.evalBool("p.usesRTSCTSFlowControl") == true)
            #expect(harness.evalBool("p.usesDTRDSRFlowControl") == true)
            #expect(harness.evalBool("p.shouldEchoReceivedData") == true)
        }
    }

    // MARK: - Lifecycle (using a pseudo-terminal in place of real hardware)

    @Suite("hs.serial port lifecycle tests", .serialized)
    struct HSSerialPortLifecycleTests {

        private func makeHarness(path: String) -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")
            harness.eval("var p = hs.serial.createPortAtPath('\(path)')")
            return harness
        }

        @Test("open() on a valid pty returns self and sets isOpen")
        func testOpenSucceeds() throws {
            let pty = try TempPTY()
            let harness = makeHarness(path: pty.slavePath)
            harness.eval("var same = (p.open() === p)")
            harness.expectTrue("same")
            #expect(harness.evalBool("p.isOpen") == true)
            #expect(!harness.hasException)
            harness.eval("p.close()")
        }

        @Test("open() on a nonexistent path fails gracefully")
        func testOpenNonExistentPath() {
            let harness = makeHarness(path: "/dev/cu.definitely-not-real-\(UUID().uuidString)")
            harness.eval("p.open()")
            #expect(harness.evalBool("p.isOpen") == false)
            #expect(!harness.hasException)
        }

        @Test("close() returns self for chaining")
        func testCloseChaining() throws {
            let pty = try TempPTY()
            let harness = makeHarness(path: pty.slavePath)
            harness.eval("p.open(); var same = (p.close() === p)")
            harness.expectTrue("same")
            #expect(harness.evalBool("p.isOpen") == false)
        }

        @Test("setCallback returns self for chaining")
        func testSetCallbackChaining() {
            let harness = makeHarness(path: "/dev/cu.whatever")
            harness.eval("var same = (p.setCallback(function() {}) === p)")
            harness.expectTrue("same")
            #expect(!harness.hasException)
        }

        @Test("calling open() twice does not crash")
        func testDoubleOpen() throws {
            let pty = try TempPTY()
            let harness = makeHarness(path: pty.slavePath)
            harness.eval("p.open(); p.open()")
            #expect(harness.evalBool("p.isOpen") == true)
            #expect(!harness.hasException)
            harness.eval("p.close()")
        }

        @Test("calling close() before open() does not crash")
        func testCloseBeforeOpen() {
            let harness = makeHarness(path: "/dev/cu.whatever")
            harness.eval("p.close()")
            #expect(!harness.hasException)
        }

        @Test("destroy() on an open port does not crash")
        func testDestroyOpen() throws {
            let pty = try TempPTY()
            let harness = makeHarness(path: pty.slavePath)
            harness.eval("p.setCallback(function() {}).open(); p.destroy()")
            #expect(!harness.hasException)
            #expect(harness.evalBool("p.isOpen") == false)
        }

        @Test("sendData() on a closed port fires an error event")
        func testSendDataWhenClosed() async {
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")

            var firedEvent: String?
            harness.registerCallback("onEvent") { (event: String) in firedEvent = event }

            harness.eval("""
                var p = hs.serial.createPortAtPath('/dev/cu.whatever')
                p.setCallback((event, data) => onEvent(event))
                p.sendData('hello')
            """)
            #expect(!harness.hasException)

            let fired = await harness.waitForAsync(timeout: 2.0) { firedEvent != nil }
            #expect(fired)
            #expect(firedEvent == "error")
        }
    }

    // MARK: - I/O (using a pseudo-terminal in place of real hardware)

    @Suite("hs.serial port I/O tests", .serialized)
    struct HSSerialPortIOTests {

        @Test("data written to the far end of the pty fires a received event")
        func testReceivedData() async throws {
            let pty = try TempPTY()
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")

            var receivedData: String?
            harness.registerCallback("onReceived") { (data: String) in receivedData = data }

            harness.eval("""
                var p = hs.serial.createPortAtPath('\(pty.slavePath)')
                p.setCallback((event, data) => {
                    if (event === 'received') { onReceived(data) }
                }).open()
            """)
            #expect(!harness.hasException)

            pty.writeToMaster("hello serial")

            let fired = await harness.waitForAsync(timeout: 5.0) { receivedData != nil }
            #expect(fired, "received callback should have fired")
            #expect(receivedData == "hello serial")

            harness.eval("p.close()")
        }

        @Test("sendData() delivers bytes to the far end of the pty")
        func testSendDataDeliversToFarEnd() throws {
            let pty = try TempPTY()
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")

            harness.eval("""
                var p = hs.serial.createPortAtPath('\(pty.slavePath)')
                p.open()
                p.sendData('ping')
            """)
            #expect(!harness.hasException)

            let received = pty.waitForDataFromMaster()
            #expect(received == "ping")

            harness.eval("p.close()")
        }

        @Test("shouldEchoReceivedData delivers sent data back to the callback locally")
        func testShouldEchoReceivedData() async throws {
            let pty = try TempPTY()
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")

            var receivedData: String?
            harness.registerCallback("onReceived") { (data: String) in receivedData = data }

            harness.eval("""
                var p = hs.serial.createPortAtPath('\(pty.slavePath)')
                p.shouldEchoReceivedData = true
                p.setCallback((event, data) => {
                    if (event === 'received') { onReceived(data) }
                }).open()
                p.sendData('echoed')
            """)
            #expect(!harness.hasException)

            let fired = await harness.waitForAsync(timeout: 5.0) { receivedData != nil }
            #expect(fired)
            #expect(receivedData == "echoed")

            harness.eval("p.close()")
        }

        @Test("open() fires an opened event, close() fires a closed event")
        func testOpenCloseEvents() async throws {
            let pty = try TempPTY()
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")

            var events: [String] = []
            harness.registerCallback("onEvent") { (event: String) in events.append(event) }

            harness.eval("""
                var p = hs.serial.createPortAtPath('\(pty.slavePath)')
                p.setCallback((event, data) => onEvent(event))
                p.open()
            """)
            let opened = await harness.waitForAsync(timeout: 2.0) { events.contains("opened") }
            #expect(opened)

            harness.eval("p.close()")
            let closed = await harness.waitForAsync(timeout: 2.0) { events.contains("closed") }
            #expect(closed)
        }
    }

    // MARK: - Device watcher

    @Suite("hs.serial device watcher tests")
    struct HSSerialDeviceWatcherTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")
            return harness
        }

        @Test("addWatcher with non-function causes a context exception")
        func testAddWatcherNonFunctionCausesException() {
            let harness = makeHarness()
            harness.eval("hs.serial.addWatcher('notAFunction')")
            harness.expectException()
        }

        @Test("addWatcher and removeWatcher do not throw with a function")
        func testAddRemoveWatcherNoThrow() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(event, port) {};
                hs.serial.addWatcher(fn);
                hs.serial.removeWatcher(fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("duplicate addWatcher registration is silently rejected")
        func testDuplicateWatcherRejected() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(event, port) {};
                hs.serial.addWatcher(fn);
                hs.serial.addWatcher(fn);
                hs.serial.removeWatcher(fn);
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Memory leak test

    @Test("active HSSerialPort is released after shutdown")
    func testSerialPortDoesNotLeakAfterReload() throws {
        let pty = try TempPTY()
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSSerialModule.self, as: "serial")

            harness.eval("""
                var p = hs.serial.createPortAtPath('\(pty.slavePath)')
                p.setCallback(function(event, data) {})
                p.open()
            """)

            if let swift = harness.evalValue("p")?.toObjectOf(HSSerialPort.self) as? HSSerialPort {
                tracker.track(swift)
            }

            harness.eval("p = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
