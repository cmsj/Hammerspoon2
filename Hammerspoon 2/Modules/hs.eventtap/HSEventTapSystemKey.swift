//
//  HSEventTapSystemKey.swift
//  Hammerspoon 2
//

import AppKit
import CoreGraphics
import IOKit.hidsystem

/// Builds and decodes the system-defined (NX_SYSDEFINED) events that macOS uses for media,
/// volume, brightness and other special keys.
///
/// These events carry the key in `data1`: the NX_KEYTYPE_* code in the high 16 bits, then the
/// key state (0xA = down, 0xB = up) in bits 8-15 and a repeat flag in bit 0.
nonisolated enum SystemKey {
    /// NSEvent subtype for auxiliary control button (special key) events, NX_SUBTYPE_AUX_CONTROL_BUTTONS
    static let auxControlButtonsSubtype: Int16 = 8

    private static let keyDownState = 0xA
    private static let keyUpState = 0xB

    /// System key names (matching Hammerspoon 1's) mapped to their NX_KEYTYPE_* codes
    static let codes: [String: Int] = [
        "SOUND_UP": Int(NX_KEYTYPE_SOUND_UP),
        "SOUND_DOWN": Int(NX_KEYTYPE_SOUND_DOWN),
        "MUTE": Int(NX_KEYTYPE_MUTE),
        "BRIGHTNESS_UP": Int(NX_KEYTYPE_BRIGHTNESS_UP),
        "BRIGHTNESS_DOWN": Int(NX_KEYTYPE_BRIGHTNESS_DOWN),
        "CONTRAST_UP": Int(NX_KEYTYPE_CONTRAST_UP),
        "CONTRAST_DOWN": Int(NX_KEYTYPE_CONTRAST_DOWN),
        "POWER": Int(NX_POWER_KEY),
        "LAUNCH_PANEL": Int(NX_KEYTYPE_LAUNCH_PANEL),
        "VIDMIRROR": Int(NX_KEYTYPE_VIDMIRROR),
        "PLAY": Int(NX_KEYTYPE_PLAY),
        "EJECT": Int(NX_KEYTYPE_EJECT),
        "NEXT": Int(NX_KEYTYPE_NEXT),
        "PREVIOUS": Int(NX_KEYTYPE_PREVIOUS),
        "FAST": Int(NX_KEYTYPE_FAST),
        "REWIND": Int(NX_KEYTYPE_REWIND),
        "ILLUMINATION_UP": Int(NX_KEYTYPE_ILLUMINATION_UP),
        "ILLUMINATION_DOWN": Int(NX_KEYTYPE_ILLUMINATION_DOWN),
        "ILLUMINATION_TOGGLE": Int(NX_KEYTYPE_ILLUMINATION_TOGGLE),
        "CAPS_LOCK": Int(NX_KEYTYPE_CAPS_LOCK),
        "HELP": Int(NX_KEYTYPE_HELP),
        "NUM_LOCK": Int(NX_KEYTYPE_NUM_LOCK),
    ]

    private static let names: [Int: String] = Dictionary(uniqueKeysWithValues: codes.map { ($1, $0) })

    /// Looks up a system key code by name, ignoring case
    static func code(named name: String) -> Int? {
        codes[name.uppercased()]
    }

    /// Creates a system-defined key event, or nil if AppKit can't build one
    @MainActor
    static func makeEvent(code: Int, isDown: Bool) -> CGEvent? {
        let state = isDown ? keyDownState : keyUpState
        let nsEvent = NSEvent.otherEvent(with: .systemDefined,
                                         location: .zero,
                                         modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                         timestamp: 0,
                                         windowNumber: 0,
                                         context: nil,
                                         subtype: auxControlButtonsSubtype,
                                         data1: (code << 16) | (state << 8),
                                         data2: -1)
        return nsEvent?.cgEvent
    }

    /// Decodes a system-defined key event into its key name, code and state, or nil if the
    /// event isn't a special key event
    @MainActor
    static func decode(_ event: CGEvent) -> [String: Any]? {
        guard event.type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue),
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == auxControlButtonsSubtype else {
            return nil
        }
        let data1 = nsEvent.data1
        let code = (data1 & 0xFFFF0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        return [
            "key": names[code] ?? "unknown",
            "keyCode": code,
            "isDown": state == keyDownState,
            "isRepeat": (data1 & 0x1) != 0,
        ]
    }
}
