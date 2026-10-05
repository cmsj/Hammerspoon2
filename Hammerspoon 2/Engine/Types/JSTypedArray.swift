//
//  JSTypedArray.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// Bridging between Swift byte buffers and JavaScript typed arrays.
//
// JSExport has no automatic bridging for binary data, so these helpers use the
// JavaScriptCore C API directly. Type checks are done natively (JSValueGetTypedArrayType)
// rather than via JS globals like `instanceof Uint8Array`, which user code could replace.

extension JSContext {
    /// Create a new `Uint8Array` in this context holding a copy of `bytes`.
    ///
    /// - Returns: The `Uint8Array`, or `nil` if JavaScriptCore could not allocate it.
    func makeUint8Array<Bytes: Collection>(_ bytes: Bytes) -> JSValue? where Bytes.Element == UInt8 {
        let count = bytes.count
        // malloc(0) may legitimately return NULL, so always allocate at least one byte.
        guard let buffer = unsafe malloc(max(count, 1)) else { return nil }
        let typed = unsafe buffer.bindMemory(to: UInt8.self, capacity: max(count, 1))
        for (i, byte) in bytes.enumerated() {
            unsafe typed[i] = byte
        }

        var exception: JSValueRef?
        // The typed array takes ownership of `buffer` and frees it when it is garbage collected.
        guard let object = unsafe JSObjectMakeTypedArrayWithBytesNoCopy(
            jsGlobalContextRef,
            kJSTypedArrayTypeUint8Array,
            buffer,
            count,
            { bytes, _ in unsafe free(bytes) },
            nil,
            &exception
        ), unsafe exception == nil else {
            unsafe free(buffer)
            return nil
        }
        return unsafe JSValue(jsValueRef: object, in: self)
    }
}

extension JSValue {
    /// If this value is a typed array (e.g. `Uint8Array`) or an `ArrayBuffer`, return a copy of
    /// the bytes it covers. Returns `nil` for any other value (including `DataView`).
    var typedArrayBytes: [UInt8]? {
        let ctx = unsafe context.jsGlobalContextRef
        let ref = unsafe jsValueRef
        var exception: JSValueRef?

        let type = unsafe JSValueGetTypedArrayType(ctx, ref, &exception)
        guard unsafe exception == nil, type != kJSTypedArrayTypeNone,
              let object = unsafe JSValueToObject(ctx, ref, &exception) else {
            return nil
        }

        let base: UnsafeMutableRawPointer?
        let offset: Int
        let length: Int
        if type == kJSTypedArrayTypeArrayBuffer {
            unsafe base = unsafe JSObjectGetArrayBufferBytesPtr(ctx, object, &exception)
            offset = 0
            length = unsafe JSObjectGetArrayBufferByteLength(ctx, object, &exception)
        } else {
            // JSObjectGetTypedArrayBytesPtr returns the start of the *underlying buffer*, so
            // the view's byte offset must be applied to honour views like `buf.subarray(2)`.
            unsafe base = unsafe JSObjectGetTypedArrayBytesPtr(ctx, object, &exception)
            offset = unsafe JSObjectGetTypedArrayByteOffset(ctx, object, &exception)
            length = unsafe JSObjectGetTypedArrayByteLength(ctx, object, &exception)
        }
        guard unsafe exception == nil else { return nil }
        guard length > 0 else { return [] }
        guard let base = unsafe base else { return nil }

        let start = unsafe base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
        return unsafe Array(UnsafeBufferPointer(start: start, count: length))
    }
}
