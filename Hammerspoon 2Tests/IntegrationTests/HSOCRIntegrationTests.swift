//
//  HSOCRIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
@testable import Hammerspoon_2

// MARK: - Helpers

/// Render `text` into a PNG at a temporary path and return that path.
/// Uses large bold text on a black background so Vision has an easy time.
private func makePNG(text: String, fontSize: CGFloat = 72) throws -> String {
    let scale: CGFloat = 2
    let padding: CGFloat = 20
    let scaledFont = NSFont.boldSystemFont(ofSize: fontSize * scale)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: scaledFont,
        .foregroundColor: NSColor.white
    ]
    let attrStr = NSAttributedString(string: text, attributes: attrs)
    let textSize = attrStr.size()
    let canvasSize = NSSize(
        width: ceil(textSize.width + padding * 2 * scale),
        height: ceil(textSize.height + padding * 2 * scale)
    )

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx

    NSColor.black.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    attrStr.draw(at: NSPoint(x: padding * scale, y: padding * scale))

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TestHelpers", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not render PNG"])
    }

    let tmpPath = NSTemporaryDirectory() + "hs_ocr_test_\(UUID().uuidString).png"
    try pngData.write(to: URL(fileURLWithPath: tmpPath))
    return tmpPath
}

// MARK: - API Structure Tests

@Suite("hs.ocr API structure tests")
struct HSOCRStructureTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSOCRModule.self, as: "ocr")
        return harness
    }

    @Test("hs.ocr module exists and is an object")
    func testModuleExists() {
        makeHarness().expectTrue("typeof hs.ocr === 'object'")
    }

    @Test("recognizeText is a function")
    func testRecognizeTextIsFunction() {
        makeHarness().expectTrue("typeof hs.ocr.recognizeText === 'function'")
    }

    @Test("supportedLanguages is a function")
    func testSupportedLanguagesIsFunction() {
        makeHarness().expectTrue("typeof hs.ocr.supportedLanguages === 'function'")
    }

    @Test("recognizeText returns a thenable Promise")
    func testRecognizeTextReturnsPromise() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ocr.recognizeText('/nonexistent.png').then === 'function'")
        #expect(harness.hasException == false)
    }

    @Test("supportedLanguages returns an array")
    func testSupportedLanguagesReturnsArray() {
        let harness = makeHarness()
        harness.expectTrue("Array.isArray(hs.ocr.supportedLanguages())")
        #expect(harness.hasException == false)
    }
}

// MARK: - supportedLanguages Tests

@Suite("hs.ocr supportedLanguages tests")
struct HSOCRSupportedLanguagesTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSOCRModule.self, as: "ocr")
        return harness
    }

    @Test("supportedLanguages returns a non-empty array")
    func testReturnsNonEmpty() {
        let harness = makeHarness()
        harness.expectTrue("hs.ocr.supportedLanguages().length > 0")
        #expect(harness.hasException == false)
    }

    @Test("supportedLanguages contains English (en-US)")
    func testContainsEnglish() {
        let harness = makeHarness()
        harness.expectTrue("hs.ocr.supportedLanguages().includes('en-US')")
        #expect(harness.hasException == false)
    }

    @Test("all entries in supportedLanguages are non-empty strings")
    func testAllNonEmptyStrings() {
        let harness = makeHarness()
        harness.expectTrue("""
            hs.ocr.supportedLanguages().every(function(lang) {
                return typeof lang === 'string' && lang.length >= 2
            })
        """)
        #expect(harness.hasException == false)
    }
}

// MARK: - recognizeText error handling

@Suite("hs.ocr recognizeText error handling")
struct HSOCRErrorHandlingTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSOCRModule.self, as: "ocr")
        return harness
    }

    @Test("recognizeText rejects for a non-existent file")
    @MainActor
    func testRejectsMissingFile() async throws {
        let harness = makeHarness()
        harness.eval("""
            var _ocrError = null
            hs.ocr.recognizeText('/nonexistent_hs_ocr_test_file.png')
                .then(function() { _ocrError = 'resolved_unexpectedly' })
                .catch(function(err) { _ocrError = err || 'caught' })
        """)
        let ok = await harness.waitForAsync(timeout: 5.0) {
            let val = harness.evalValue("_ocrError")
            return val != nil && !val!.isNull && !val!.isUndefined
        }
        try #require(ok, "promise should have rejected for a missing file")
        harness.expectFalse("_ocrError === 'resolved_unexpectedly'")
    }
}

// MARK: - recognizeText functional tests

// .serialized is required: concurrent Swift Testing runners share the same NSGraphicsContext
// stack when makePNG is called, which causes crashes without serialization.
@Suite("hs.ocr recognizeText functional tests", .serialized)
struct HSOCRFunctionalTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSOCRModule.self, as: "ocr")
        return harness
    }

    @Test("recognizeText resolves with a result object")
    @MainActor
    func testResolvesWithResult() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrResult = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrResult = r })
                .catch(function() { _ocrResult = 'error' })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let val = harness.evalValue("_ocrResult")
            return val != nil && !val!.isNull && !val!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectFalse("_ocrResult === 'error'")
    }

    @Test("result has typeName HSOCRResult")
    @MainActor
    func testResultTypeName() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrR2 = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrR2 = r })
                .catch(function() { _ocrR2 = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrR2")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectEqual("_ocrR2.typeName", "HSOCRResult")
    }

    @Test("result.text is a string")
    @MainActor
    func testResultTextIsString() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrR3 = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrR3 = r })
                .catch(function() { _ocrR3 = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrR3")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("typeof _ocrR3.text === 'string'")
    }

    @Test("result.observations is an array")
    @MainActor
    func testResultObservationsIsArray() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrR4 = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrR4 = r })
                .catch(function() { _ocrR4 = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrR4")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("Array.isArray(_ocrR4.observations)")
    }

    @Test("observations contain valid HSOCRObservation objects")
    @MainActor
    func testObservationShape() async throws {
        let imagePath = try makePNG(text: "Hello World")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrR5 = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrR5 = r })
                .catch(function() { _ocrR5 = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrR5")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("_ocrR5.observations.length > 0")
        harness.expectTrue("""
            (function() {
                var first = _ocrR5.observations[0]
                return typeof first.text === 'string'
                    && typeof first.confidence === 'number'
                    && typeof first.bounds === 'object'
                    && typeof first.bounds.x === 'number'
                    && typeof first.bounds.y === 'number'
                    && typeof first.bounds.width === 'number'
                    && typeof first.bounds.height === 'number'
            })()
        """)
    }

    @Test("observation typeName is HSOCRObservation")
    @MainActor
    func testObservationTypeName() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrR6 = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrR6 = r })
                .catch(function() { _ocrR6 = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrR6")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("_ocrR6.observations.length > 0")
        harness.expectEqual("_ocrR6.observations[0].typeName", "HSOCRObservation")
    }

    @Test("observation confidence is in 0..1 range")
    @MainActor
    func testObservationConfidenceRange() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrR7 = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrR7 = r })
                .catch(function() { _ocrR7 = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrR7")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("_ocrR7.observations.length > 0")
        harness.expectTrue("""
            _ocrR7.observations.every(function(o) {
                return o.confidence >= 0 && o.confidence <= 1
            })
        """)
    }

    @Test("observation bounds values are in 0..1 range")
    @MainActor
    func testObservationBoundsRange() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrR8 = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrR8 = r })
                .catch(function() { _ocrR8 = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrR8")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("_ocrR8.observations.length > 0")
        harness.expectTrue("""
            _ocrR8.observations.every(function(o) {
                var b = o.bounds
                return b.x >= 0 && b.x <= 1
                    && b.y >= 0 && b.y <= 1
                    && b.width > 0 && b.width <= 1
                    && b.height > 0 && b.height <= 1
            })
        """)
    }

    @Test("result.text equals observations joined by newlines")
    @MainActor
    func testResultTextMatchesObservations() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrR9 = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrR9 = r })
                .catch(function() { _ocrR9 = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrR9")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("""
            (function() {
                var joined = _ocrR9.observations.map(function(o) { return o.text }).join('\\n')
                return _ocrR9.text === joined
            })()
        """)
    }

    @Test("minimumConfidence 0.9999 does not increase observation count")
    @MainActor
    func testMinimumConfidenceFilter() async throws {
        let imagePath = try makePNG(text: "Hello World")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrUnfiltered = null
            var _ocrFiltered = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrUnfiltered = r.observations.length })
                .catch(function() { _ocrUnfiltered = -1 })
            hs.ocr.recognizeText('\(imagePath)', { minimumConfidence: 0.9999 })
                .then(function(r) { _ocrFiltered = r.observations.length })
                .catch(function() { _ocrFiltered = -1 })
        """)
        let ok = await harness.waitForAsync(timeout: 15.0) {
            let u = harness.evalValue("_ocrUnfiltered")
            let f = harness.evalValue("_ocrFiltered")
            return u != nil && !u!.isNull && !u!.isUndefined
                && f != nil && !f!.isNull && !f!.isUndefined
        }
        try #require(ok, "both recognizeText calls should resolve within 15 seconds")
        harness.expectTrue("_ocrUnfiltered >= 0 && _ocrFiltered >= 0")
        harness.expectTrue("_ocrFiltered <= _ocrUnfiltered")
    }

    @Test("result.text contains the text rendered into the image")
    @MainActor
    func testRecognizedTextMatchesRenderedText() async throws {
        // Use a simple, unambiguous uppercase word. Vision is highly accurate on
        // large bold white-on-black text, so an exact case-insensitive match is
        // a reliable correctness signal.
        let imagePath = try makePNG(text: "VISION")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrText = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrText = r.text })
                .catch(function() { _ocrText = '' })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrText")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("_ocrText.toLowerCase().includes('vision')")
    }

    @Test("each observation's text appears in result.text")
    @MainActor
    func testObservationTextsAppearInResultText() async throws {
        let imagePath = try makePNG(text: "HELLO")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrRt = null
            hs.ocr.recognizeText('\(imagePath)')
                .then(function(r) { _ocrRt = r })
                .catch(function() { _ocrRt = null })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrRt")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectTrue("_ocrRt.observations.length > 0")
        harness.expectTrue("""
            _ocrRt.observations.every(function(obs) {
                return _ocrRt.text.toLowerCase().includes(obs.text.toLowerCase())
            })
        """)
    }

    @Test("fast recognitionLevel resolves without throwing")
    @MainActor
    func testFastRecognitionLevel() async throws {
        let imagePath = try makePNG(text: "Hello")
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let harness = makeHarness()
        harness.eval("""
            var _ocrFast = null
            hs.ocr.recognizeText('\(imagePath)', { recognitionLevel: 'fast' })
                .then(function(r) { _ocrFast = r })
                .catch(function() { _ocrFast = 'error' })
        """)
        let ok = await harness.waitForAsync(timeout: 10.0) {
            let v = harness.evalValue("_ocrFast")
            return v != nil && !v!.isNull && !v!.isUndefined
        }
        try #require(ok, "recognizeText should resolve within 10 seconds")
        harness.expectFalse("_ocrFast === 'error'")
        #expect(harness.hasException == false)
    }
}
