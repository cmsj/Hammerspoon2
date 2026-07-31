//
//  HSMIDIIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import CoreMIDI
@testable import Hammerspoon_2

// MARK: - Helpers

/// A virtual MIDI source created by the test itself, used as a stand-in for real MIDI
/// hardware. Since CoreMIDI publishes virtual endpoints system-wide the same way a real
/// external device's endpoints would appear, `hs.midi.virtualSources()` / `virtualSourceNamed()`
/// can observe and connect to it exactly as they would a real device — no physical MIDI
/// hardware is required to exercise the receive path end-to-end.
private final class TestMIDIVirtualSource {
    let name: String
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()

    init(name: String) throws {
        self.name = name

        // The full test suite runs hundreds of tests across many suites concurrently, and
        // MIDIClientCreateWithBlock intermittently fails under that thread contention even
        // though the calling code is correct (a bare, unloaded process never sees this). A
        // few short retries absorb that transient contention without masking a real failure.
        var clientStatus: OSStatus = noErr
        for attempt in 0..<12 {
            clientStatus = MIDIClientCreateWithBlock(name as CFString, &client) { _ in }
            if clientStatus == noErr { break }
            usleep(useconds_t(30_000 * (attempt + 1)))
        }
        guard clientStatus == noErr else {
            throw NSError(domain: "TestMIDIVirtualSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "MIDIClientCreateWithBlock failed (\(clientStatus))"])
        }

        var sourceStatus: OSStatus = noErr
        for attempt in 0..<12 {
            sourceStatus = MIDISourceCreate(client, name as CFString, &source)
            if sourceStatus == noErr { break }
            usleep(useconds_t(30_000 * (attempt + 1)))
        }
        guard sourceStatus == noErr else {
            MIDIClientDispose(client)
            throw NSError(domain: "TestMIDIVirtualSource", code: 2, userInfo: [NSLocalizedDescriptionKey: "MIDISourceCreate failed (\(sourceStatus))"])
        }
    }

    deinit {
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
    }

    /// Injects a single MIDI message as though it arrived from this source.
    func send(_ bytes: [UInt8]) {
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        _ = bytes.withUnsafeBufferPointer { ptr in
            MIDIPacketListAdd(&packetList, 1024, packet, 0, ptr.count, ptr.baseAddress!)
        }
        _ = MIDIReceived(source, &packetList)
    }
}

private nonisolated func hasPhysicalMIDIDevice() -> Bool {
    MIDIGetNumberOfDevices() > 0
}

// MARK: - Test suite

// Serialized top-to-bottom: CoreMIDI client/virtual-source creation is not reliably
// concurrency-safe under this test host — parallel creation across suites intermittently
// fails with a spurious error, so every nested suite here runs one test at a time.
@MainActor
@Suite("hs.midi tests", .serialized)
struct HSMIDITests {

    // MARK: - Module API structure

    @Suite("hs.midi module API structure tests")
    struct HSMIDIModuleStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")
            return harness
        }

        @Test("commandTypes is an object")
        func testCommandTypesIsObject() {
            #expect(makeHarness().evalTypeOf("hs.midi.commandTypes") == "object")
        }

        @Test("commandTypes.noteOn is a number")
        func testCommandTypesNoteOnIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.midi.commandTypes.noteOn") == "number")
        }

        @Test("devices is a function")
        func testDevicesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.midi.devices") == "function")
        }

        @Test("virtualSources is a function")
        func testVirtualSourcesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.midi.virtualSources") == "function")
        }

        @Test("deviceCallback is a function")
        func testDeviceCallbackIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.midi.deviceCallback") == "function")
        }

        @Test("deviceNamed is a function")
        func testDeviceNamedIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.midi.deviceNamed") == "function")
        }

        @Test("virtualSourceNamed is a function")
        func testVirtualSourceNamedIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.midi.virtualSourceNamed") == "function")
        }

        @Test("devices returns an array")
        func testDevicesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.midi.devices())")
            #expect(!harness.hasException)
        }

        @Test("virtualSources returns an array")
        func testVirtualSourcesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.midi.virtualSources())")
            #expect(!harness.hasException)
        }

        @Test("deviceNamed with an unknown name returns null")
        func testDeviceNamedUnknown() {
            let harness = makeHarness()
            harness.eval("var d = hs.midi.deviceNamed('definitely-not-a-real-device-\(UUID().uuidString)')")
            harness.expectTrue("d === null || d === undefined")
            #expect(!harness.hasException)
        }

        @Test("virtualSourceNamed with an unknown name returns null")
        func testVirtualSourceNamedUnknown() {
            let harness = makeHarness()
            harness.eval("var d = hs.midi.virtualSourceNamed('definitely-not-a-real-source-\(UUID().uuidString)')")
            harness.expectTrue("d === null || d === undefined")
            #expect(!harness.hasException)
        }

        @Test("deviceCallback accepts a function without throwing")
        func testDeviceCallbackAcceptsFunction() {
            let harness = makeHarness()
            harness.eval("hs.midi.deviceCallback(function(devices, virtualSources) {})")
            #expect(!harness.hasException)
        }

        @Test("deviceCallback accepts null to remove a previously-set callback")
        func testDeviceCallbackAcceptsNull() {
            let harness = makeHarness()
            harness.eval("hs.midi.deviceCallback(function(devices, virtualSources) {}); hs.midi.deviceCallback(null)")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Device object structure

    @Suite("hs.midi device API structure tests")
    struct HSMIDIDeviceStructureTests {

        private func makeHarness(virtualSourceName: String) -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")
            harness.eval("var d = hs.midi.virtualSourceNamed('\(virtualSourceName)')")
            return harness
        }

        @Test("virtualSourceNamed returns an object with every expected member")
        func testDeviceStructure() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestStructure-\(UUID().uuidString)")
            let harness = makeHarness(virtualSourceName: source.name)
            #expect(harness.evalTypeOf("d") == "object")
            #expect(harness.evalTypeOf("d.identifier") == "string")
            #expect(harness.evalTypeOf("d.name") == "string")
            #expect(harness.evalTypeOf("d.displayName") == "string")
            #expect(harness.evalTypeOf("d.manufacturer") == "string")
            #expect(harness.evalTypeOf("d.model") == "string")
            #expect(harness.evalTypeOf("d.isOnline") == "boolean")
            #expect(harness.evalTypeOf("d.isVirtual") == "boolean")
            #expect(harness.evalTypeOf("d.setCallback") == "function")
            #expect(harness.evalTypeOf("d.sendCommand") == "function")
            #expect(harness.evalTypeOf("d.sendSysex") == "function")
            #expect(harness.evalTypeOf("d.identityRequest") == "function")
            #expect(harness.evalTypeOf("d.destroy") == "function")
            #expect(!harness.hasException)
        }

        @Test("isVirtual is true for a virtual source device")
        func testIsVirtualTrue() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestVirtualFlag-\(UUID().uuidString)")
            let harness = makeHarness(virtualSourceName: source.name)
            #expect(harness.evalBool("d.isVirtual") == true)
        }

        @Test("name matches the virtual source's published name")
        func testNameMatches() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestName-\(UUID().uuidString)")
            let harness = makeHarness(virtualSourceName: source.name)
            #expect(harness.evalString("d.name") == source.name)
        }

        @Test("two devices have different identifiers")
        func testUniqueIdentifiers() throws {
            let sourceA = try TestMIDIVirtualSource(name: "HSMIDITestUniqueA-\(UUID().uuidString)")
            let sourceB = try TestMIDIVirtualSource(name: "HSMIDITestUniqueB-\(UUID().uuidString)")
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")
            harness.eval("""
                var a = hs.midi.virtualSourceNamed('\(sourceA.name)')
                var b = hs.midi.virtualSourceNamed('\(sourceB.name)')
            """)
            harness.expectTrue("a.identifier !== b.identifier")
        }

        @Test("setCallback returns self for chaining")
        func testSetCallbackChaining() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestChaining-\(UUID().uuidString)")
            let harness = makeHarness(virtualSourceName: source.name)
            harness.eval("var same = (d.setCallback(function() {}) === d)")
            harness.expectTrue("same")
            #expect(!harness.hasException)
            harness.eval("d.setCallback(null)")
        }

        @Test("sendCommand on a virtual source (no destination) returns false")
        func testSendCommandNoDestination() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestSendFail-\(UUID().uuidString)")
            let harness = makeHarness(virtualSourceName: source.name)
            #expect(harness.evalBool("d.sendCommand('noteOn', { note: 60, velocity: 100, channel: 0 })") == false)
            #expect(!harness.hasException)
        }

        @Test("sendCommand with an invalid commandType returns false")
        func testSendCommandInvalidType() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestSendInvalid-\(UUID().uuidString)")
            let harness = makeHarness(virtualSourceName: source.name)
            #expect(harness.evalBool("d.sendCommand('bogus', {})") == false)
            #expect(!harness.hasException)
        }

        @Test("sendSysex and identityRequest on a virtual source do not throw")
        func testSendSysexAndIdentityRequestNoThrow() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestSysexFail-\(UUID().uuidString)")
            let harness = makeHarness(virtualSourceName: source.name)
            harness.eval("d.sendSysex('F0 7E 7F 06 01 F7'); d.identityRequest()")
            #expect(!harness.hasException)
        }

        @Test("destroy() does not crash and can be called twice")
        func testDestroyIsIdempotent() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestDestroy-\(UUID().uuidString)")
            let harness = makeHarness(virtualSourceName: source.name)
            harness.eval("d.destroy(); d.destroy()")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Pure codec tests (no JSTestHarness — exercises the Swift-only byte codec directly)

    @Suite("hs.midi message codec tests")
    struct HSMIDICodecTests {

        @Test("noteOn encodes to the expected bytes and round-trips through the decoder")
        func testNoteOnRoundTrip() {
            var state = MIDIParserState()
            let bytes = encodeMIDICommand(type: "noteOn", metadata: ["note": 60, "velocity": 100, "channel": 2])
            #expect(bytes == [0x92, 60, 100])
            let decoded = parseMIDIBytes(bytes!, state: &state)
            #expect(decoded.count == 1)
            #expect(decoded[0].commandType == "noteOn")
            #expect(decoded[0].metadata["note"] as? Int == 60)
            #expect(decoded[0].metadata["velocity"] as? Int == 100)
            #expect(decoded[0].metadata["channel"] as? Int == 2)
        }

        @Test("noteOff round-trips")
        func testNoteOffRoundTrip() {
            var state = MIDIParserState()
            let bytes = encodeMIDICommand(type: "noteOff", metadata: ["note": 40, "velocity": 0, "channel": 0])
            let decoded = parseMIDIBytes(bytes!, state: &state)
            #expect(decoded.first?.commandType == "noteOff")
            #expect(decoded.first?.metadata["note"] as? Int == 40)
        }

        @Test("polyphonicKeyPressure round-trips")
        func testPolyphonicKeyPressureRoundTrip() {
            var state = MIDIParserState()
            let bytes = encodeMIDICommand(type: "polyphonicKeyPressure", metadata: ["note": 72, "pressure": 90, "channel": 1])
            let decoded = parseMIDIBytes(bytes!, state: &state)
            #expect(decoded.first?.commandType == "polyphonicKeyPressure")
            #expect(decoded.first?.metadata["pressure"] as? Int == 90)
        }

        @Test("controlChange round-trips")
        func testControlChangeRoundTrip() {
            var state = MIDIParserState()
            let bytes = encodeMIDICommand(type: "controlChange", metadata: ["controllerNumber": 7, "controllerValue": 127, "channel": 0])
            let decoded = parseMIDIBytes(bytes!, state: &state)
            #expect(decoded.first?.metadata["controllerNumber"] as? Int == 7)
            #expect(decoded.first?.metadata["controllerValue"] as? Int == 127)
        }

        @Test("programChange round-trips")
        func testProgramChangeRoundTrip() {
            var state = MIDIParserState()
            let bytes = encodeMIDICommand(type: "programChange", metadata: ["programNumber": 5, "channel": 0])
            let decoded = parseMIDIBytes(bytes!, state: &state)
            #expect(decoded.first?.metadata["programNumber"] as? Int == 5)
        }

        @Test("channelPressure round-trips")
        func testChannelPressureRoundTrip() {
            var state = MIDIParserState()
            let bytes = encodeMIDICommand(type: "channelPressure", metadata: ["pressure": 64, "channel": 0])
            let decoded = parseMIDIBytes(bytes!, state: &state)
            #expect(decoded.first?.metadata["pressure"] as? Int == 64)
        }

        @Test("pitchWheelChange round-trips with center value")
        func testPitchWheelChangeRoundTrip() {
            var state = MIDIParserState()
            let bytes = encodeMIDICommand(type: "pitchWheelChange", metadata: ["pitchChange": 8192, "channel": 0])
            let decoded = parseMIDIBytes(bytes!, state: &state)
            #expect(decoded.first?.commandType == "pitchWheelChange")
            #expect(decoded.first?.metadata["pitchChange"] as? Int == 8192)
        }

        @Test("encodeMIDICommand returns nil for out-of-range values")
        func testEncodeRejectsOutOfRange() {
            #expect(encodeMIDICommand(type: "noteOn", metadata: ["note": 200, "velocity": 100, "channel": 0]) == nil)
            #expect(encodeMIDICommand(type: "pitchWheelChange", metadata: ["pitchChange": 99999, "channel": 0]) == nil)
        }

        @Test("encodeMIDICommand returns nil for missing required fields or an unknown command type")
        func testEncodeRejectsInvalidInput() {
            #expect(encodeMIDICommand(type: "noteOn", metadata: ["note": 60]) == nil)
            #expect(encodeMIDICommand(type: "bogusCommand", metadata: [:]) == nil)
        }

        @Test("running status lets consecutive messages omit the repeated status byte")
        func testRunningStatus() {
            var state = MIDIParserState()
            let bytes: [UInt8] = [0x90, 60, 100, 61, 101]
            let decoded = parseMIDIBytes(bytes, state: &state)
            #expect(decoded.count == 2)
            #expect(decoded[0].metadata["note"] as? Int == 60)
            #expect(decoded[1].metadata["note"] as? Int == 61)
            #expect(decoded[1].commandType == "noteOn")
        }

        @Test("a sysex message spanning two calls accumulates correctly")
        func testSysexAcrossCalls() {
            var state = MIDIParserState()
            let firstResult = parseMIDIBytes([0xF0, 0x7E, 0x7F], state: &state)
            #expect(firstResult.isEmpty)
            let secondResult = parseMIDIBytes([0x06, 0x01, 0xF7], state: &state)
            #expect(secondResult.count == 1)
            #expect(secondResult[0].commandType == "systemExclusive")
            #expect(secondResult[0].metadata["data"] as? String == "F0 7E 7F 06 01 F7")
        }

        @Test("real-time bytes do not disturb an in-progress sysex")
        func testRealTimeDuringSysex() {
            var state = MIDIParserState()
            let decoded = parseMIDIBytes([0xF0, 0x7E, 0xF8, 0x7F, 0x06, 0x01, 0xF7], state: &state)
            #expect(decoded.count == 2)
            #expect(decoded[0].commandType == "systemRealTime")
            #expect(decoded[1].commandType == "systemExclusive")
            #expect(decoded[1].metadata["data"] as? String == "F0 7E 7F 06 01 F7")
        }

        @Test("hexStringToBytes parses whitespace-separated and compact hex")
        func testHexStringToBytes() {
            #expect(hexStringToBytes("F0 7E 7F 06 01 F7") == [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])
            #expect(hexStringToBytes("f07e7f0601f7") == [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])
        }

        @Test("hexStringToBytes returns nil for malformed input")
        func testHexStringToBytesMalformed() {
            #expect(hexStringToBytes("F0 7E 7") == nil)
            #expect(hexStringToBytes("ZZ") == nil)
            #expect(hexStringToBytes("") == nil)
        }

        @Test("commandTypes table has an entry for every command type the decoder can produce")
        func testCommandTypesTableCompleteness() {
            let expectedKeys: Set<String> = [
                "noteOff", "noteOn", "polyphonicKeyPressure", "controlChange", "programChange",
                "channelPressure", "pitchWheelChange", "systemExclusive", "systemCommon", "systemRealTime"
            ]
            #expect(Set(midiCommandTypeNumbers.keys) == expectedKeys)
        }
    }

    // MARK: - Hardware-free CoreMIDI loopback (via a test-created virtual source)

    @Suite("hs.midi virtual source loopback tests", .serialized)
    struct HSMIDIVirtualSourceLoopbackTests {

        @Test("a virtual source created by the test appears in virtualSources()")
        func testVirtualSourceAppearsInList() throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestLoopbackList-\(UUID().uuidString)")
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")
            harness.eval("var names = hs.midi.virtualSources()")
            harness.expectTrue("names.includes('\(source.name)')")
        }

        @Test("receiving a noteOn message fires the callback with decoded fields")
        func testReceiveNoteOn() async throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestReceiveNoteOn-\(UUID().uuidString)")
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")

            var received: [String: Any]?
            harness.registerCallback("onMessage") { (result: [String: Any]) in received = result }

            harness.eval("""
                var d = hs.midi.virtualSourceNamed('\(source.name)')
                d.setCallback((device, deviceName, commandType, description, metadata) => {
                    onMessage({ commandType: commandType, note: metadata.note, velocity: metadata.velocity })
                })
            """)
            #expect(!harness.hasException)

            source.send([0x90, 60, 100])

            let fired = await harness.waitForAsync(timeout: 3.0) { received != nil }
            #expect(fired, "the noteOn callback should have fired")
            #expect(received?["commandType"] as? String == "noteOn")
            #expect(received?["note"] as? Int == 60)
            #expect(received?["velocity"] as? Int == 100)

            harness.eval("d.destroy()")
        }

        @Test("receiving a sysex message fires the callback with the raw hex data")
        func testReceiveSysex() async throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestReceiveSysex-\(UUID().uuidString)")
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")

            var received: [String: Any]?
            harness.registerCallback("onMessage") { (result: [String: Any]) in received = result }

            harness.eval("""
                var d = hs.midi.virtualSourceNamed('\(source.name)')
                d.setCallback((device, deviceName, commandType, description, metadata) => {
                    onMessage({ commandType: commandType, data: metadata.data })
                })
            """)
            #expect(!harness.hasException)

            source.send([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])

            let fired = await harness.waitForAsync(timeout: 3.0) { received != nil }
            #expect(fired, "the sysex callback should have fired")
            #expect(received?["commandType"] as? String == "systemExclusive")
            #expect(received?["data"] as? String == "F0 7E 7F 06 01 F7")

            harness.eval("d.destroy()")
        }

        @Test("setCallback(null) stops further messages from being delivered")
        func testSetCallbackNullStopsDelivery() async throws {
            let source = try TestMIDIVirtualSource(name: "HSMIDITestStopDelivery-\(UUID().uuidString)")
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")

            var receiveCount = 0
            harness.registerCallback("onMessage") { (_: [String: Any]) in receiveCount += 1 }

            harness.eval("""
                var d = hs.midi.virtualSourceNamed('\(source.name)')
                d.setCallback((device, deviceName, commandType, description, metadata) => {
                    onMessage({ commandType: commandType })
                })
            """)

            source.send([0x90, 60, 100])
            let firstFired = await harness.waitForAsync(timeout: 3.0) { receiveCount > 0 }
            #expect(firstFired)

            harness.eval("d.setCallback(null)")
            source.send([0x90, 61, 101])
            // Give any (incorrectly still-connected) delivery a moment to arrive before asserting it didn't.
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(receiveCount == 1)

            harness.eval("d.destroy()")
        }
    }

    // MARK: - Physical device tests (require a real, connected MIDI device)

    @Suite("hs.midi physical device tests",
           .disabled(if: !hasPhysicalMIDIDevice(), "No physical MIDI device connected"))
    struct HSMIDIPhysicalDeviceTests {

        // sendCommand/sendSysex/identityRequest all require a real destination endpoint.
        // Unlike the receive path (which a test-created virtual source can stand in for),
        // CoreMIDI has no way to synthesize a "device" with a destination endpoint outside
        // of real hardware, so this suite can only run when hardware happens to be attached.

        @Test("sendCommand does not throw for a connected physical device")
        func testSendCommandDoesNotThrow() {
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")
            harness.eval("""
                var d = hs.midi.deviceNamed(hs.midi.devices()[0])
                d.sendCommand('noteOn', { note: 60, velocity: 100, channel: 0 })
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Memory leak test

    @Test("active HSMIDIDevice is released after shutdown")
    func testDeviceDoesNotLeakAfterReload() throws {
        let source = try TestMIDIVirtualSource(name: "HSMIDITestLeak-\(UUID().uuidString)")
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")

            harness.eval("""
                var d = hs.midi.virtualSourceNamed('\(source.name)')
                d.setCallback(function(device, deviceName, commandType, description, metadata) {})
            """)

            if let swift = harness.evalValue("d")?.toObjectOf(HSMIDIDevice.self) as? HSMIDIDevice {
                tracker.track(swift)
            }

            harness.eval("d = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
