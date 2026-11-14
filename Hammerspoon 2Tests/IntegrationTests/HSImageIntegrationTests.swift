//
//  HSImageIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2
import HammerspoonSDK

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
}

private final class WeakBox {
    weak var value: HSImage?
    init(_ value: HSImage?) { self.value = value }
}
