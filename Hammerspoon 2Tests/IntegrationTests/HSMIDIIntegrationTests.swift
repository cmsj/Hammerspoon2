//
//  HSMIDIIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import CoreMIDI
@testable import Hammerspoon_2

// MARK: - Helpers

/// Builds a `MIDIEventList` from `packets` (each inner array is one packet's UMP words) in a
/// freshly-allocated, generously-sized buffer, handing it to `body` for the duration of the
/// call. Shared by the virtual-source test helper (to inject received messages) and the pure
/// codec round-trip tests (to decode via CoreMIDI's own `MIDIEventListForEachEvent`).
private func withMIDIEventList<T>(_ packets: [[UInt32]], _ body: (UnsafeMutablePointer<MIDIEventList>) -> T) -> T {
    let totalWords = packets.reduce(0) { $0 + $1.count }
    let bufferSize = totalWords * 4 + packets.count * 16 + 64
    let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<MIDIEventList>.alignment)
    defer { rawBuffer.deallocate() }
    let eventListPtr = rawBuffer.bindMemory(to: MIDIEventList.self, capacity: 1)
    var packetPtr = MIDIEventListInit(eventListPtr, ._1_0)
    for packet in packets {
        packetPtr = packet.withUnsafeBufferPointer { wordsPtr in
            MIDIEventListAdd(eventListPtr, bufferSize, packetPtr, 0, wordsPtr.count, wordsPtr.baseAddress!)
        }
    }
    return body(eventListPtr)
}

/// Decodes every `MIDIUniversalMessage` out of an event list via CoreMIDI's own
/// `MIDIEventListForEachEvent` — used to validate this module's encoder against Apple's own
/// decoder. Pure in-memory operation, no `MIDIClientRef`/daemon connection needed.
private func decodedMessages(from packets: [[UInt32]]) -> [MIDIUniversalMessage] {
    withMIDIEventList(packets) { eventListPtr in
        var collected: [MIDIUniversalMessage] = []
        withUnsafeMutablePointer(to: &collected) { collectedPtr in
            MIDIEventListForEachEvent(eventListPtr, { context, _, message in
                guard let context else { return }
                context.assumingMemoryBound(to: [MIDIUniversalMessage].self).pointee.append(message)
            }, UnsafeMutableRawPointer(collectedPtr))
        }
        return collected
    }
}

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
            sourceStatus = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source)
            if sourceStatus == noErr { break }
            usleep(useconds_t(30_000 * (attempt + 1)))
        }
        guard sourceStatus == noErr else {
            MIDIClientDispose(client)
            throw NSError(domain: "TestMIDIVirtualSource", code: 2, userInfo: [NSLocalizedDescriptionKey: "MIDISourceCreateWithProtocol failed (\(sourceStatus))"])
        }
    }

    deinit {
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
    }

    /// Injects a channel voice message using this module's own production encoder
    /// (`encodeMIDICommand`) — this test exercises the real encoder on the "sender" side,
    /// not a hand-rolled duplicate of it.
    func send(commandType: String, metadata: [String: Any]) {
        guard let word = encodeMIDICommand(type: commandType, metadata: metadata) else {
            Issue.record("test injection: failed to encode \(commandType)")
            return
        }
        withMIDIEventList([[word]]) { _ = MIDIReceivedEventList(source, $0) }
    }

    /// Injects a sysex message (payload only, no 0xF0/0xF7 framing) using this module's own
    /// production encoder (`encodeSysexWords`).
    func sendSysex(_ payload: [UInt8]) {
        withMIDIEventList(encodeSysexWords(payload)) { _ = MIDIReceivedEventList(source, $0) }
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

    // MARK: - Pure codec tests (no JSTestHarness, no MIDIClientRef — pure in-memory UMP encode/decode)

    @Suite("hs.midi message codec tests")
    struct HSMIDICodecTests {

        private func decodedMessage(_ word: UInt32) -> MIDIUniversalMessage? {
            decodedMessages(from: [[word]]).first
        }

        /// Encodes `metadata` via the production `encodeMIDICommand`, decodes the resulting
        /// word via CoreMIDI's own `MIDIEventListForEachEvent`, then decodes that via this
        /// module's `decodeUniversalMessage` — a full encode → CoreMIDI → decode round trip.
        private func encodeDecodeRoundTrip(type: String, metadata: [String: Any]) throws -> (commandType: String, description: String, metadata: [String: Any]) {
            let word = try #require(encodeMIDICommand(type: type, metadata: metadata))
            let message = try #require(decodedMessage(word))
            var acc: [UInt8]?
            return try #require(decodeUniversalMessage(message, sysexAccumulator: &acc))
        }

        @Test("noteOn encodes to the expected UMP word and round-trips through CoreMIDI's own decoder")
        func testNoteOnRoundTrip() throws {
            let metadata: [String: Any] = ["note": 60, "velocity": 100, "channel": 2]
            #expect(encodeMIDICommand(type: "noteOn", metadata: metadata) == 0x20923C64)
            let decoded = try encodeDecodeRoundTrip(type: "noteOn", metadata: metadata)
            #expect(decoded.commandType == "noteOn")
            #expect(decoded.metadata["note"] as? Int == 60)
            #expect(decoded.metadata["velocity"] as? Int == 100)
            #expect(decoded.metadata["channel"] as? Int == 2)
        }

        @Test("noteOff round-trips")
        func testNoteOffRoundTrip() throws {
            let decoded = try encodeDecodeRoundTrip(type: "noteOff", metadata: ["note": 40, "velocity": 0, "channel": 0])
            #expect(decoded.commandType == "noteOff")
            #expect(decoded.metadata["note"] as? Int == 40)
        }

        @Test("polyphonicKeyPressure round-trips")
        func testPolyphonicKeyPressureRoundTrip() throws {
            let decoded = try encodeDecodeRoundTrip(type: "polyphonicKeyPressure", metadata: ["note": 72, "pressure": 90, "channel": 1])
            #expect(decoded.commandType == "polyphonicKeyPressure")
            #expect(decoded.metadata["pressure"] as? Int == 90)
        }

        @Test("controlChange round-trips")
        func testControlChangeRoundTrip() throws {
            let decoded = try encodeDecodeRoundTrip(type: "controlChange", metadata: ["controllerNumber": 7, "controllerValue": 127, "channel": 0])
            #expect(decoded.metadata["controllerNumber"] as? Int == 7)
            #expect(decoded.metadata["controllerValue"] as? Int == 127)
        }

        @Test("programChange round-trips")
        func testProgramChangeRoundTrip() throws {
            let decoded = try encodeDecodeRoundTrip(type: "programChange", metadata: ["programNumber": 5, "channel": 0])
            #expect(decoded.metadata["programNumber"] as? Int == 5)
        }

        @Test("channelPressure round-trips")
        func testChannelPressureRoundTrip() throws {
            let decoded = try encodeDecodeRoundTrip(type: "channelPressure", metadata: ["pressure": 64, "channel": 0])
            #expect(decoded.metadata["pressure"] as? Int == 64)
        }

        @Test("pitchWheelChange round-trips with center value")
        func testPitchWheelChangeRoundTrip() throws {
            let decoded = try encodeDecodeRoundTrip(type: "pitchWheelChange", metadata: ["pitchChange": 8192, "channel": 0])
            #expect(decoded.commandType == "pitchWheelChange")
            #expect(decoded.metadata["pitchChange"] as? Int == 8192)
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

        @Test("a short sysex payload round-trips as a single Complete packet")
        func testSysexCompleteRoundTrip() {
            let packets = encodeSysexWords([0x7E, 0x7F, 0x06, 0x01])
            #expect(packets.count == 1)
            let messages = decodedMessages(from: packets)
            #expect(messages.count == 1)
            var acc: [UInt8]?
            let decoded = decodeUniversalMessage(messages[0], sysexAccumulator: &acc)
            #expect(decoded?.commandType == "systemExclusive")
            #expect(decoded?.metadata["data"] as? String == "F0 7E 7F 06 01 F7")
            #expect(acc == nil)
        }

        @Test("a long sysex payload chunks into Start/Continue/End packets and reassembles")
        func testSysexMultiChunkRoundTrip() {
            let payload = (0..<20).map { UInt8($0) } // 20 bytes -> 4 chunks of 6/6/6/2
            let packets = encodeSysexWords(payload)
            #expect(packets.count == 4)
            let messages = decodedMessages(from: packets)
            #expect(messages.count == 4)

            var acc: [UInt8]?
            var lastDecoded: (commandType: String, description: String, metadata: [String: Any])?
            for message in messages {
                let result = decodeUniversalMessage(message, sysexAccumulator: &acc)
                if let result { lastDecoded = result }
            }
            let expectedHex = ([0xF0] + payload + [0xF7]).map { String(format: "%02X", $0) }.joined(separator: " ")
            #expect(lastDecoded?.commandType == "systemExclusive")
            #expect(lastDecoded?.metadata["data"] as? String == expectedHex)
            #expect(acc == nil, "accumulator should be cleared once the End chunk completes the message")
        }

        @Test("system real-time messages interleaved with an in-progress sysex don't disturb its accumulator")
        func testRealTimeDuringSysexAccumulation() {
            // Build the sysex chunks separately, but decode a system real-time message
            // (Timing Clock, 0xF8) between the Start and End chunks to confirm it doesn't
            // touch `sysexAccumulator`.
            let payload = (0..<10).map { UInt8($0) } // -> Start (6 bytes) + End (4 bytes)
            let sysexPackets = encodeSysexWords(payload)
            #expect(sysexPackets.count == 2)
            // UMP System word: byte0 = (type=0x1 << 4 | group), byte1 = status. Timing Clock
            // (0xF8) carries no data bytes.
            let realTimeWord: UInt32 = (0x1 << 28) | (0xF8 << 16)
            let messages = decodedMessages(from: [sysexPackets[0], [realTimeWord], sysexPackets[1]])
            #expect(messages.count == 3)

            var acc: [UInt8]?
            let startResult = decodeUniversalMessage(messages[0], sysexAccumulator: &acc)
            #expect(startResult == nil)
            #expect(acc?.count == 6)

            let realTimeResult = decodeUniversalMessage(messages[1], sysexAccumulator: &acc)
            #expect(realTimeResult?.commandType == "systemRealTime")
            #expect(acc?.count == 6, "the interleaved real-time message must not touch the sysex accumulator")

            let endResult = decodeUniversalMessage(messages[2], sysexAccumulator: &acc)
            #expect(endResult?.commandType == "systemExclusive")
            #expect(acc == nil)
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

        @Test("stripSysexFraming removes a leading 0xF0 and trailing 0xF7 if present")
        func testStripSysexFraming() {
            #expect(stripSysexFraming([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]) == [0x7E, 0x7F, 0x06, 0x01])
            #expect(stripSysexFraming([0x7E, 0x7F, 0x06, 0x01]) == [0x7E, 0x7F, 0x06, 0x01])
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

        // Regression test: MIDIClientCreateWithBlock's notify block is documented as running
        // on "an arbitrary thread" — exercising it for real (rather than just checking that
        // registering a callback doesn't throw) is what catches a MainActor.assumeIsolated
        // trap that a synchronous, same-thread-assuming test would miss entirely. Verified
        // the notification mechanism itself is fast and reliable in an unloaded process via a
        // standalone script; under the full ~1700-test suite it joins the same known class of
        // flakiness as HSFSPathWatcherTests/HSOCRTests (OS async-callback delivery becoming
        // unreliable under heavy full-suite resource contention, not a delivery failure this
        // module causes) — see the "Flakiness note" in this module's project memory.
        @Test("deviceCallback fires when a virtual source appears, without crashing")
        func testDeviceCallbackFiresOnSetupChange() async throws {
            let harness = JSTestHarness()
            harness.loadModule(HSMIDIModule.self, as: "midi")

            var fired = false
            harness.registerCallback("onSetupChange") { fired = true }
            harness.eval("hs.midi.deviceCallback(() => onSetupChange())")
            #expect(!harness.hasException)

            let source = try TestMIDIVirtualSource(name: "HSMIDITestSetupChange-\(UUID().uuidString)")

            let didFire = await harness.waitForAsync(timeout: 5.0) { fired }
            #expect(didFire, "deviceCallback should fire when a virtual source appears")

            harness.eval("hs.midi.deviceCallback(null)")
            withExtendedLifetime(source) {}
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

            source.send(commandType: "noteOn", metadata: ["note": 60, "velocity": 100, "channel": 0])

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

            source.sendSysex([0x7E, 0x7F, 0x06, 0x01])

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

            source.send(commandType: "noteOn", metadata: ["note": 60, "velocity": 100, "channel": 0])
            let firstFired = await harness.waitForAsync(timeout: 3.0) { receiveCount > 0 }
            #expect(firstFired)

            harness.eval("d.setCallback(null)")
            source.send(commandType: "noteOn", metadata: ["note": 61, "velocity": 101, "channel": 0])
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
