//
//  HSStreamDeckIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
import IOKit
import IOKit.hid
@testable import Hammerspoon_2

private nonisolated func hasNoStreamDeck() -> Bool {
    // Matches HSStreamDeckModel.usbVendorIDElgato, duplicated here since that type is
    // @MainActor-isolated under this project's default actor isolation and can't be
    // referenced synchronously from a nonisolated `.disabled(if:)` trait expression.
    let elgatoVendorID = 0x0fd9
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [kIOHIDVendorIDKey as String: elgatoVendorID]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    guard let deviceSet = IOHIDManagerCopyDevices(manager) else { return true }
    return CFSetGetCount(deviceSet) == 0
}

@Suite("hs.streamdeck tests")
struct HSStreamDeckTests {

    // MARK: - API structure (no hardware required)

    @Suite("hs.streamdeck API structure tests")
    struct HSStreamDeckAPIStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSStreamDeckModule.self, as: "streamdeck")
            return harness
        }

        @Test("hs.streamdeck object exists")
        func testModuleExists() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.streamdeck") == "object")
        }

        @Test("all() method exists and returns an array")
        func testAllMethodExists() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.streamdeck.all") == "function")
            harness.expectTrue("Array.isArray(hs.streamdeck.all())")
        }

        @Test("findBySerialNumber() method exists and returns null for unknown serial")
        func testFindBySerialNumberMethodExists() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.streamdeck.findBySerialNumber") == "function")
            let result = harness.evalValue("hs.streamdeck.findBySerialNumber('__nonexistent__')")
            #expect(result?.isNull == true || result?.isUndefined == true)
        }

        @Test("addWatcher() and removeWatcher() methods exist")
        func testWatcherMethodsExist() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.streamdeck.addWatcher") == "function")
            #expect(harness.evalTypeOf("hs.streamdeck.removeWatcher") == "function")
        }

        @Test("_watcherEmitter is initialized by hs.streamdeck.js")
        func testWatcherEmitterInitialized() {
            let harness = makeHarness()
            harness.expectTrue("hs.streamdeck._watcherEmitter !== null && hs.streamdeck._watcherEmitter !== undefined")
        }

        @Test("module-level addWatcher() / removeWatcher() cycle is safe")
        func testModuleWatcherCycle() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var fn = function(e, d) {};
                hs.streamdeck.addWatcher(fn);
                hs.streamdeck.removeWatcher(fn);
                return true;
            })()
        """)
        }

        @Test("removeWatcher() with an unregistered listener does not crash")
        func testRemoveUnregisteredWatcherIsSafe() {
            let harness = makeHarness()
            harness.eval("hs.streamdeck.removeWatcher(function() {})")
            #expect(!harness.hasException)
        }

        @Test("addWatcher() with the same listener twice does not crash")
        func testAddWatcherIdempotent() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var fn = function(e, d) {};
                hs.streamdeck.addWatcher(fn);
                hs.streamdeck.addWatcher(fn);
                hs.streamdeck.removeWatcher(fn);
                return true;
            })()
        """)
        }

        @Test("addWatcher() throws when given a non-function")
        func testAddWatcherThrowsOnNonFunction() {
            let harness = makeHarness()
            var threw = false
            harness.registerCallback("addWatcherThrew") { threw = true }
            harness.eval("""
            try {
                hs.streamdeck.addWatcher("not a function");
            } catch(e) {
                __test_callback("addWatcherThrew");
            }
        """)
            #expect(threw)
        }
    }

    // MARK: - Model table (pure Swift, no hardware required)

    // @MainActor because HSStreamDeckModel is @MainActor-isolated under this project's
    // default actor isolation setting (it's still a plain data struct — no actor state).
    @MainActor
    struct HSStreamDeckModelTests {

        @Test("Original resolves to a 5x3 BMP device with the mirrored key transform")
        func testOriginal() {
            let model = HSStreamDeckModel.forProductID(0x0060)
            #expect(model != nil)
            #expect(model?.deckType == "Elgato Stream Deck (Original v1)")
            #expect(model?.keyColumns == 5)
            #expect(model?.keyRows == 3)
            #expect(model?.imageWidth == 72)
            #expect(model?.imageHeight == 72)
            #expect(model?.imageCodec == .bmp)
            #expect(model?.mirrorsKeyIndexPerRow == true)
            #expect(model?.imageWriteStyle == .legacyHalves)
            #expect(model?.setBrightnessCommand == [0x05, 0x55, 0xAA, 0xD1, 0x01, 0xFF])
        }

        @Test("Mini and MiniV2 resolve to identical configs")
        func testMiniAndMiniV2Match() {
            let mini = HSStreamDeckModel.forProductID(0x0063)
            let miniV2 = HSStreamDeckModel.forProductID(0x0090)
            #expect(mini != nil)
            #expect(mini?.deckType == miniV2?.deckType)
            #expect(mini?.keyColumns == miniV2?.keyColumns)
            #expect(mini?.imageRotationDegrees == 90)
            #expect(mini?.imageWriteStyle == .legacyPaginated)
        }

        @Test("XL and XLV2 resolve to identical configs")
        func testXLAndXLV2Match() {
            let xl = HSStreamDeckModel.forProductID(0x006c)
            let xlV2 = HSStreamDeckModel.forProductID(0x008F)
            #expect(xl != nil)
            #expect(xl?.deckType == xlV2?.deckType)
            #expect(xl?.keyColumns == 8)
            #expect(xl?.keyRows == 4)
            #expect(xl?.imageWriteStyle == .v2)
        }

        @Test("Plus has encoders and a screen")
        func testPlus() {
            let model = HSStreamDeckModel.forProductID(0x0084)
            #expect(model != nil)
            #expect(model?.keyColumns == 4)
            #expect(model?.keyRows == 2)
            #expect(model?.encoderColumns == 4)
            #expect(model?.encoderCount == 4)
            #expect(model?.hasScreen == true)
            #expect(model?.lcdStripWidth == 800)
            #expect(model?.lcdStripHeight == 100)
        }

        @Test("Pedal has no image support and no brightness command")
        func testPedal() {
            let model = HSStreamDeckModel.forProductID(0x0086)
            #expect(model != nil)
            #expect(model?.imageCodec == .unsupported)
            #expect(model?.imageWriteStyle == .unsupported)
            #expect(model?.setBrightnessCommand == nil)
            #expect(model?.keyColumns == 3)
            #expect(model?.keyRows == 1)
        }

        @Test("unknown product ID returns nil")
        func testUnknownProductID() {
            #expect(HSStreamDeckModel.forProductID(0xFFFF) == nil)
        }

        @Test("all 9 known product IDs resolve to a model")
        func testAllProductIDsResolve() {
            let productIDs = [0x0060, 0x006d, 0x0063, 0x0090, 0x006c, 0x008F, 0x0080, 0x0084, 0x0086]
            for productID in productIDs {
                #expect(HSStreamDeckModel.forProductID(productID) != nil, "product ID 0x\(String(productID, radix: 16)) should resolve")
            }
        }

        @Test("transformKeyIndex mirrors each row for a 5-column 3-row grid")
        func testTransformKeyIndexMirrorsRows() {
            let model = HSStreamDeckModel.forProductID(0x0060)! // Original
            // Row 1 (keys 1-5): 1<->5, 2<->4, 3 stays put
            #expect(model.transformKeyIndex(1) == 5)
            #expect(model.transformKeyIndex(2) == 4)
            #expect(model.transformKeyIndex(3) == 3)
            #expect(model.transformKeyIndex(4) == 2)
            #expect(model.transformKeyIndex(5) == 1)
            // Row 2 (keys 6-10): 6<->10, 8 stays put
            #expect(model.transformKeyIndex(6) == 10)
            #expect(model.transformKeyIndex(8) == 8)
            #expect(model.transformKeyIndex(10) == 6)
            // Applying the transform twice returns the original index (it's an involution)
            for key in 1...15 {
                #expect(model.transformKeyIndex(model.transformKeyIndex(key)) == key)
            }
        }

        @Test("transformKeyIndex is the identity when mirrorsKeyIndexPerRow is false")
        func testTransformKeyIndexIdentityElsewhere() {
            let model = HSStreamDeckModel.forProductID(0x0084)! // Plus
            for key in 1...model.keyCount {
                #expect(model.transformKeyIndex(key) == key)
            }
        }
    }

    // MARK: - Image rendering (pure Swift, no hardware required)

    // @MainActor: HSStreamDeckImageRendering is @MainActor-isolated under this project's
    // default actor isolation setting, and NSImage rendering (lockFocus/NSGraphicsContext)
    // must happen on the main thread regardless.
    @MainActor
    struct HSStreamDeckImageRenderingTests {

        @Test("renderForDevice produces a valid BMP header for the Original")
        func testBMPHeader() {
            let model = HSStreamDeckModel.forProductID(0x0060)! // Original: 72x72, BMP
            let swatch = HSStreamDeckImageRendering.solidColorImage(.red, size: NSSize(width: model.imageWidth, height: model.imageHeight))
            guard let data = HSStreamDeckImageRendering.renderForDevice(swatch, model: model) else {
                Issue.record("renderForDevice returned nil")
                return
            }
            let bytes = [UInt8](data)
            #expect(bytes.count > 54) // header + at least some pixel data

            // BITMAPFILEHEADER: bfType "BM" (0x42, 0x4D little-endian for 0x4D42)
            #expect(bytes[0] == 0x42)
            #expect(bytes[1] == 0x4D)
            // bfOffBits == 54 (14 + 40), little-endian UInt32 at offset 10
            let bfOffBits = UInt32(bytes[10]) | (UInt32(bytes[11]) << 8) | (UInt32(bytes[12]) << 16) | (UInt32(bytes[13]) << 24)
            #expect(bfOffBits == 54)

            // BITMAPINFOHEADER: biWidth/biHeight at offsets 18/22, biBitCount at offset 28
            let biWidth = UInt32(bytes[18]) | (UInt32(bytes[19]) << 8) | (UInt32(bytes[20]) << 16) | (UInt32(bytes[21]) << 24)
            let biHeight = UInt32(bytes[22]) | (UInt32(bytes[23]) << 8) | (UInt32(bytes[24]) << 16) | (UInt32(bytes[25]) << 24)
            let biBitCount = UInt16(bytes[28]) | (UInt16(bytes[29]) << 8)
            #expect(biWidth == UInt32(model.imageWidth))
            #expect(biHeight == UInt32(model.imageHeight))
            #expect(biBitCount == 24)

            // Row padding: (width*3 + extraBytes) * height + 54 == total byte count
            let extraBytes = (4 - (model.imageWidth * 3) % 4) % 4
            let expectedPixelBytes = (model.imageWidth * 3 + extraBytes) * model.imageHeight
            #expect(bytes.count == 54 + expectedPixelBytes)
        }

        @Test("BMP pixel data is BGR-ordered for a solid red swatch")
        func testBMPPixelByteOrder() {
            let model = HSStreamDeckModel.forProductID(0x0060)!
            let swatch = HSStreamDeckImageRendering.solidColorImage(.red, size: NSSize(width: model.imageWidth, height: model.imageHeight))
            guard let data = HSStreamDeckImageRendering.renderForDevice(swatch, model: model) else {
                Issue.record("renderForDevice returned nil")
                return
            }
            let bytes = [UInt8](data)
            // First pixel after the 54-byte header: solid red should encode as B=0, G=0, R=255 (approximately)
            #expect(bytes.count > 57)
            #expect(bytes[54] < 40)   // B
            #expect(bytes[55] < 40)   // G
            #expect(bytes[56] > 200)  // R
        }

        @Test("renderForDevice produces non-empty JPEG data for JPEG-codec models")
        func testJPEGEncoding() {
            let model = HSStreamDeckModel.forProductID(0x006d)! // OriginalV2: JPEG
            let swatch = HSStreamDeckImageRendering.solidColorImage(.blue, size: NSSize(width: model.imageWidth, height: model.imageHeight))
            let data = HSStreamDeckImageRendering.renderForDevice(swatch, model: model)
            #expect(data != nil)
            #expect((data?.count ?? 0) > 0)
            // JPEG magic bytes: 0xFF 0xD8
            #expect(data?.first == 0xFF)
            #expect(data?.dropFirst().first == 0xD8)
        }

        @Test("renderForDevice returns nil for a device with no image support")
        func testNoImageSupportReturnsNil() {
            let model = HSStreamDeckModel.forProductID(0x0086)! // Pedal
            let swatch = HSStreamDeckImageRendering.solidColorImage(.black, size: NSSize(width: 10, height: 10))
            #expect(model.imageCodec == .unsupported)
            #expect(HSStreamDeckImageRendering.renderForDevice(swatch, model: model) == nil)
        }

        @Test("renderScreenImage produces data sized for one encoder tile on the Plus")
        func testScreenImageRendering() {
            let model = HSStreamDeckModel.forProductID(0x0084)! // Plus
            let swatch = HSStreamDeckImageRendering.solidColorImage(.green, size: NSSize(width: 200, height: 100))
            let data = HSStreamDeckImageRendering.renderScreenImage(swatch, model: model)
            #expect(data != nil)
            #expect((data?.count ?? 0) > 0)
        }

        @Test("renderScreenImage returns nil for devices with no screen")
        func testScreenImageNilWithoutScreen() {
            let model = HSStreamDeckModel.forProductID(0x0060)! // Original: no screen
            let swatch = HSStreamDeckImageRendering.solidColorImage(.green, size: NSSize(width: 72, height: 72))
            #expect(HSStreamDeckImageRendering.renderScreenImage(swatch, model: model) == nil)
        }
    }

    // MARK: - Hardware-gated tests (real Stream Deck required)

    @Suite("hs.streamdeck device tests", .serialized,
           .disabled(if: hasNoStreamDeck(), "No Stream Deck hardware present"))
    struct HSStreamDeckDeviceTests {

        // A single, long-lived harness shared by every test in this suite, matching how
        // hs.streamdeck is actually used in a real app (exactly one HSStreamDeckModule,
        // and therefore exactly one IOHIDManager, alive for the process's lifetime).
        // Opening/closing a fresh IOHIDManager against the same physical device per test
        // — the pattern every other suite in this file uses — is unrealistic here and
        // flaky in practice: macOS needs a brief moment after IOHIDManagerClose() before
        // the same device accepts another exclusive-ish open, so back-to-back
        // open/read/close cycles across tests intermittently fail feature-report reads
        // (e.g. serialNumber coming back empty) even though a single long-lived session
        // — the only way hs.streamdeck is ever actually used — works reliably.
        @MainActor
        static let sharedHarness: JSTestHarness = {
            let harness = JSTestHarness()
            harness.loadModule(HSStreamDeckModule.self, as: "streamdeck")
            return harness
        }()

        private var harness: JSTestHarness { HSStreamDeckDeviceTests.sharedHarness }

        @Test("all() returns at least one device")
        func testAllReturnsDevices() {
            harness.expectTrue("hs.streamdeck.all().length > 0")
        }

        @Test("each device has non-empty deckType and serialNumber strings")
        func testDeviceIdentity() {
            harness.expectTrue("""
            hs.streamdeck.all().every(function(d) {
                return typeof d.deckType === 'string' && d.deckType.length > 0 &&
                       typeof d.serialNumber === 'string' && d.serialNumber.length > 0;
            })
        """)
        }

        @Test("each device has sane keyColumns/keyRows/imageSize")
        func testDeviceLayout() {
            harness.expectTrue("""
            hs.streamdeck.all().every(function(d) {
                return d.keyColumns > 0 && d.keyRows > 0 && d.keyCount === d.keyColumns * d.keyRows &&
                       typeof d.imageSize === 'object';
            })
        """)
        }

        @Test("typeName is 'HSStreamDeckDevice'")
        func testTypeName() {
            harness.expectEqual("hs.streamdeck.all()[0].typeName", "HSStreamDeckDevice")
        }

        @Test("toString() and console.log() describe the device instead of the default JS object tag")
        func testToString() {
            harness.expectTrue("""
            (function() {
                const d = hs.streamdeck.all()[0];
                const s = String(d);
                return s === d.toString() &&
                       s.startsWith('<HSStreamDeckDevice: ') && s.endsWith('>') &&
                       s.includes(d.deckType);
            })()
        """)
        }

        @Test("findBySerialNumber() round-trips through all()")
        func testFindBySerialNumberRoundTrip() {
            harness.expectTrue("""
            (function() {
                var first = hs.streamdeck.all()[0];
                var found = hs.streamdeck.findBySerialNumber(first.serialNumber);
                return found !== null && found.serialNumber === first.serialNumber;
            })()
        """)
        }

        @Test("buttonCallback/encoderCallback/screenCallback don't throw and return the device")
        func testCallbackChaining() {
            harness.expectTrue("""
            (function() {
                var d = hs.streamdeck.all()[0];
                var r1 = d.buttonCallback(function() {});
                var r2 = d.encoderCallback(function() {});
                var r3 = d.screenCallback(function() {});
                return r1 === d && r2 === d && r3 === d;
            })()
        """)
            #expect(!harness.hasException)
        }

        @Test("setBrightness() and reset() don't throw and return the device")
        func testBrightnessAndReset() {
            harness.expectTrue("""
            (function() {
                var d = hs.streamdeck.all()[0];
                var r1 = d.setBrightness(50);
                var r2 = d.reset();
                return r1 === d && r2 === d;
            })()
        """)
            #expect(!harness.hasException)
        }

        @Test("setButtonImage() and setButtonColor() don't throw and return the device")
        func testButtonImageAndColor() {
            harness.eval("""
            var d = hs.streamdeck.all()[0];
            var r1 = d.setButtonColor(1, HSColor.named("red"));
            var img = HSImage.fromName("NSComputer");
            var r2 = img ? d.setButtonImage(1, img) : d;
            var _chained = (r1 === d && r2 === d);
        """)
            #expect(!harness.hasException)
            harness.expectTrue("_chained")
        }
    }
}
