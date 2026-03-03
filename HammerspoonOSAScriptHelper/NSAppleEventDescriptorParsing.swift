//
//  NSAppleEventDescriptorParsing.swift
//  HammerspoonOSAScriptHelper
//
//  Swift port of Hammerspoon v1's NSAppleEventDescriptor+Parsing category.
//  Converts an NSAppleEventDescriptor returned by OSAScript into a value
//  suitable for JSON serialisation.
//

import Foundation

// ---------------------------------------------------------------------------
// Four-char-code constants used below (avoiding a Carbon import).
// Each constant is the big-endian byte sequence of its four-character tag.
// ---------------------------------------------------------------------------
nonisolated private let kTypeUnicodeText:             DescType = 0x75747874  // 'utxt'
nonisolated private let kTypeUTF8Text:                DescType = 0x75746638  // 'utf8'
nonisolated private let kTypeTrue:                    DescType = 0x74727565  // 'true'
nonisolated private let kTypeFalse:                   DescType = 0x66616C73  // 'fals'
nonisolated private let kTypeBoolean:                 DescType = 0x626F6F6C  // 'bool'
nonisolated private let kTypeSInt16:                  DescType = 0x73686F72  // 'shor'
nonisolated private let kTypeSInt32:                  DescType = 0x6C6F6E67  // 'long'
nonisolated private let kTypeSInt64:                  DescType = 0x636F6D70  // 'comp'
nonisolated private let kTypeIEEE64BitFloatingPoint:  DescType = 0x646F7562  // 'doub'
nonisolated private let kTypeAEList:                  DescType = 0x6C697374  // 'list'
nonisolated private let kTypeAERecord:                DescType = 0x7265636F  // 'reco'
nonisolated private let kTypeNull:                    DescType = 0x6E756C6C  // 'null'
nonisolated private let kTypeType:                    DescType = 0x74797065  // 'type'
nonisolated private let kKeywordUsrf:                 AEKeyword = 0x75737266 // 'usrf'

extension NSAppleEventDescriptor {

    /// Recursively converts an `NSAppleEventDescriptor` into a value that
    /// `JSONSerialization` can handle: `String`, `Bool`, `NSNumber`, `[Any]`,
    /// `[String: Any]`, or `NSNull`.
    nonisolated func toJSONCompatibleObject() -> Any {
        switch descriptorType {

        // ── Strings ──────────────────────────────────────────────────────────
        case kTypeUnicodeText, kTypeUTF8Text:
            return stringValue ?? NSNull()

        // ── Booleans ─────────────────────────────────────────────────────────
        case kTypeTrue:
            return true
        case kTypeFalse:
            return false
        case kTypeBoolean:
            return booleanValue

        // ── Integers ─────────────────────────────────────────────────────────
        case kTypeSInt16:
            // Coerce to 32-bit; NSAppleEventDescriptor handles the widening.
            if let coerced = coerce(toDescriptorType: kTypeSInt32) {
                return NSNumber(value: coerced.int32Value)
            }
            return NSNumber(value: int32Value)

        case kTypeSInt32:
            return NSNumber(value: int32Value)

        case kTypeSInt64:
            // JSON has no native int64; use double (sufficient for most values).
            if let coerced = coerce(toDescriptorType: kTypeIEEE64BitFloatingPoint) {
                return NSNumber(value: coerced.doubleValue)
            }
            return stringValue.flatMap { Int64($0) }.map { NSNumber(value: $0) } ?? NSNull()

        // ── Floating-point ───────────────────────────────────────────────────
        case kTypeIEEE64BitFloatingPoint:
            return NSNumber(value: doubleValue)

        // ── List ─────────────────────────────────────────────────────────────
        case kTypeAEList:
            var result: [Any] = []
            let count = numberOfItems
            if count > 0 {
                for i in 1...count {
                    if let item = atIndex(i) {
                        result.append(item.toJSONCompatibleObject())
                    }
                }
            }
            return result

        // ── Record ───────────────────────────────────────────────────────────
        //
        // AERecords returned by OSA scripts store user-defined key/value pairs
        // under the 'usrf' keyword as an alternating key/value list:
        //   usrf[1] = keyDescriptor, usrf[2] = valueDescriptor, ...
        case kTypeAERecord:
            var dict: [String: Any] = [:]
            if let usrfDesc = forKeyword(kKeywordUsrf) {
                let count = usrfDesc.numberOfItems
                var i = 1
                while i + 1 <= count {
                    if let keyDesc   = usrfDesc.atIndex(i),
                       let key       = keyDesc.stringValue,
                       let valueDesc = usrfDesc.atIndex(i + 1) {
                        dict[key] = valueDesc.toJSONCompatibleObject()
                    }
                    i += 2
                }
            }
            return dict

        // ── Null / type codes ────────────────────────────────────────────────
        case kTypeNull, kTypeType:
            return NSNull()

        // ── Fallback: coerce to string ────────────────────────────────────────
        default:
            return stringValue ?? NSNull()
        }
    }
}
