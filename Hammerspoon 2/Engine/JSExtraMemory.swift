//
//  JSExtraMemory.swift
//  Hammerspoon 2
//

import AppKit
import JavaScriptCore

/// Tells JavaScriptCore about native memory held by objects bridged into JavaScript.
///
/// JSC decides when to collect garbage from how much it has allocated on its own heap. A bridged
/// object such as an `HSImage` is a wrapper of a few dozen bytes on that heap, however much it
/// holds natively, so a script that keeps creating and dropping images can grow by gigabytes
/// without JSC ever seeing a reason to collect. Reporting the native size counts it towards JSC's
/// next collection, the same way WebKit reports the memory behind DOM objects.
///
/// Reports only add: nothing is reported when an object is freed. That's all JSC needs, since a
/// report only brings the next collection forward. Report when an object takes on memory (it's
/// created, or its content is replaced with a new allocation), and keep estimates rough: what
/// matters is the order of magnitude.
///
/// `JSReportExtraMemoryCost` is exported by JavaScriptCore.framework but not declared in its
/// public headers, so it's looked up at runtime, and reporting is skipped if macOS removes it.
@_documentation(visibility: private)
enum JSExtraMemory {
    private typealias ReportFunction = @convention(c) (JSContextRef, Int) -> Void

    private static let reportFunction: ReportFunction? = {
        // RTLD_DEFAULT is a C macro, ((void *)-2), which Swift doesn't import
        let defaultHandle = unsafe UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = unsafe dlsym(defaultHandle, "JSReportExtraMemoryCost") else {
            AKWarning("JSReportExtraMemoryCost is unavailable; JavaScript garbage collection won't account for native memory")
            return nil
        }
        return unsafe unsafeBitCast(symbol, to: ReportFunction.self)
    }()

    /// Whether reports reach JSC. False only if JavaScriptCore no longer exports the function.
    static var isAvailable: Bool { unsafe reportFunction != nil }

    /// Report native memory taken on by a bridged object.
    /// - Parameters:
    ///   - byteCount: Roughly how many bytes the object holds outside the JS heap
    ///   - context: The context the object's wrapper lives in. Defaults to the context of the JS
    ///     call in progress, or else the engine's, for objects made outside a JS call (e.g. when a
    ///     promise resolves).
    static func report(_ byteCount: Int, in context: JSContext? = nil) {
        guard byteCount > 0,
              let reportFunction = unsafe reportFunction,
              let context = context ?? JSContext.current() ?? JSEngine.shared.context else { return }
        unsafe reportFunction(context.jsGlobalContextRef, byteCount)
    }

    /// Report the backing store of a window that's just been made, which holds 4 bytes per pixel.
    static func reportBackingStore(of window: NSWindow) {
        let scale = window.backingScaleFactor
        let size = window.frame.size
        report(byteCount(pixelsWide: size.width * scale, pixelsHigh: size.height * scale))
    }

    /// The bytes taken by an image of the given size at 4 bytes per pixel, or 0 for a size that
    /// isn't positive and finite.
    static func byteCount(pixelsWide: Double, pixelsHigh: Double) -> Int {
        let bytes = pixelsWide * pixelsHigh * 4
        guard bytes.isFinite, bytes > 0 else { return 0 }
        return Int(min(bytes, Double(Int32.max)))
    }
}
