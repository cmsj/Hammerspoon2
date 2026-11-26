//
//  HSImageIntegrationTests.swift
//  Hammerspoon 2Tests
//

import AppKit
import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("HSImage integration tests")
struct HSImageIntegrationTests {

    // MARK: - duplicate()

    @Test("duplicate() returns a separate image with the same size")
    func duplicateReturnsSeparateImage() {
        let harness = JSTestHarness()
        harness.eval("var original = HSImage.fromSymbol('star.fill'); var copy = original.duplicate()")

        harness.expectTrue("copy instanceof HSImage")
        harness.expectFalse("copy === original")
        harness.expectTrue("copy.size.w === original.size.w && copy.size.h === original.size.h")

        harness.eval("copy.size = new HSSize(64, 64)")
        harness.expectEqual("copy.size.w", 64.0)
        harness.expectFalse("original.size.w === 64")
    }

    // Regression test for #309: a selector starting with "copy" is in the Objective-C copy family,
    // so its return value carries an extra retain that JavaScriptCore never releases.
    @Test("Images returned by duplicate() are freed once JS drops them")
    func duplicateDoesNotLeak() {
        let harness = JSTestHarness()
        var weakCopies: [WeakBox] = []

        autoreleasepool {
            harness.eval("void (globalThis.copies = []); { const img = HSImage.fromSymbol('star.fill'); for (let i = 0; i < 10; i++) copies.push(img.duplicate()) }")
            for index in 0..<10 {
                let copy = harness.evalValue("copies[\(index)]")?.toObject() as? HSImage
                weakCopies.append(WeakBox(copy))
            }
        }
        // Checked while `copies` still holds them, since JSC may collect them as soon as it doesn't
        #expect(weakCopies.allSatisfy { $0.value != nil }, "Every copy should exist while JS holds it")

        autoreleasepool {
            harness.eval("void (globalThis.copies = null)")
        }
        harness.collectGarbage()
        let survivors = weakCopies.filter { $0.value != nil }.count
        #expect(survivors == 0, "\(survivors) of \(weakCopies.count) duplicated images were never freed")
    }

    // MARK: - croppedCopy()

    // Regression test for #445: croppedCopy() used NSImage's bottom-up coordinates for y
    @Test("croppedCopy() measures y from the top of the image")
    func croppedCopyMeasuresFromTop() throws {
        let harness = JSTestHarness()
        harness.context.setObject(HSImage(image: Self.twoToneImage()), forKeyedSubscript: "twoTone" as NSString)

        let top = try #require(harness.evalValue("twoTone.croppedCopy(new HSRect(0, 0, 10, 5))")?.toObject() as? HSImage)
        let bottom = try #require(harness.evalValue("twoTone.croppedCopy(new HSRect(0, 5, 10, 5))")?.toObject() as? HSImage)

        #expect(top.size.h == 5)
        #expect(Self.centerColor(of: top) == .red)
        #expect(Self.centerColor(of: bottom) == .blue)
    }

    @Test("croppedCopy() returns null for a rect outside the image")
    func croppedCopyOutsideBoundsReturnsNull() {
        let harness = JSTestHarness()
        harness.context.setObject(HSImage(image: Self.twoToneImage()), forKeyedSubscript: "twoTone" as NSString)

        harness.expectTrue("twoTone.croppedCopy(new HSRect(0, 6, 10, 5)) === null")
    }

    // MARK: - toDataURL() / toUint8Array()

    @Test("toDataURL() defaults to a PNG data URL", arguments: ["twoTone.toDataURL()", "twoTone.toDataURL('png')", "twoTone.toDataURL('PNG')"])
    func toDataURLDefaultsToPNG(expression: String) throws {
        let harness = Self.harnessWithTwoTone()

        let url = try #require(harness.evalValue(expression)?.toString())
        let bytes = try Self.decodeDataURL(url, mimeType: "image/png")
        #expect(Array(bytes.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test("toDataURL() encodes each supported type with its MIME type and magic bytes", arguments: [
        ("jpeg", "image/jpeg", [0xFF, 0xD8, 0xFF]),
        ("JPG", "image/jpeg", [0xFF, 0xD8, 0xFF]),
        ("tiff", "image/tiff", [0x4D, 0x4D]),
        ("bmp", "image/bmp", [0x42, 0x4D]),
        ("gif", "image/gif", [0x47, 0x49, 0x46, 0x38]),
    ] as [(String, String, [UInt8])])
    func toDataURLEncodesType(type: String, mimeType: String, magic: [UInt8]) throws {
        let harness = Self.harnessWithTwoTone()

        let url = try #require(harness.evalValue("twoTone.toDataURL('\(type)')")?.toString())
        let bytes = try Self.decodeDataURL(url, mimeType: mimeType)
        // TIFF may be big- or little-endian, so accept either byte order mark
        if mimeType == "image/tiff" {
            #expect([[0x4D, 0x4D], [0x49, 0x49]].contains(Array(bytes.prefix(2))))
        } else {
            #expect(Array(bytes.prefix(magic.count)) == magic)
        }
    }

    @Test("toUint8Array() returns the same bytes as the data URL")
    func toUint8ArrayMatchesDataURL() throws {
        let harness = Self.harnessWithTwoTone()

        harness.expectTrue("twoTone.toUint8Array() instanceof Uint8Array")
        harness.expectTrue("twoTone.toUint8Array('jpeg') instanceof Uint8Array")

        for type in ["png", "jpeg"] {
            let url = try #require(harness.evalValue("twoTone.toDataURL('\(type)')")?.toString())
            let fromURL = try Self.decodeDataURL(url, mimeType: "image/\(type)")
            let array = try #require(harness.evalValue("twoTone.toUint8Array('\(type)')"))
            #expect(array.typedArrayBytes == Array(fromURL))
        }

        let defaultBytes = try #require(harness.evalValue("twoTone.toUint8Array()")?.typedArrayBytes)
        #expect(Array(defaultBytes.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test("toDataURL() and toUint8Array() return null for an unknown type")
    func unknownTypeReturnsNull() {
        let harness = Self.harnessWithTwoTone()

        harness.expectTrue("twoTone.toDataURL('webp') === null")
        harness.expectTrue("twoTone.toUint8Array('webp') === null")
        harness.expectTrue("twoTone.toDataURL('') === null")
    }

    @Test("Encoded bytes decode back to an image of the same pixel size", arguments: ["png", "jpeg", "tiff", "bmp", "gif"])
    func encodedBytesRoundTrip(type: String) throws {
        let harness = Self.harnessWithTwoTone()
        let tiff = try #require(Self.twoToneImage().tiffRepresentation)
        let original = try #require(NSBitmapImageRep(data: tiff))

        let bytes = try #require(harness.evalValue("twoTone.toUint8Array('\(type)')")?.typedArrayBytes)
        let decoded = try #require(NSImage(data: Data(bytes)))
        let rep = try #require(decoded.representations.first)

        #expect(rep.pixelsWide == original.pixelsWide)
        #expect(rep.pixelsHigh == original.pixelsHigh)
    }

    private static func harnessWithTwoTone() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.context.setObject(HSImage(image: twoToneImage()), forKeyedSubscript: "twoTone" as NSString)
        return harness
    }

    /// Check a data URL's prefix and return its decoded payload
    private static func decodeDataURL(_ url: String, mimeType: String) throws -> Data {
        let prefix = "data:\(mimeType);base64,"
        try #require(url.hasPrefix(prefix), "Expected \(url.prefix(40)) to start with \(prefix)")
        return try #require(Data(base64Encoded: String(url.dropFirst(prefix.count))))
    }

    /// A 10x10 image whose top half is red and bottom half is blue
    private static func twoToneImage() -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { _ in
            NSColor.blue.setFill()
            NSRect(x: 0, y: 0, width: 10, height: 5).fill()
            NSColor.red.setFill()
            NSRect(x: 0, y: 5, width: 10, height: 5).fill()
            return true
        }
    }

    private enum Tone { case red, blue, other }

    private static func centerColor(of image: HSImage) -> Tone {
        guard let cgImage = image.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .other }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
            .usingColorSpace(.sRGB) else { return .other }
        if color.redComponent > 0.9 && color.blueComponent < 0.1 { return .red }
        if color.blueComponent > 0.9 && color.redComponent < 0.1 { return .blue }
        return .other
    }
}

private final class WeakBox {
    weak var value: HSImage?
    init(_ value: HSImage?) { self.value = value }
}
