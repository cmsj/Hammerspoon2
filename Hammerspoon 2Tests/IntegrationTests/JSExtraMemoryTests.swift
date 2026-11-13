//
//  JSExtraMemoryTests.swift
//  Hammerspoon 2Tests
//

import Testing
import AppKit
import JavaScriptCore
@testable import Hammerspoon_2
import HammerspoonSDK

@Suite("Native memory accounting for JavaScript garbage collection")
struct JSExtraMemoryTests {

    @Test("JavaScriptCore still exports JSReportExtraMemoryCost")
    func reportFunctionIsAvailable() {
        #expect(JSExtraMemory.isAvailable)
    }

    // MARK: - Collection

    // Without the report, JSC sees only a few dozen bytes per image wrapper, and collects none of
    // them in a run this short.
    @Test("Large images JS drops are collected without an explicit garbage collection")
    func droppedLargeImagesAreCollected() throws {
        let path = try Self.writeBitmapImage(pixelsWide: 1024, pixelsHigh: 1024)
        defer { try? FileManager.default.removeItem(at: path) }

        let harness = JSTestHarness()
        var images: [WeakImage] = []
        for _ in 0..<200 {
            autoreleasepool {
                let image = harness.evalValue("HSImage.fromPath('\(path.path)')")?.toObject() as? HSImage
                images.append(WeakImage(image))
            }
            // Concurrent collections finish on the main run loop
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        #expect(images.allSatisfy { $0.wasCreated }, "Every image should have loaded")

        let collected = harness.waitFor(timeout: 5) {
            images.filter { $0.value == nil }.count >= images.count / 2
        }
        let survivors = images.filter { $0.value != nil }.count
        #expect(collected, "\(survivors) of \(images.count) dropped 4 MB images were still alive")
    }

    @Test("Memory pressure collection frees images JS has dropped")
    func memoryPressureCollectionFreesDroppedImages() {
        let harness = JSTestHarness()
        let collector = MemoryPressureCollector(context: harness.context)
        var images: [WeakImage] = []

        autoreleasepool {
            harness.eval("void (globalThis.images = []); for (let i = 0; i < 10; i++) images.push(HSImage.fromSymbol('star.fill'))")
            for index in 0..<10 {
                images.append(WeakImage(harness.evalValue("images[\(index)]")?.toObject() as? HSImage))
            }
        }
        #expect(images.allSatisfy { $0.value != nil }, "Every image should exist while JS holds it")

        autoreleasepool {
            harness.eval("void (globalThis.images = null)")
        }
        collector.collect()

        let survivors = images.filter { $0.value != nil }.count
        #expect(survivors == 0, "\(survivors) of \(images.count) dropped images survived the collection")
    }

    // MARK: - Image size estimates

    @Test("A bitmap image is counted at 4 bytes per pixel")
    func bitmapImageIsCountedInFull() throws {
        let path = try Self.writeBitmapImage(pixelsWide: 300, pixelsHigh: 200)
        defer { try? FileManager.default.removeItem(at: path) }
        let image = try #require(NSImage(contentsOf: path))
        #expect(HSImage.estimatedByteCount(of: image) == 300 * 200 * 4)
    }

    @Test("An app icon is counted at the size it draws, not its largest representation")
    func appIconIsCountedAtDrawnSize() {
        let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Calculator.app")
        let drawnBytes = Int(icon.size.width * 2) * Int(icon.size.height * 2) * 4
        #expect(HSImage.estimatedByteCount(of: icon) == drawnBytes)
    }

    @Test("A symbol, which has no pixel size, is counted at the size it draws")
    func symbolIsCountedAtDrawnSize() throws {
        let symbol = try #require(NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil))
        let drawnBytes = JSExtraMemory.byteCount(pixelsWide: symbol.size.width * 2, pixelsHigh: symbol.size.height * 2)
        #expect(drawnBytes > 0)
        #expect(HSImage.estimatedByteCount(of: symbol) == drawnBytes)
    }

    @Test("Sizes that aren't positive and finite count as nothing", arguments: [
        (0.0, 100.0), (-10.0, 100.0), (Double.infinity, 100.0), (Double.nan, 100.0),
    ])
    func invalidSizesCountAsNothing(width: Double, height: Double) {
        #expect(JSExtraMemory.byteCount(pixelsWide: width, pixelsHigh: height) == 0)
    }

    // MARK: - Helpers

    /// Write an opaque PNG of the given pixel size to a temporary file, and return its URL.
    private static func writeBitmapImage(pixelsWide: Int, pixelsHigh: Int) throws -> URL {
        let rep = try #require(unsafe NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("JSExtraMemoryTests-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}

private final class WeakImage {
    weak var value: HSImage?
    let wasCreated: Bool
    init(_ value: HSImage?) {
        self.value = value
        wasCreated = value != nil
    }
}
