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
