//
//  HSMIDIMessageCodec.swift
//  Hammerspoon 2
//

import Foundation

// Pure MIDI 1.0 byte-stream codec. No CoreMIDI types, no actor isolation —
// fully unit-testable without any hardware or OS API.

/// Per-device parsing state. MIDI sysex messages can arrive split across
/// multiple `MIDIPacket`s, and running status lets a device omit a repeated
/// status byte across consecutive same-type messages, so this must persist
/// across separate calls to `parseMIDIBytes`.
struct MIDIParserState {
    fileprivate var runningStatus: UInt8?
    fileprivate var pending: [UInt8] = []
    fileprivate var pendingLength: Int = 0
    fileprivate var inSysex = false
}

let midiCommandTypeNumbers: [String: Int] = [
    "noteOff": 1,
    "noteOn": 2,
    "polyphonicKeyPressure": 3,
    "controlChange": 4,
    "programChange": 5,
    "channelPressure": 6,
    "pitchWheelChange": 7,
    "systemExclusive": 8,
    "systemCommon": 9,
    "systemRealTime": 10
]

// MARK: - Decoding

private func channelVoiceDataLength(forHighNibble highNibble: UInt8) -> Int? {
    switch highNibble {
    case 0x80, 0x90, 0xA0, 0xB0, 0xE0: return 2
    case 0xC0, 0xD0: return 1
    default: return nil
    }
}

// F1: MTC quarter frame (1 data byte), F2: song position (2 data bytes),
// F3: song select (1 data byte), F6: tune request (no data bytes).
private func systemCommonTotalLength(forStatus status: UInt8) -> Int {
    switch status {
    case 0xF1: return 2
    case 0xF2: return 3
    case 0xF3: return 2
    default: return 1
    }
}

private func decodeChannelVoice(_ bytes: [UInt8]) -> (commandType: String, description: String, metadata: [String: Any]) {
    let status = bytes[0]
    let channel = Int(status & 0x0F)
    switch status & 0xF0 {
    case 0x80:
        return ("noteOff", "Note Off", ["note": Int(bytes[1]), "velocity": Int(bytes[2]), "channel": channel])
    case 0x90:
        return ("noteOn", "Note On", ["note": Int(bytes[1]), "velocity": Int(bytes[2]), "channel": channel])
    case 0xA0:
        return ("polyphonicKeyPressure", "Polyphonic Key Pressure", ["note": Int(bytes[1]), "pressure": Int(bytes[2]), "channel": channel])
    case 0xB0:
        return ("controlChange", "Control Change", ["controllerNumber": Int(bytes[1]), "controllerValue": Int(bytes[2]), "channel": channel])
    case 0xC0:
        return ("programChange", "Program Change", ["programNumber": Int(bytes[1]), "channel": channel])
    case 0xD0:
        return ("channelPressure", "Channel Pressure", ["pressure": Int(bytes[1]), "channel": channel])
    case 0xE0:
        let pitchChange = (Int(bytes[2]) << 7) | Int(bytes[1])
        return ("pitchWheelChange", "Pitch Wheel Change", ["pitchChange": pitchChange, "channel": channel])
    default:
        return ("unknown", "Unknown Channel Voice Message", ["channel": channel])
    }
}

private func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { unsafe String(format: "%02X", $0) }.joined(separator: " ")
}

private func decodeSysex(_ bytes: [UInt8]) -> (commandType: String, description: String, metadata: [String: Any]) {
    ("systemExclusive", "System Exclusive", ["data": hexString(bytes)])
}

private func decodeSystemCommon(_ bytes: [UInt8]) -> (commandType: String, description: String, metadata: [String: Any]) {
    ("systemCommon", "System Common", ["data": hexString(bytes)])
}

private func decodeSystemRealTime(_ byte: UInt8) -> (commandType: String, description: String, metadata: [String: Any]) {
    let description: String
    switch byte {
    case 0xF8: description = "Timing Clock"
    case 0xFA: description = "Start"
    case 0xFB: description = "Continue"
    case 0xFC: description = "Stop"
    case 0xFE: description = "Active Sensing"
    case 0xFF: description = "System Reset"
    default: description = "System Real Time"
    }
    return ("systemRealTime", description, ["status": Int(byte)])
}

/// Decodes a chunk of raw MIDI 1.0 bytes into zero or more discrete messages, updating
/// `state` with any partial message left over for the next call (a split sysex, or a
/// running-status byte carried forward for the next call's leading data byte).
func parseMIDIBytes(_ bytes: [UInt8], state: inout MIDIParserState) -> [(commandType: String, description: String, metadata: [String: Any])] {
    var results: [(commandType: String, description: String, metadata: [String: Any])] = []

    for byte in bytes {
        // Real-time bytes may appear at any point in the stream — including mid-sysex or
        // mid-message — and must not disturb whatever else is in progress.
        if byte >= 0xF8 {
            results.append(decodeSystemRealTime(byte))
            continue
        }

        if state.inSysex {
            state.pending.append(byte)
            if byte == 0xF7 {
                results.append(decodeSysex(state.pending))
                state.pending = []
                state.inSysex = false
            }
            continue
        }

        if byte == 0xF0 {
            state.pending = [byte]
            state.inSysex = true
            state.runningStatus = nil
            continue
        }

        if byte >= 0xF1 && byte <= 0xF6 {
            state.runningStatus = nil
            state.pending = [byte]
            state.pendingLength = systemCommonTotalLength(forStatus: byte)
            if state.pending.count == state.pendingLength {
                results.append(decodeSystemCommon(state.pending))
                state.pending = []
            }
            continue
        }

        if byte >= 0x80 {
            guard let dataLength = channelVoiceDataLength(forHighNibble: byte & 0xF0) else {
                state.pending = []
                state.runningStatus = nil
                continue
            }
            state.runningStatus = byte
            state.pending = [byte]
            state.pendingLength = dataLength + 1
            continue
        }

        // Data byte (< 0x80)
        if !state.pending.isEmpty {
            state.pending.append(byte)
            if state.pending.count == state.pendingLength {
                if state.pending[0] >= 0xF0 {
                    results.append(decodeSystemCommon(state.pending))
                } else {
                    results.append(decodeChannelVoice(state.pending))
                }
                state.pending = []
            }
        } else if let running = state.runningStatus, let dataLength = channelVoiceDataLength(forHighNibble: running & 0xF0) {
            state.pending = [running, byte]
            state.pendingLength = dataLength + 1
            if state.pending.count == state.pendingLength {
                results.append(decodeChannelVoice(state.pending))
                state.pending = []
            }
        }
        // else: a stray data byte with no status context to interpret it against — drop it.
    }

    return results
}

// MARK: - Encoding

private func midiInt(_ value: Any?) -> Int? {
    switch value {
    case let v as Int: return v
    case let v as Double: return Int(v)
    case let v as NSNumber: return v.intValue
    default: return nil
    }
}

private func midiByte(_ value: Any?, max: Int = 127) -> UInt8? {
    guard let intValue = midiInt(value), intValue >= 0, intValue <= max else { return nil }
    return UInt8(intValue)
}

private func midiChannelNibble(_ metadata: [String: Any]) -> UInt8 {
    midiByte(metadata["channel"], max: 15) ?? 0
}

/// Encodes a `sendCommand` invocation into raw MIDI 1.0 bytes, or `nil` if `type` is
/// unrecognised or `metadata` is missing/out-of-range required fields.
func encodeMIDICommand(type: String, metadata: [String: Any]) -> [UInt8]? {
    let channel = midiChannelNibble(metadata)
    switch type {
    case "noteOff":
        guard let note = midiByte(metadata["note"]), let velocity = midiByte(metadata["velocity"]) else { return nil }
        return [0x80 | channel, note, velocity]
    case "noteOn":
        guard let note = midiByte(metadata["note"]), let velocity = midiByte(metadata["velocity"]) else { return nil }
        return [0x90 | channel, note, velocity]
    case "polyphonicKeyPressure":
        guard let note = midiByte(metadata["note"]), let pressure = midiByte(metadata["pressure"]) else { return nil }
        return [0xA0 | channel, note, pressure]
    case "controlChange":
        guard let controllerNumber = midiByte(metadata["controllerNumber"]), let controllerValue = midiByte(metadata["controllerValue"]) else { return nil }
        return [0xB0 | channel, controllerNumber, controllerValue]
    case "programChange":
        guard let programNumber = midiByte(metadata["programNumber"]) else { return nil }
        return [0xC0 | channel, programNumber]
    case "channelPressure":
        guard let pressure = midiByte(metadata["pressure"]) else { return nil }
        return [0xD0 | channel, pressure]
    case "pitchWheelChange":
        // 14-bit value — midiByte() clamps to UInt8 (max 127), so resolve it directly here instead.
        guard let pitchChange = midiInt(metadata["pitchChange"]), pitchChange >= 0, pitchChange <= 16383 else { return nil }
        let lsb = UInt8(pitchChange & 0x7F)
        let msb = UInt8((pitchChange >> 7) & 0x7F)
        return [0xE0 | channel, lsb, msb]
    default:
        return nil
    }
}

/// Parses a hex string (whitespace ignored) into raw bytes, or `nil` if malformed.
func hexStringToBytes(_ hex: String) -> [UInt8]? {
    let cleaned = hex.filter { !$0.isWhitespace }
    guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(cleaned.count / 2)
    var index = cleaned.startIndex
    while index < cleaned.endIndex {
        let next = cleaned.index(index, offsetBy: 2)
        guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
        bytes.append(byte)
        index = next
    }
    return bytes
}
