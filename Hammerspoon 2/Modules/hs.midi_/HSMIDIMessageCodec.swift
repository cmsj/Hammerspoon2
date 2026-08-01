//
//  HSMIDIMessageCodec.swift
//  Hammerspoon 2
//

import Foundation
import CoreMIDI

// MIDI 1.0-over-UMP (Universal MIDI Packet) codec, built on CoreMIDI's MIDIEventList
// family (MIDIPacketList-based sending/receiving is deprecated in favor of this).
// MIDIEventListInit/Add/ForEachEvent are pure in-memory struct operations — no
// MIDIClientRef or daemon connection needed — so this is fully unit-testable without
// any hardware, by round-tripping through those functions directly.

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

// CoreMIDI's MIDISystemStatus enum covers both what hs.midi calls "systemCommon"
// (MTC/song position/song select/tune request) and "systemRealTime" (clock/start/stop/
// active sensing/reset) under one type — the split below preserves hs.midi's existing
// JS-facing distinction between the two.
private let systemCommonStatuses: Set<UInt32> = [0xF1, 0xF2, 0xF3, 0xF6]

private func systemStatusDescription(_ status: UInt32) -> String {
    switch status {
    case 0xF1: return "MIDI Time Code Quarter Frame"
    case 0xF2: return "Song Position Pointer"
    case 0xF3: return "Song Select"
    case 0xF6: return "Tune Request"
    case 0xF8: return "Timing Clock"
    case 0xFA: return "Start"
    case 0xFB: return "Continue"
    case 0xFC: return "Stop"
    case 0xFE: return "Active Sensing"
    case 0xFF: return "System Reset"
    default: return "System"
    }
}

private func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { unsafe String(format: "%02X", $0) }.joined(separator: " ")
}

/// A hard ceiling on `sysexAccumulator`'s growth. Real-world sysex (patch dumps, identity
/// replies, even bulk/firmware dumps) is essentially always well under this — at MIDI 1.0's
/// wire speed (31,250 bit/s), transferring 1 MiB takes minutes — so this is a generous safety
/// ceiling, not a realistic message size. Without it, a device that sends a `.start` chunk and
/// then an unbounded stream of `.continue` chunks without ever sending `.end` (malfunctioning
/// hardware, or a malicious/malformed source) would grow the accumulator without bound and
/// eventually exhaust process memory.
///
/// Not marked `private` — referenced directly by the regression test so it doesn't hardcode a
/// duplicate magic number to determine how many chunks are needed to exceed the cap.
let maxSysexAccumulatorBytes = 1 * 1024 * 1024

/// Decodes a single UMP message (as parsed by CoreMIDI's `MIDIEventListForEachEvent`)
/// into hs.midi's `(commandType, description, metadata)` shape.
///
/// `sysexAccumulator` persists per-device across calls: sysex arrives as a `.start` chunk,
/// zero or more `.continue` chunks, and a final `.end` chunk (or a single `.complete` chunk
/// for short messages) — this function returns `nil` for `.start`/`.continue` since they
/// aren't a complete message yet.
///
/// Returns `nil` for message types hs.midi doesn't expose at MIDI 1.0 protocol (channel
/// voice 2, data128, utility) — unreachable in practice since every port/source this module
/// creates negotiates `MIDIProtocolID._1_0`, but the switch needs an exhaustive default.
func decodeUniversalMessage(_ message: MIDIUniversalMessage, sysexAccumulator: inout [UInt8]?) -> (commandType: String, description: String, metadata: [String: Any])? {
    switch message.type {
    case .channelVoice1:
        let cv = message.channelVoice1
        let channel = Int(cv.channel)
        switch cv.status {
        case .noteOff:
            return ("noteOff", "Note Off", ["note": Int(cv.note.number), "velocity": Int(cv.note.velocity), "channel": channel])
        case .noteOn:
            return ("noteOn", "Note On", ["note": Int(cv.note.number), "velocity": Int(cv.note.velocity), "channel": channel])
        case .polyPressure:
            return ("polyphonicKeyPressure", "Polyphonic Key Pressure", ["note": Int(cv.polyPressure.noteNumber), "pressure": Int(cv.polyPressure.pressure), "channel": channel])
        case .controlChange:
            return ("controlChange", "Control Change", ["controllerNumber": Int(cv.controlChange.index), "controllerValue": Int(cv.controlChange.data), "channel": channel])
        case .programChange:
            return ("programChange", "Program Change", ["programNumber": Int(cv.program), "channel": channel])
        case .channelPressure:
            return ("channelPressure", "Channel Pressure", ["pressure": Int(cv.channelPressure), "channel": channel])
        case .pitchBend:
            return ("pitchWheelChange", "Pitch Wheel Change", ["pitchChange": Int(cv.pitchBend), "channel": channel])
        default:
            return ("unknown", "Unknown Channel Voice Message", ["channel": channel])
        }

    case .sysEx:
        let sysex = message.sysEx
        // `sysex.channel` is mislabeled in CoreMIDI's own header — it actually holds the
        // valid byte count (0-6) of `sysex.data`, not a MIDI channel. Confirmed empirically
        // by inspecting the raw decoded struct bytes against a hand-built UMP message.
        let byteCount = Int(sysex.channel)
        let chunk = withUnsafeBytes(of: sysex.data) { raw in unsafe Array(raw.prefix(byteCount)) }
        // The decoded `data` metadata re-adds the classic 0xF0/0xF7 framing bytes UMP
        // itself doesn't carry (status/start/end already say "this is sysex" structurally)
        // — preserves the exact JS-facing shape this module had before the UMP migration.
        switch sysex.status {
        case .complete:
            return ("systemExclusive", "System Exclusive", ["data": hexString([0xF0] + chunk + [0xF7])])
        case .start:
            sysexAccumulator = chunk
            return nil
        case .continue:
            guard var acc = sysexAccumulator else { return nil } // no Start seen, or already abandoned below
            guard acc.count + chunk.count <= maxSysexAccumulatorBytes else {
                AKWarning("hs.midi: sysex message exceeded \(maxSysexAccumulatorBytes) bytes without an End chunk — dropping")
                sysexAccumulator = nil
                return nil
            }
            acc.append(contentsOf: chunk)
            sysexAccumulator = acc
            return nil
        case .end:
            var bytes = sysexAccumulator ?? []
            bytes.append(contentsOf: chunk)
            sysexAccumulator = nil
            return ("systemExclusive", "System Exclusive", ["data": hexString([0xF0] + bytes + [0xF7])])
        default:
            return nil
        }

    case .system:
        let status = message.system.status.rawValue
        let commandType = systemCommonStatuses.contains(status) ? "systemCommon" : "systemRealTime"
        return (commandType, systemStatusDescription(status), ["status": Int(status)])

    case .invalid:
        // CoreMIDI's own UMP decoder (MIDIEventListForEachEvent) doesn't recognize every
        // System status byte on this SDK — Tune Request (0xF6) and the Real-Time family
        // (0xF8-0xFF, clock/start/stop/active-sensing/reset) all come back as `.invalid`,
        // confirmed empirically, even though MTC/song-position/song-select (0xF1-0xF3)
        // decode correctly via `.system`. When that happens, CoreMIDI leaves the original
        // raw word untouched in the `unknown` union arm (only a *successfully* classified
        // message repacks that memory into its own type-specific fields), so fall back to
        // extracting the status byte ourselves directly from it.
        let word0 = message.unknown.words.0
        guard (word0 >> 28) & 0xF == 0x1 else { return nil } // not a System-type word — genuinely unrecognized
        let status = (word0 >> 16) & 0xFF
        let commandType = systemCommonStatuses.contains(status) ? "systemCommon" : "systemRealTime"
        return (commandType, systemStatusDescription(status), ["status": Int(status)])

    default:
        return nil
    }
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

/// Encodes a `sendCommand` invocation into a single UMP word (MIDI 1.0 protocol), or
/// `nil` if `type` is unrecognised or `metadata` is missing/out-of-range required fields.
/// hs.midi never exposes UMP groups to JS, so `group` defaults to 0 (a single virtual
/// cable per device).
func encodeMIDICommand(type: String, metadata: [String: Any], group: UInt8 = 0) -> UInt32? {
    let channel = midiChannelNibble(metadata)
    switch type {
    case "noteOff":
        guard let note = midiByte(metadata["note"]), let velocity = midiByte(metadata["velocity"]) else { return nil }
        return MIDI1UPNoteOff(group, channel, note, velocity)
    case "noteOn":
        guard let note = midiByte(metadata["note"]), let velocity = midiByte(metadata["velocity"]) else { return nil }
        return MIDI1UPNoteOn(group, channel, note, velocity)
    case "polyphonicKeyPressure":
        guard let note = midiByte(metadata["note"]), let pressure = midiByte(metadata["pressure"]) else { return nil }
        return MIDI1UPPolyPressure(group, channel, note, pressure)
    case "controlChange":
        guard let controllerNumber = midiByte(metadata["controllerNumber"]), let controllerValue = midiByte(metadata["controllerValue"]) else { return nil }
        return MIDI1UPControlChange(group, channel, controllerNumber, controllerValue)
    case "programChange":
        guard let programNumber = midiByte(metadata["programNumber"]) else { return nil }
        return MIDI1UPProgramChange(group, channel, programNumber)
    case "channelPressure":
        guard let pressure = midiByte(metadata["pressure"]) else { return nil }
        return MIDI1UPChannelPressure(group, channel, pressure)
    case "pitchWheelChange":
        // 14-bit value — midiByte() clamps to UInt8 (max 127), so resolve it directly here instead.
        guard let pitchChange = midiInt(metadata["pitchChange"]), pitchChange >= 0, pitchChange <= 16383 else { return nil }
        let lsb = UInt8(pitchChange & 0x7F)
        let msb = UInt8((pitchChange >> 7) & 0x7F)
        return MIDI1UPPitchBend(group, channel, lsb, msb)
    default:
        return nil
    }
}

/// Chunks a sysex payload (without the 0xF0/0xF7 framing bytes — UMP encodes "this is
/// sysex" and start/continue/end structurally, not via literal framing bytes) into UMP
/// SysEx7 packets (`kMIDIMessageTypeSysEx`, 2 words each — no CF_INLINE helper exists for
/// this message type, so the word layout is hand-built here; verified by round-tripping
/// through `MIDIEventListForEachEvent`). Each packet holds up to 6 payload bytes, framed
/// as Complete (single packet), or Start/Continue/…/Continue/End (multiple packets).
func encodeSysexWords(_ bytes: [UInt8], group: UInt8 = 0) -> [[UInt32]] {
    guard !bytes.isEmpty else { return [] }
    let chunkSize = 6
    let chunks = stride(from: 0, to: bytes.count, by: chunkSize).map { start in
        Array(bytes[start..<min(start + chunkSize, bytes.count)])
    }
    return chunks.enumerated().map { index, chunk in
        let status: UInt32
        if chunks.count == 1 {
            status = 0x0 // Complete
        } else if index == 0 {
            status = 0x1 // Start
        } else if index == chunks.count - 1 {
            status = 0x3 // End
        } else {
            status = 0x2 // Continue
        }
        var padded = chunk
        while padded.count < chunkSize { padded.append(0) }
        let word0: UInt32 = (0x3 << 28) | (UInt32(group) << 24) | (status << 20) | (UInt32(chunk.count) << 16)
            | (UInt32(padded[0]) << 8) | UInt32(padded[1])
        let word1: UInt32 = (UInt32(padded[2]) << 24) | (UInt32(padded[3]) << 16) | (UInt32(padded[4]) << 8) | UInt32(padded[5])
        return [word0, word1]
    }
}

/// Strips the classic 0xF0/0xF7 sysex framing bytes if present. `sendSysex()` callers write
/// the familiar full F0...F7 sequence (matching MIDI convention and this module's previous
/// API), but UMP encodes "this is sysex" and start/continue/end structurally rather than via
/// literal framing bytes, so `encodeSysexWords` wants just the payload in between.
func stripSysexFraming(_ bytes: [UInt8]) -> [UInt8] {
    var result = bytes[...]
    if result.first == 0xF0 { result = result.dropFirst() }
    if result.last == 0xF7 { result = result.dropLast() }
    return Array(result)
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
