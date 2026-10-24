//
//  HSBluetoothIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import CoreBluetooth
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

    /// Puts a device with no Bluetooth backend in the global `dev`. It behaves like a BLE
    /// peripheral that has gone away, which exercises the device API without any hardware.
    private static func makeDevice(in harness: JSTestHarness) throws -> HSBluetoothDevice {
        let device = try module(in: harness).makeDevice(classic: nil, record: nil)
        harness.context.setObject(device, forKeyedSubscript: "dev" as NSString)
        return device
    }

    // MARK: - Suite 1: API structure and emitter wiring (no Bluetooth access)

    @Suite("hs.bluetooth API structure tests")
    struct HSBluetoothStructureTests {

        @Test("API structure", arguments: ["pairedDevices", "connectedDevices", "device", "scan", "stopScan",
                                           "on", "off", "once", "_addWatcher", "_removeWatcher", "_makeDeviceEmitter"])
        func testIsFunction(_ name: String) {
            #expect(makeHarness().evalTypeOf("hs.bluetooth." + name) == "function")
        }

        @Test("_watcherEmitter is initialised by hs.bluetooth.js")
        func testWatcherEmitterInitialised() {
            makeHarness().expectTrue("hs.bluetooth._watcherEmitter !== null && hs.bluetooth._watcherEmitter !== undefined")
        }

        @Test("isScanning is false before any scan")
        func testIsScanningDefault() {
            #expect(makeHarness().evalBool("hs.bluetooth.isScanning") == false)
        }

        @Test("toString() describes the module without touching Bluetooth")
        func testToString() {
            #expect(makeHarness().evalString("String(hs.bluetooth)") == "<hs.bluetooth>")
        }

        @Test("device() returns null for a malformed address", arguments: ["not-an-address", "", "aa-bb-cc", "zz-zz-zz-zz-zz-zz"])
        func testMalformedAddress(_ id: String) {
            let harness = makeHarness()
            harness.expectTrue("hs.bluetooth.device('\(id)') === null")
            #expect(!harness.hasException)
        }

        @Test("device() returns null for a BLE identifier it has never seen, without starting CoreBluetooth")
        func testUnknownIdentifier() throws {
            let harness = makeHarness()
            harness.expectTrue("hs.bluetooth.device('00000000-0000-0000-0000-000000000000') === null")
            #expect(try module(in: harness).existingCentral == nil)
        }

        @Test("scan() rejects invalid options without touching Bluetooth", arguments: [
            ("{ lowEnergy: false }", "lowEnergy and classic can't both be false"),
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

        @Test("A device without a Bluetooth backend reports empty state")
        func testEmptyDeviceState() throws {
            let harness = makeHarness()
            _ = try makeDevice(in: harness)
            #expect(harness.evalString("dev.typeName") == "HSBluetoothDevice")
            #expect(harness.evalString("String(dev)") == "<HSBluetoothDevice: unnamed (unknown)>")
            for property in ["name", "address", "identifier", "rssi", "lastSeen", "advertisement", "batteryLevel",
                             "batteryLevels", "classOfDevice", "majorClass", "minorClass", "serviceClasses"] {
                #expect(harness.evalBool("dev.\(property) === null") == true, "\(property) should be null")
            }
            #expect(harness.evalBool("dev.isPaired") == false)
            #expect(harness.evalBool("dev.isConnected") == false)
            #expect(harness.evalBool("dev.isFavorite") == false)
            harness.expectTrue("Array.isArray(dev.serviceNames) && dev.serviceNames.length === 0")
            #expect(!harness.hasException)
        }

        @Test("JSON.stringify() uses toJSON()")
        func testToJSON() throws {
            let harness = makeHarness()
            _ = try makeDevice(in: harness)
            harness.eval("var json = JSON.parse(JSON.stringify(dev))")
            #expect(harness.evalString("Object.keys(json).sort().join(',')") ==
                    "address,batteryLevel,batteryLevels,identifier,isConnected,isPaired,majorClass,minorClass,name,rssi")
            #expect(harness.evalBool("json.isConnected") == false)
            harness.expectTrue("json.address === null")
            #expect(!harness.hasException)
        }

        @Test("Operations needing a connection reject, and don't keep the device alive", arguments: [
            ("dev.connect()", "connect", "this device can't be connected to"),
            ("dev.readRSSI()", "readRSSI", "the device is not connected, call connect() first"),
            ("dev.discoverServices()", "discoverServices", "the device is not connected, call connect() first"),
            ("dev.readValue('180F', '2A19')", "readValue", "the device is not connected, call connect() first"),
            ("dev.subscribe('180D', '2A37')", "subscribe", "the device is not connected, call connect() first"),
        ])
        func testOperationsRejectWhenNotConnected(_ call: String, _ method: String, _ reason: String) async throws {
            let harness = makeHarness()
            _ = try makeDevice(in: harness)
            harness.eval("var reason = null; \(call).catch(e => { reason = e; })")
            #expect(!harness.hasException)
            let settled = await harness.waitForAsync(timeout: 1) { harness.evalBool("reason !== null") == true }
            #expect(settled)
            #expect(harness.evalString("reason") == "hs.bluetooth device.\(method)(): \(reason)")
            #expect(try module(in: harness).existingCentral == nil)
        }

        @Test("readBatteryLevel() resolves null when nothing reports a level")
        func testReadBatteryLevelWithoutSource() async throws {
            let harness = makeHarness()
            _ = try makeDevice(in: harness)
            harness.eval("var level, done = false; dev.readBatteryLevel().then(l => { level = l; done = true; })")
            let settled = await harness.waitForAsync(timeout: 1) { harness.evalBool("done") == true }
            #expect(settled)
            harness.expectTrue("level === null")
        }

        @Test("writeValue() rejects values that aren't bytes", arguments: ["{}", "[256]", "[1.5]", "['a']", "null"])
        func testWriteValueRejectsNonBytes(_ value: String) async throws {
            let harness = makeHarness()
            _ = try makeDevice(in: harness)
            harness.eval("var reason = null; dev.writeValue('180F', '2A19', \(value), false).catch(e => { reason = e; })")
            let settled = await harness.waitForAsync(timeout: 1) { harness.evalBool("reason !== null") == true }
            #expect(settled)
            harness.expectTrue("reason.includes('value must be a Uint8Array')")
        }

        @Test("discoverCharacteristics() rejects an invalid UUID")
        func testInvalidUUID() async throws {
            let harness = makeHarness()
            _ = try makeDevice(in: harness)
            harness.eval("var reason = null; dev.discoverCharacteristics('battery').catch(e => { reason = e; })")
            let settled = await harness.waitForAsync(timeout: 1) { harness.evalBool("reason !== null") == true }
            #expect(settled)
            #expect(harness.evalString("reason") == "hs.bluetooth device.discoverCharacteristics(): 'battery' is not a valid Bluetooth UUID")
        }

        @Test("Device listeners only receive the event they registered for")
        func testDeviceEmitterRouting() throws {
            let harness = makeHarness()
            let device = try makeDevice(in: harness)
            harness.eval("""
                var connected = 0, values = [];
                dev.on('connected', function() { connected++; });
                dev.on('value', function(service, characteristic, value) { values.push(service + '/' + characteristic + '=' + value); });
            """)
            #expect(!harness.hasException)
            device.fire(.connected)
            device.fire(.value, ["180D", "2A37", [1, 72]])
            device.fire(.disconnected)
            #expect(harness.evalInt("connected") == 1)
            #expect(harness.evalString("values.join(';')") == "180D/2A37=1,72")
            // A device with no classic side needs no IOBluetooth notifications
            #expect(try module(in: harness).isReceivingClassicNotifications == false)
        }

        @Test("Device on() with an unknown event throws and registers nothing")
        func testDeviceUnknownEvent() throws {
            let harness = makeHarness()
            let device = try makeDevice(in: harness)
            harness.eval("""
                var message = null;
                try { dev.on('connect', function() {}); } catch (err) { message = err.message; }
            """)
            #expect(harness.evalString("message")?.contains("unknown event 'connect'") == true)
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
                harness.eval("dev.on('value', function() {}); dev.on('disconnected', function() {})")
                #expect(device.isWatching)
                tracker.track(device)
                harness.eval("dev = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }

    // MARK: - Suite 3: Support helpers

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
    }

    // MARK: - Suite 4: Real Bluetooth stack (skipped unless access was already granted)

    @Suite("hs.bluetooth real-hardware tests",
           .serialized,
           .disabled(if: !isBluetoothAuthorized(), "Bluetooth access not granted"))
    struct HSBluetoothHardwareTests {

        @Test("powered is a boolean")
        func testPoweredIsBoolean() {
            #expect(makeHarness().evalTypeOf("hs.bluetooth.powered") == "boolean")
        }

        @Test("Paired and connected devices are HSBluetoothDevices, and connected paired devices are paired")
        func testDeviceShape() {
            let harness = makeHarness()
            harness.eval("""
                var paired = hs.bluetooth.pairedDevices();
                var connected = hs.bluetooth.connectedDevices();
                var allValid = paired.concat(connected).every(function(d) {
                    return d.typeName === 'HSBluetoothDevice' &&
                           (d.name === null || typeof d.name === 'string') &&
                           typeof d.isConnected === 'boolean' &&
                           (d.batteryLevel === null || typeof d.batteryLevel === 'number');
                });
                var pairedAddresses = paired.map(d => d.address);
                var subset = connected.filter(d => d.address !== null)
                                      .every(d => d.isConnected && pairedAddresses.includes(d.address));
            """)
            harness.expectTrue("Array.isArray(paired) && Array.isArray(connected)")
            harness.expectTrue("paired.every(d => typeof d.address === 'string' && d.isPaired)")
            harness.expectTrue("allValid")
            harness.expectTrue("subset")
            #expect(!harness.hasException)
        }

        @Test("device() finds a paired device by address in either form")
        func testDeviceLookup() {
            let harness = makeHarness()
            harness.eval("""
                var paired = hs.bluetooth.pairedDevices();
                var ok = paired.length === 0 || (function() {
                    var address = paired[0].address;
                    var colons = address.toUpperCase().replace(/-/g, ':');
                    var byDash = hs.bluetooth.device(address), byColon = hs.bluetooth.device(colons);
                    return byDash !== null && byDash.address === address && byColon.address === address;
                })();
            """)
            harness.expectTrue("ok")
            #expect(!harness.hasException)
        }

        @Test("A short BLE scan resolves with devices")
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
            harness.expectTrue("failure === null ? Array.isArray(result) : failure.includes('Bluetooth is turned off')")
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
