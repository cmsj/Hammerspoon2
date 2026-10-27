//
//  HSBluetoothIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import CoreBluetooth
import IOBluetooth
@testable import Hammerspoon_2

/// True only when the user has already granted Bluetooth access. Reading the authorization
/// state never shows the prompt, unlike the first IOBluetooth or CoreBluetooth call does.
private nonisolated func isBluetoothAuthorized() -> Bool {
    CBManager.authorization == .allowedAlways
}

@Suite("hs.bluetooth tests")
struct HSBluetoothTests {

    private static func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBluetoothModule.self, as: "bluetooth")
        return harness
    }

    private static func module(in harness: JSTestHarness) throws -> HSBluetoothModule {
        try #require(harness.evalValue("hs.bluetooth")?.toObjectOf(HSBluetoothModule.self) as? HSBluetoothModule)
    }

    private static let testAddress = "a4-83-e7-12-34-56"

    /// A stand-in for an IOBluetooth device: touching a real one can wait for the Bluetooth
    /// permission prompt, which a test must never show
    private final class FakeClassicDevice: HSClassicBluetoothDevice {
        var name: String? = "Test Keyboard"
        var isPaired = true
        var isConnected = false
        var isFavorite = false
        var classOfDevice = 0x2540
        var majorClass = 5
        var minorClass = 16
        var serviceClasses = 1
        var serviceNames = ["Keyboard"]
        var lastRSSI: Int? = -60
        var lastSeen: Date? = nil
        var batteryLevels = HSBluetoothBatteryLevels(level: 80, left: nil, right: nil, caseLevel: nil)
        var connectionResult: IOReturn = kIOReturnSuccess
        var connectionAttempts = 0

        func currentRSSI() -> Int? { isConnected ? -55 : nil }

        func openConnection(completion: @escaping @MainActor (IOReturn) -> Void) throws {
            connectionAttempts += 1
            let result = connectionResult
            Task { @MainActor in
                if result == kIOReturnSuccess { self.isConnected = true }
                completion(result)
            }
        }

        func closeConnection() -> IOReturn {
            isConnected = false
            return kIOReturnSuccess
        }
    }

    /// Puts a device object for a fake device in the global `dev`. Its connection notifications
    /// are simulated, so nothing here needs Bluetooth access.
    @discardableResult
    private static func makeDevice(in harness: JSTestHarness, _ classic: FakeClassicDevice = FakeClassicDevice()) throws -> HSBluetoothDevice {
        let module = try module(in: harness)
        module.simulatesClassicNotifications = true
        let device = module.makeDevice(classic, address: testAddress)
        harness.context.setObject(device, forKeyedSubscript: "dev" as NSString)
        return device
    }

    // MARK: - Suite 1: API structure and emitter wiring (no Bluetooth access)

    @Suite("hs.bluetooth API structure tests")
    struct HSBluetoothStructureTests {

        @Test("API structure", arguments: ["pairedDevices", "connectedDevices", "device", "connectedPeripherals", "peripheral",
                                           "scan", "stopScan", "inquiry", "stopInquiry",
                                           "on", "off", "once", "_addWatcher", "_removeWatcher", "_makeObjectEmitter"])
        func testIsFunction(_ name: String) {
            #expect(makeHarness().evalTypeOf("hs.bluetooth." + name) == "function")
        }

        @Test("_watcherEmitter is initialised by hs.bluetooth.js")
        func testWatcherEmitterInitialised() {
            makeHarness().expectTrue("hs.bluetooth._watcherEmitter !== null && hs.bluetooth._watcherEmitter !== undefined")
        }

        @Test("isScanning and isInquiring are false before anything starts")
        func testActivityDefaults() {
            let harness = makeHarness()
            #expect(harness.evalBool("hs.bluetooth.isScanning") == false)
            #expect(harness.evalBool("hs.bluetooth.isInquiring") == false)
        }

        @Test("toString() describes the module without touching Bluetooth")
        func testToString() throws {
            let harness = makeHarness()
            #expect(harness.evalString("String(hs.bluetooth)") == "<hs.bluetooth>")
            #expect(try module(in: harness).existingCentral == nil)
        }

        @Test("device() returns null for a malformed address", arguments: ["not-an-address", "", "aa-bb-cc", "zz-zz-zz-zz-zz-zz",
                                                                             "00000000-0000-0000-0000-000000000000"])
        func testMalformedAddress(_ address: String) {
            let harness = makeHarness()
            harness.expectTrue("hs.bluetooth.device('\(address)') === null")
            #expect(!harness.hasException)
        }

        @Test("peripheral() returns null for an identifier it has never seen, without starting CoreBluetooth",
              arguments: ["00000000-0000-0000-0000-000000000000", "a4-83-e7-12-34-56", "nonsense"])
        func testUnknownPeripheral(_ identifier: String) throws {
            let harness = makeHarness()
            harness.expectTrue("hs.bluetooth.peripheral('\(identifier)') === null")
            #expect(try module(in: harness).existingCentral == nil)
        }

        @Test("connectedPeripherals() is empty, without starting CoreBluetooth")
        func testConnectedPeripheralsEmpty() throws {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.bluetooth.connectedPeripherals()) && hs.bluetooth.connectedPeripherals().length === 0")
            #expect(try module(in: harness).existingCentral == nil)
        }

        @Test("scan() rejects invalid options without touching Bluetooth", arguments: [
            ("{ seconds: -1 }", "seconds must be a positive number"),
            ("{ seconds: 0 }", "seconds must be a positive number"),
            ("{ services: ['not-a-uuid'] }", "'not-a-uuid' is not a valid Bluetooth UUID"),
            ("{ services: '180F' }", "services must be an array of UUID strings"),
        ])
        func testScanRejectsInvalidOptions(_ options: String, _ reason: String) throws {
            let harness = makeHarness()
            // Promise reactions run as microtasks once the script finishes, so this is settled
            // by the time eval returns
            harness.eval("var reason = null; hs.bluetooth.scan(\(options)).catch(e => { reason = e; })")
            #expect(harness.evalString("reason") == "hs.bluetooth.scan(): " + reason)
            #expect(harness.evalBool("hs.bluetooth.isScanning") == false)
            #expect(try module(in: harness).existingCentral == nil)
        }

        @Test("inquiry() rejects invalid options without touching Bluetooth", arguments: ["{ seconds: 0 }", "{ seconds: -5 }", "{ seconds: 256 }"])
        func testInquiryRejectsInvalidOptions(_ options: String) {
            let harness = makeHarness()
            harness.eval("var reason = null; hs.bluetooth.inquiry(\(options)).catch(e => { reason = e; })")
            #expect(harness.evalString("reason") == "hs.bluetooth.inquiry(): seconds must be a number from 1 to 255")
            #expect(harness.evalBool("hs.bluetooth.isInquiring") == false)
        }

        @Test("listeners only receive the event they registered for, once fires once")
        func testEmitterRouting() {
            let harness = makeHarness()
            // Stub the native start/stop hooks so this stays a pure routing test that never
            // needs Bluetooth access
            harness.eval("""
                var started = [];
                hs.bluetooth._watcherEmitter._start = function(event) { started.push(event); return true; };
                hs.bluetooth._watcherEmitter._stop = function() {};
                var connectedCount = 0, disconnectedCount = 0, onceCount = 0, powered = null;
                hs.bluetooth.on('connected', function() { connectedCount++; });
                hs.bluetooth.on('disconnected', function() { disconnectedCount++; });
                hs.bluetooth.once('connected', function() { onceCount++; });
                hs.bluetooth.on('powerChanged', function(on) { powered = on; });
                hs.bluetooth._watcherEmitter.emit('connected', {});
                hs.bluetooth._watcherEmitter.emit('connected', {});
                hs.bluetooth._watcherEmitter.emit('powerChanged', false);
            """)
            #expect(harness.evalInt("connectedCount") == 2)
            #expect(harness.evalInt("disconnectedCount") == 0)
            #expect(harness.evalInt("onceCount") == 1)
            #expect(harness.evalBool("powered") == false)
            // Each event's native source is started separately
            #expect(harness.evalString("started.join(',')") == "connected,disconnected,powerChanged")
            #expect(!harness.hasException)
        }

        @Test("'discovered' listeners can be added without starting anything native")
        func testDiscoveredNeedsNothingNative() throws {
            let harness = makeHarness()
            harness.eval("hs.bluetooth.on('discovered', function() {})")
            #expect(!harness.hasException)
            let module = try module(in: harness)
            #expect(module.existingCentral == nil)
            #expect(!module.isReceivingClassicNotifications)
        }

        @Test("on with non-function listener causes a context exception")
        func testOnNonFunctionCausesException() {
            let harness = makeHarness()
            harness.eval("hs.bluetooth.on('connected', 'notAFunction')")
            harness.expectException()
        }

        @Test("on/off/once survive garbage collection of the module's JS wrapper")
        func testOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSBluetoothModule.self, as: "bluetooth")
            harness.collectGarbage()
            #expect(harness.evalTypeOf("hs.bluetooth.on") == "function")
            #expect(harness.evalTypeOf("hs.bluetooth.off") == "function")
            #expect(harness.evalTypeOf("hs.bluetooth.once") == "function")
        }
    }

    // MARK: - Suite 2: Device objects (no Bluetooth access)

    @Suite("hs.bluetooth device tests")
    struct HSBluetoothDeviceTests {

        @Test("A device reports what IOBluetooth knows about it")
        func testProperties() throws {
            let harness = makeHarness()
            try makeDevice(in: harness)
            #expect(harness.evalString("dev.typeName") == "HSBluetoothDevice")
            #expect(harness.evalString("dev.address") == testAddress)
            #expect(harness.evalString("dev.name") == "Test Keyboard")
            #expect(harness.evalString("String(dev)") == "<HSBluetoothDevice: Test Keyboard (\(testAddress))>")
            #expect(harness.evalBool("dev.isPaired") == true)
            #expect(harness.evalBool("dev.isConnected") == false)
            #expect(harness.evalInt("dev.majorClass") == 5)
            #expect(harness.evalInt("dev.minorClass") == 16)
            #expect(harness.evalInt("dev.rssi") == -60)
            #expect(harness.evalInt("dev.batteryLevel") == 80)
            harness.expectTrue("dev.batteryLevels === null")
            harness.expectTrue("dev.lastSeen === null")
            #expect(harness.evalString("dev.serviceNames.join(',')") == "Keyboard")
            #expect(!harness.hasException)
        }

        @Test("JSON.stringify() uses toJSON()")
        func testToJSON() throws {
            let harness = makeHarness()
            try makeDevice(in: harness)
            harness.eval("var json = JSON.parse(JSON.stringify(dev))")
            #expect(harness.evalString("Object.keys(json).sort().join(',')") ==
                    "address,batteryLevel,batteryLevels,isConnected,isPaired,majorClass,minorClass,name,rssi")
            #expect(harness.evalString("json.address") == testAddress)
            #expect(harness.evalInt("json.batteryLevel") == 80)
            harness.expectTrue("json.batteryLevels === null")
            #expect(!harness.hasException)
        }

        @Test("connect() resolves to the device once IOBluetooth reports the connection")
        func testConnect() async throws {
            let harness = makeHarness()
            let fake = FakeClassicDevice()
            try makeDevice(in: harness, fake)
            harness.eval("var result = null; dev.connect().then(d => { result = d; }, e => { result = e; })")
            let settled = await harness.waitForAsync(timeout: 1) { harness.evalBool("result !== null") == true }
            #expect(settled)
            harness.expectTrue("result === dev")
            #expect(harness.evalBool("dev.isConnected") == true)
            #expect(fake.connectionAttempts == 1)

            // Already connected: resolves without connecting again
            harness.eval("result = null; dev.connect().then(d => { result = d; })")
            _ = await harness.waitForAsync(timeout: 1) { harness.evalBool("result !== null") == true }
            #expect(fake.connectionAttempts == 1)
        }

        @Test("connect() rejects with IOBluetooth's error when the connection fails")
        func testConnectFailure() async throws {
            let harness = makeHarness()
            let fake = FakeClassicDevice()
            fake.connectionResult = kIOReturnTimeout
            try makeDevice(in: harness, fake)
            harness.eval("var reason = null; dev.connect().catch(e => { reason = e; })")
            let settled = await harness.waitForAsync(timeout: 1) { harness.evalBool("reason !== null") == true }
            #expect(settled)
            harness.expectTrue("reason.startsWith('hs.bluetooth device.connect(): Connecting failed (IOReturn 0x')")
            #expect(harness.evalBool("dev.isConnected") == false)
        }

        @Test("readRSSI() and disconnect() work on a connected device")
        func testConnectedOperations() async throws {
            let harness = makeHarness()
            let fake = FakeClassicDevice()
            fake.isConnected = true
            try makeDevice(in: harness, fake)
            harness.eval("""
                var rssi = null, disconnected = null;
                dev.readRSSI().then(r => { rssi = r; });
                dev.disconnect().then(d => { disconnected = d; });
            """)
            let settled = await harness.waitForAsync(timeout: 1) { harness.evalBool("rssi !== null && disconnected !== null") == true }
            #expect(settled)
            #expect(harness.evalInt("rssi") == -55)
            harness.expectTrue("disconnected === dev")
            #expect(!fake.isConnected)
        }

        @Test("Operations needing a connection reject, and don't keep the device alive", arguments: [
            ("dev.readRSSI()", "readRSSI"),
            ("dev.lowEnergyPeripheral()", "lowEnergyPeripheral"),
        ])
        func testOperationsRejectWhenNotConnected(_ call: String, _ method: String) async throws {
            let harness = makeHarness()
            _ = try makeDevice(in: harness)
            harness.eval("var reason = null; \(call).catch(e => { reason = e; })")
            #expect(!harness.hasException)
            let settled = await harness.waitForAsync(timeout: 1) { harness.evalBool("reason !== null") == true }
            #expect(settled)
            #expect(harness.evalString("reason") == "hs.bluetooth device.\(method)(): the device is not connected")
            // Rejecting must not have started CoreBluetooth
            #expect(try module(in: harness).existingCentral == nil)
        }

        @Test("Device listeners only receive the event they registered for, and once fires once")
        func testDeviceEmitterRouting() throws {
            let harness = makeHarness()
            let device = try makeDevice(in: harness)
            harness.eval("""
                var connected = 0, disconnected = 0, onceCount = 0;
                dev.on('connected', function() { connected++; });
                dev.once('connected', function() { onceCount++; });
                dev.on('disconnected', function() { disconnected++; });
            """)
            #expect(!harness.hasException)
            #expect(device.isWatching)
            #expect(try module(in: harness).isReceivingClassicNotifications)
            device.fire(.connected)
            device.fire(.connected)
            device.fire(.disconnected)
            #expect(harness.evalInt("connected") == 2)
            #expect(harness.evalInt("onceCount") == 1)
            #expect(harness.evalInt("disconnected") == 1)
        }

        @Test("A system connection event reaches both the device's and the module's listeners")
        func testClassicEventDelivery() throws {
            let harness = makeHarness()
            let device = try makeDevice(in: harness)
            harness.eval("""
                var deviceEvents = 0, moduleDevice = null;
                dev.on('connected', function() { deviceEvents++; });
                hs.bluetooth.on('connected', function(d) { moduleDevice = d; });
            """)
            #expect(!harness.hasException)
            try module(in: harness).deliverClassicEvent(.connected, address: testAddress, device: nil)
            #expect(harness.evalInt("deviceEvents") == 1)
            // The module's listener gets the same object the script holds
            harness.expectTrue("moduleDevice === dev")
        }

        @Test("Removing the last device listener stops the connection notifications")
        func testNotificationsFollowListeners() throws {
            let harness = makeHarness()
            _ = try makeDevice(in: harness)
            let module = try module(in: harness)
            harness.eval("function f() {}; dev.on('connected', f)")
            #expect(module.isReceivingClassicNotifications)
            harness.eval("dev.off('connected', f)")
            #expect(!module.isReceivingClassicNotifications)
        }

        @Test("Device on() with an unknown event throws and registers nothing")
        func testDeviceUnknownEvent() throws {
            let harness = makeHarness()
            let device = try makeDevice(in: harness)
            harness.eval("""
                var message = null;
                try { dev.on('value', function() {}); } catch (err) { message = err.message; }
            """)
            #expect(harness.evalString("message")?.contains("unknown event 'value'") == true)
            #expect(!device.isWatching)
        }

        @Test("A watching device the caller didn't keep keeps delivering events after garbage collection, and is collected once it stops watching")
        func testWatchingDeviceLifetime() throws {
            let harness = makeHarness()
            var received = 0
            harness.registerCallback("onConnected") { received += 1 }
            weak var device: HSBluetoothDevice?
            try autoreleasepool {
                device = try makeDevice(in: harness)
                harness.eval("dev.on('connected', function() { __test_callback('onConnected'); }); delete globalThis.dev; void 0")
            }
            #expect(!harness.hasException)
            harness.collectGarbage()
            #expect(device != nil, "A watching device must not be collected")
            // The listener calls back into the device, which the ObjC bridge autoreleases
            autoreleasepool { device?.fire(.connected) }
            #expect(received == 1, "Its listener must survive garbage collection")

            autoreleasepool { device?._removeWatcher() }
            harness.collectGarbage()
            #expect(device == nil, "A device that stopped watching must be collectable")
        }

        @Test("A device the caller didn't keep is garbage collected")
        func testUnwatchedDeviceIsCollected() throws {
            let harness = makeHarness()
            weak var device: HSBluetoothDevice?
            try autoreleasepool {
                device = try makeDevice(in: harness)
                harness.eval("delete globalThis.dev; void 0")
            }
            harness.collectGarbage()
            #expect(device == nil)
        }

        @Test("A watching HSBluetoothDevice is released after shutdown")
        func testDeviceDoesNotLeakAfterReload() throws {
            let tracker = WeakLeakTracker()
            try autoreleasepool {
                let harness = makeHarness()
                let device = try makeDevice(in: harness)
                harness.eval("dev.on('connected', function() {}); dev.on('disconnected', function() {})")
                #expect(device.isWatching)
                tracker.track(device)
                harness.eval("dev = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }

    // MARK: - Suite 3: Request plumbing (pure Swift)

    @MainActor
    @Suite("hs.bluetooth request tests")
    struct HSBluetoothRequestTests {

        private struct Failure: Error, Equatable {
            let reason: String
        }

        /// Shared state the requests' closures update
        private final class Log {
            var entries: [String] = []
            var count = 0
        }

        /// Lets every Task started so far run up to its first suspension
        private func settleTasks() async {
            for _ in 0..<20 { await Task.yield() }
        }

        @Test("Waiters for the same key share one request, and one settle resolves them all")
        func testSharedWait() async throws {
            let requests = HSBluetoothRequests()
            let log = Log()
            let first = Task { try await requests.wait(for: "read", timeout: .seconds(5)) { log.count += 1 } }
            let second = Task { try await requests.wait(for: "read", timeout: .seconds(5)) { log.count += 1 } }
            await settleTasks()
            #expect(requests.isWaiting(for: "read"))
            requests.settle("read", nil)
            try await first.value
            try await second.value
            #expect(log.count == 1)
            #expect(!requests.isWaiting(for: "read"))
        }

        @Test("Settling with an error fails every waiter for that key only")
        func testSettleWithError() async throws {
            let requests = HSBluetoothRequests()
            let failing = Task { try await requests.wait(for: "write", timeout: .seconds(5)) {} }
            let other = Task { try await requests.wait(for: "read", timeout: .seconds(5)) {} }
            await settleTasks()
            requests.settle("write", Failure(reason: "rejected"))
            await #expect(throws: Failure(reason: "rejected")) { try await failing.value }
            #expect(requests.isWaiting(for: "read"))
            requests.settle("read", nil)
            try await other.value
        }

        @Test("A start that throws fails its waiters with that error")
        func testThrowingStart() async {
            let requests = HSBluetoothRequests()
            await #expect(throws: Failure(reason: "no radio")) {
                try await requests.wait(for: "connect", timeout: .seconds(5)) { throw Failure(reason: "no radio") }
            }
            #expect(!requests.isWaiting(for: "connect"))
        }

        @Test("A waiter that isn't settled in time fails with the timeout error, and a later settle is harmless")
        func testTimeout() async {
            let requests = HSBluetoothRequests()
            await #expect(throws: Failure(reason: "too slow")) {
                try await requests.wait(for: "rssi", timeout: .milliseconds(20), timeoutError: Failure(reason: "too slow")) {}
            }
            #expect(!requests.isWaiting(for: "rssi"))
            requests.settle("rssi", nil)
        }

        @Test("failAll() fails every key")
        func testFailAll() async {
            let requests = HSBluetoothRequests()
            let first = Task { try await requests.wait(for: "a", timeout: .seconds(5)) {} }
            let second = Task { try await requests.wait(for: "b", timeout: .seconds(5)) {} }
            await settleTasks()
            requests.failAll(Failure(reason: "disconnected"))
            await #expect(throws: Failure(reason: "disconnected")) { try await first.value }
            await #expect(throws: Failure(reason: "disconnected")) { try await second.value }
        }

        @Test("close() fails what's waiting and every later request")
        func testClose() async {
            let requests = HSBluetoothRequests()
            let log = Log()
            let pending = Task { try await requests.wait(for: "a", timeout: .seconds(5)) {} }
            await settleTasks()
            requests.close(Failure(reason: "shutting down"))
            await #expect(throws: Failure(reason: "shutting down")) { try await pending.value }
            await #expect(throws: Failure(reason: "shutting down")) {
                try await requests.wait(for: "b", timeout: .seconds(5)) { log.count += 1 }
            }
            await #expect(throws: Failure(reason: "shutting down")) {
                try await requests.serially("lane") { log.count += 1 }
            }
            #expect(log.count == 0)
        }

        @Test("serially() runs a lane's operations one at a time, in order, each with its own request")
        func testSerialLane() async throws {
            let requests = HSBluetoothRequests()
            let log = Log()
            func write(_ value: String) -> Task<Void, Error> {
                Task {
                    try await requests.serially("write") {
                        log.entries.append("start " + value)
                        try await requests.wait(for: "write", timeout: .seconds(5)) {}
                        log.entries.append("done " + value)
                    }
                }
            }
            let first = write("1")
            let second = write("2")
            await settleTasks()
            // The second write hasn't started: its request would otherwise share the first's answer
            #expect(log.entries == ["start 1"])
            requests.settle("write", nil)
            await settleTasks()
            #expect(log.entries == ["start 1", "done 1", "start 2"])
            requests.settle("write", nil)
            try await first.value
            try await second.value
            #expect(log.entries == ["start 1", "done 1", "start 2", "done 2"])
        }

        @Test("A failed operation doesn't block the rest of its lane")
        func testSerialLaneContinuesAfterFailure() async throws {
            let requests = HSBluetoothRequests()
            let log = Log()
            let first = Task { try await requests.serially("notify") { throw Failure(reason: "first failed") } }
            let second = Task { try await requests.serially("notify") { log.count += 1 } }
            await #expect(throws: Failure(reason: "first failed")) { try await first.value }
            try await second.value
            #expect(log.count == 1)
        }

        @Test("Different lanes don't wait for each other")
        func testIndependentLanes() async throws {
            let requests = HSBluetoothRequests()
            let log = Log()
            let blocked = Task {
                try await requests.serially("a") {
                    try await requests.wait(for: "never", timeout: .seconds(5)) {}
                }
            }
            await settleTasks()
            try await requests.serially("b") { log.count += 1 }
            #expect(log.count == 1)
            #expect(requests.isWaiting(for: "never"))
            requests.settle("never", nil)
            try await blocked.value
        }
    }

    // MARK: - Suite 4: Support helpers

    @Suite("hs.bluetooth support tests")
    struct HSBluetoothSupportTests {

        @Test("Addresses are normalised to IOBluetooth's form", arguments: [
            ("A4:83:E7:12:34:56", "a4-83-e7-12-34-56"),
            ("a4-83-e7-12-34-56", "a4-83-e7-12-34-56"),
            ("A4-83-E7-12-34-56", "a4-83-e7-12-34-56"),
        ])
        func testAddressNormalisation(_ input: String, _ expected: String) {
            #expect(HSBluetoothAddress.normalize(input) == expected)
        }

        @Test("Malformed addresses are rejected", arguments: ["", "a4-83-e7-12-34", "a4-83-e7-12-34-56-78", "g4-83-e7-12-34-56", "a483e7123456"])
        func testMalformedAddresses(_ input: String) {
            #expect(HSBluetoothAddress.normalize(input) == nil)
        }

        @Test("GATT UUIDs parse in their short and long forms", arguments: [
            ("180F", "180F"), ("180f", "180F"), ("0x180F", "180F"),
            ("6E400001-B5A3-F393-E0A9-E50E24DCCA9E", "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
        ])
        func testUUIDParsing(_ input: String, _ expected: String) {
            #expect(HSBluetoothUUID.parse(input)?.uuidString == expected)
        }

        @Test("Invalid GATT UUIDs are rejected rather than raising", arguments: ["", "18F", "battery", "180G", "6E400001-B5A3"])
        func testInvalidUUIDs(_ input: String) {
            #expect(HSBluetoothUUID.parse(input) == nil)
        }

        @Test("Earbud battery levels report the lower bud overall, and the case separately")
        func testBatteryLevelComponents() {
            let earbuds = HSBluetoothBatteryLevels(level: nil, left: 80, right: 65, caseLevel: 40)
            #expect(earbuds.overall == 65)
            #expect(earbuds.components == ["left": 80, "right": 65, "case": 40])

            let keyboard = HSBluetoothBatteryLevels(level: 90, left: nil, right: nil, caseLevel: nil)
            #expect(keyboard.overall == 90)
            #expect(keyboard.components == nil)

            #expect(HSBluetoothBatteryLevels().overall == nil)
        }

        @Test("Characteristic properties are named for JavaScript")
        func testCharacteristicPropertyNames() {
            let properties: CBCharacteristicProperties = [.read, .notify, .writeWithoutResponse]
            #expect(properties.names == ["read", "writeWithoutResponse", "notify"])
        }

        @Test("Values to write convert from bytes, arrays and strings, and reject anything else")
        func testBytesFromJS() throws {
            let context = try #require(JSContext())
            func bytes(_ script: String) -> [UInt8]? {
                context.evaluateScript(script).flatMap(HSBluetoothPeripheral.bytes(from:)).map { Array($0) }
            }
            #expect(bytes("new Uint8Array([1, 2, 255])") == [1, 2, 255])
            #expect(bytes("[0, 128, 255]") == [0, 128, 255])
            #expect(bytes("'hi'") == [0x68, 0x69])
            for invalid in ["({})", "[256]", "[1.5]", "['a']", "null", "42"] {
                #expect(bytes(invalid) == nil, "\(invalid) should be rejected")
            }
        }
    }

    // MARK: - Suite 5: Real Bluetooth stack (skipped unless access was already granted)

    @Suite("hs.bluetooth real-hardware tests",
           .serialized,
           .disabled(if: !isBluetoothAuthorized(), "Bluetooth access not granted"))
    struct HSBluetoothHardwareTests {

        @Test("powered is a boolean")
        func testPoweredIsBoolean() {
            #expect(makeHarness().evalTypeOf("hs.bluetooth.powered") == "boolean")
        }

        @Test("Paired and connected devices are HSBluetoothDevices, and connected devices are paired")
        func testDeviceShape() {
            let harness = makeHarness()
            harness.eval("""
                var paired = hs.bluetooth.pairedDevices();
                var connected = hs.bluetooth.connectedDevices();
                var allValid = paired.concat(connected).every(function(d) {
                    return d.typeName === 'HSBluetoothDevice' &&
                           typeof d.address === 'string' &&
                           (d.name === null || typeof d.name === 'string') &&
                           typeof d.isConnected === 'boolean' &&
                           (d.batteryLevel === null || typeof d.batteryLevel === 'number');
                });
                var pairedAddresses = paired.map(d => d.address);
                var subset = connected.every(d => d.isConnected && pairedAddresses.includes(d.address));
            """)
            harness.expectTrue("Array.isArray(paired) && Array.isArray(connected)")
            harness.expectTrue("paired.every(d => d.isPaired)")
            harness.expectTrue("allValid")
            harness.expectTrue("subset")
            #expect(!harness.hasException)
        }

        @Test("device() finds a paired device by address in either form, as the same object")
        func testDeviceLookup() {
            let harness = makeHarness()
            harness.eval("""
                var paired = hs.bluetooth.pairedDevices();
                var ok = paired.length === 0 || (function() {
                    var address = paired[0].address;
                    var colons = address.toUpperCase().replace(/-/g, ':');
                    return hs.bluetooth.device(address) === paired[0] && hs.bluetooth.device(colons) === paired[0];
                })();
            """)
            harness.expectTrue("ok")
            #expect(!harness.hasException)
        }

        @Test("A short BLE scan resolves with peripherals")
        func testShortScan() async {
            let harness = makeHarness()
            harness.eval("""
                var result = null, failure = null;
                hs.bluetooth.scan({ seconds: 0.5 }).then(r => { result = r; }, e => { failure = e; });
                var scanningNow = hs.bluetooth.isScanning;
            """)
            #expect(harness.evalBool("scanningNow") == true)
            let settled = await harness.waitForAsync(timeout: 5) { harness.evalBool("result !== null || failure !== null") == true }
            #expect(settled)
            // Bluetooth may be off on the test machine, which rejects; anything else must resolve
            harness.expectTrue("failure === null ? Array.isArray(result) && result.every(p => p.typeName === 'HSBluetoothPeripheral') : failure.includes('Bluetooth is turned off')")
            #expect(harness.evalBool("hs.bluetooth.isScanning") == false)
        }

        @Test("A second scan while one runs is rejected, and stopScan() resolves the first early")
        func testConcurrentScanRejectedAndStopScan() async {
            let harness = makeHarness()
            harness.eval("""
                var first = null, secondFailure = null;
                hs.bluetooth.scan({ seconds: 30 }).then(r => { first = r; }, e => { first = e; });
                hs.bluetooth.scan().catch(e => { secondFailure = e; });
            """)
            #expect(harness.evalString("secondFailure") == "hs.bluetooth.scan(): a scan is already running")
            harness.eval("hs.bluetooth.stopScan()")
            let settled = await harness.waitForAsync(timeout: 2) { harness.evalBool("first !== null") == true }
            #expect(settled)
            #expect(harness.evalBool("hs.bluetooth.isScanning") == false)
        }
    }
}
