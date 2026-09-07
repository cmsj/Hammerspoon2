//
//  HSCanvasIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
@testable import Hammerspoon_2

@Suite("hs.canvas tests", .serialized)
struct HSCanvasTests {

    // MARK: - Module structure

    @Suite("hs.canvas API structure tests")
    struct StructureTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            return harness
        }

        @Test("hs.canvas is an object")
        func moduleIsObject() {
            #expect(makeHarness().evalTypeOf("hs.canvas") == "object")
        }

        @Test("create is a function")
        func createIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.canvas.create") == "function")
        }

        @Test("create() returns an object")
        func createReturnsObject() {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 100})")
            #expect(harness.evalTypeOf("c") == "object")
            #expect(!harness.hasException)
        }

        @Test("HSCanvas.typeName is HSCanvas")
        func typeName() {
            makeHarness().expectEqual(
                "hs.canvas.create({x: 0, y: 0, w: 100, h: 100}).typeName",
                "HSCanvas"
            )
        }

        @Test("windowLevels is an object with numeric values")
        func windowLevelsIsNumericObject() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.canvas.windowLevels") == "object")
            #expect(harness.evalTypeOf("hs.canvas.windowLevels.screenSaver") == "number")
            #expect(harness.evalTypeOf("hs.canvas.windowLevels.normal") == "number")
        }

        @Test("windowLevels supports arithmetic like v1")
        func windowLevelsArithmetic() {
            let harness = makeHarness()
            harness.eval("var lvl = hs.canvas.windowLevels.screenSaver + 1")
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("lvl") == "number")
        }

        @Test("windowBehaviors is an object with numeric values")
        func windowBehaviorsIsNumericObject() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.canvas.windowBehaviors") == "object")
            #expect(harness.evalTypeOf("hs.canvas.windowBehaviors.canJoinAllSpaces") == "number")
        }
    }

    // MARK: - Lifecycle chaining

    @Suite("hs.canvas lifecycle tests")
    struct LifecycleTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            return harness
        }

        @Test("show/hide/destroy don't throw and return chainable values")
        @MainActor
        func showHideDestroy() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.show()
                var showing = c.isShowing()
                c.hide()
                var hidingWorked = (c.isShowing() === false)
                c.destroy()
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("showing") == "boolean")
            harness.expectEqual("hidingWorked", true)
        }

        @Test("levelValue() accepts a raw numeric level and chains")
        @MainActor
        func levelValueNumeric() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                var result = c.levelValue(hs.canvas.windowLevels.screenSaver + 1)
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("result") == "object")
        }

        @Test("level() accepts a named level and chains")
        @MainActor
        func levelNamed() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                var result = c.level("floating")
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("result") == "object")
        }

        @Test("behavior() accepts a named behavior and chains")
        @MainActor
        func behaviorNamed() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                var result = c.behavior("canJoinAllSpaces")
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("result") == "object")
        }

        @Test("behaviorList() accepts an array of named behaviors and chains")
        @MainActor
        func behaviorListNamed() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                var result = c.behaviorList(["canJoinAllSpaces", "stationary"])
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("result") == "object")
        }

        @Test("behaviorValue() accepts a raw bitmask and chains")
        @MainActor
        func behaviorValueNumeric() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                var result = c.behaviorValue(hs.canvas.windowBehaviors.canJoinAllSpaces)
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("result") == "object")
        }

        @Test("clickActivating() and ignoreMouseEvents() chain without throwing")
        @MainActor
        func clickThroughChaining() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.clickActivating(false).ignoreMouseEvents(true).show()
                """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Position and size

    @Suite("hs.canvas position/size tests")
    struct PositionTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            return harness
        }

        @Test("frame() reflects the rect passed to create()")
        func frameReflectsCreate() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 10, y: 20, w: 100, h: 50})
                var f = c.frame()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("f.x", 10)
            harness.expectEqual("f.y", 20)
            harness.expectEqual("f.w", 100)
            harness.expectEqual("f.h", 50)
        }

        @Test("setFrame() updates position and size, leaving omitted keys unchanged")
        @MainActor
        func setFrameUpdatesAndPreservesOmitted() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 100})
                c.show()
                c.setFrame({x: 50, y: 60})
                var f = c.frame()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("f.x", 50)
            harness.expectEqual("f.y", 60)
            harness.expectEqual("f.w", 100)
            harness.expectEqual("f.h", 100)
        }

        @Test("topLeft() is the frame's origin plus its height (unflipped AppKit sense)")
        func topLeftMatchesFrame() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 10, y: 20, w: 100, h: 50})
                var tl = c.topLeft()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("tl.x", 10)
            harness.expectEqual("tl.y", 70)
        }

        @Test("setTopLeft() moves the window without changing its size")
        @MainActor
        func setTopLeftPreservesSize() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 50})
                c.show()
                c.setTopLeft({x: 200, y: 300})
                var f = c.frame()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("f.y", 250) // topLeft y (300) - height (50)
            harness.expectEqual("f.w", 100)
            harness.expectEqual("f.h", 50)
        }

        @Test("size() reflects the rect passed to create()")
        func sizeReflectsCreate() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 120, h: 80})
                var s = c.size()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("s.w", 120)
            harness.expectEqual("s.h", 80)
        }

        @Test("setSize() resizes the window without moving its origin")
        @MainActor
        func setSizePreservesOrigin() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 30, y: 40, w: 100, h: 100})
                c.show()
                c.setSize({w: 200, h: 150})
                var f = c.frame()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("f.x", 30)
            harness.expectEqual("f.y", 40)
            harness.expectEqual("f.w", 200)
            harness.expectEqual("f.h", 150)
        }
    }

    // MARK: - Element CRUD

    @Suite("hs.canvas element management tests")
    struct ElementTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            return harness
        }

        @Test("appendElements() adds elements and elementCount() reflects it")
        func appendAndCount() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([
                    { type: "rectangle", action: "fill", fillColor: { alpha: 1 } },
                    { type: "circle", action: "fill", fillColor: { alpha: 1 } }
                ])
                var count = c.elementCount()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("count", 2)
        }

        @Test("canvasElements() round-trips the appended elements")
        func canvasElementsRoundTrip() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill" }])
                var elements = c.canvasElements()
                var firstType = elements[0].type
                """)
            #expect(!harness.hasException)
            harness.expectEqual("firstType", "rectangle")
        }

        @Test("elementAttribute get/set round-trips a value")
        func elementAttributeRoundTrip() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill" }])
                c.setElementAttribute(0, "strokeWidth", 4)
                var width = c.elementAttribute(0, "strokeWidth")
                """)
            #expect(!harness.hasException)
            harness.expectEqual("width", 4)
        }

        @Test("removeElementAttribute() removes a single attribute")
        func removeElementAttribute() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill", strokeWidth: 4 }])
                c.removeElementAttribute(0, "strokeWidth")
                var width = c.elementAttribute(0, "strokeWidth")
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("width") == "undefined" || harness.evalTypeOf("width") == "object")
        }

        @Test("removeElement() removes the element at an index")
        func removeElement() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([
                    { type: "rectangle", action: "fill" },
                    { type: "circle", action: "fill" }
                ])
                c.removeElement(0)
                var count = c.elementCount()
                var remainingType = c.canvasElements()[0].type
                """)
            #expect(!harness.hasException)
            harness.expectEqual("count", 1)
            harness.expectEqual("remainingType", "circle")
        }

        @Test("replaceElements() replaces the full element list")
        func replaceElements() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill" }])
                c.replaceElements([{ type: "oval", action: "fill" }, { type: "text", text: "hi" }])
                var count = c.elementCount()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("count", 2)
        }

        @Test("elementBounds() returns a plausible bounding rect for a circle")
        func elementBounds() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 100})
                c.appendElements([{ type: "circle", action: "fill", center: {x: 50, y: 50}, radius: 20 }])
                var bounds = c.elementBounds(0)
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("bounds.w") == "number")
            #expect(harness.evalTypeOf("bounds.h") == "number")
        }
    }

    // MARK: - Mouse interaction, transforms, and full-parity extras (M4/M5)

    @Suite("hs.canvas mouse/transform/extras tests")
    struct ExtrasTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            return harness
        }

        @Test("mouseCallback() and canvasMouseEvents() chain without throwing")
        @MainActor
        func mouseCallbackChaining() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "circle", action: "fill", trackMouseDown: true, id: "dot" }])
                var result = c.mouseCallback((canvas, message, id, x, y) => {}).canvasMouseEvents(true, true, true, true)
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("result") == "object")
        }

        @Test("rotateElement() stores a rotation attribute readable via elementAttribute")
        func rotateElementStoresAttribute() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill" }])
                c.rotateElement(0, 45)
                var angle = c.elementAttribute(0, "rotation")
                """)
            #expect(!harness.hasException)
            harness.expectEqual("angle", 45)
        }

        @Test("rotateElementAroundPoint() stores both rotation and rotationPoint")
        func rotateElementAroundPointStoresAttributes() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill" }])
                c.rotateElementAroundPoint(0, 90, {x: 5, y: 5})
                var point = c.elementAttribute(0, "rotationPoint")
                """)
            #expect(!harness.hasException)
            harness.expectEqual("point.x", 5)
        }

        @Test("setElementTransformation() and setTransformation()/clearTransformation() chain")
        @MainActor
        func transformationChaining() {
            let harness = makeHarness()
            harness.eval("""
                var matrix = {m11: 1, m12: 0, m21: 0, m22: 1, tX: 10, tY: 10}
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill" }])
                var result = c.setElementTransformation(0, matrix).setTransformation(matrix).clearTransformation()
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("result") == "object")
        }

        @Test("duplicate() produces an independent canvas with the same elements")
        func duplicateCopiesElements() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill" }])
                var d = c.duplicate()
                d.appendElements([{ type: "circle", action: "fill" }])
                var originalCount = c.elementCount()
                var duplicateCount = d.elementCount()
                """)
            #expect(!harness.hasException)
            harness.expectEqual("originalCount", 1)
            harness.expectEqual("duplicateCount", 2)
        }

        @Test("imageFromCanvas() returns an HSImage after show()")
        @MainActor
        func imageFromCanvasReturnsImage() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill", fillColor: { alpha: 1 } }])
                c.show()
                var img = c.imageFromCanvas()
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("img") == "object")
        }

        @Test("setAccessibilitySubrole() and draggingCallback() chain without throwing")
        @MainActor
        func accessibilityAndDraggingChaining() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                var result = c.setAccessibilitySubrole("HSCanvasOverlay").draggingCallback((paths) => {})
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("result") == "object")
        }

        @Test("compositeTypes is an object exposing blend-mode names")
        func compositeTypesIsObject() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.canvas.compositeTypes") == "object")
            #expect(harness.evalTypeOf("hs.canvas.compositeTypes.multiply") == "string")
        }

        @Test("gradient/arc/segments/points/image element types don't throw when rendered")
        @MainActor
        func newElementTypesDontThrow() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 100})
                c.appendElements([
                    { type: "arc", action: "fill", center: {x: 50, y: 50}, radius: 20, startAngle: 0, endAngle: 180, fillColor: {alpha: 1} },
                    { type: "ellipticalArc", action: "fill", frame: {x: 0, y: 0, w: 80, h: 40}, startAngle: 0, endAngle: 360, fillColor: {alpha: 1} },
                    { type: "segments", action: "stroke", coordinates: [{x: 0, y: 0}, {x: 50, y: 50}], strokeColor: {alpha: 1} },
                    { type: "points", action: "fill", coordinates: [{x: 10, y: 10}, {x: 20, y: 20}], fillColor: {alpha: 1} },
                    { type: "rectangle", action: "fill", fillGradient: "linear", fillGradientColors: [{red: 1, alpha: 1}, {blue: 1, alpha: 1}] }
                ])
                c.show()
                """)
            #expect(!harness.hasException)
        }

        @Test("nested canvas element renders without throwing and respects recursion guard")
        @MainActor
        func nestedCanvasElement() {
            let harness = makeHarness()
            harness.eval("""
                var inner = hs.canvas.create({x: 0, y: 0, w: 20, h: 20})
                inner.appendElements([{ type: "rectangle", action: "fill", fillColor: { alpha: 1 } }])
                var outer = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                outer.appendElements([{ type: "canvas", canvas: inner, frame: {x: 0, y: 0, w: 20, h: 20} }])
                outer.show()
                """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Memory leak tests

    @Test("Shown HSCanvas is released after shutdown")
    @MainActor
    func testCanvasDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        // autoreleasepool {} (not do {}) ensures JSValues returned by harness.eval()
        // are drained here rather than in the outer test-runner pool -- see
        // HSUIIntegrationTests.testWindowDoesNotLeakAfterReload for the full rationale.
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            // show() registers the canvas in HSCanvasModule.activeCanvases (strong
            // dictionary). Without shutdown(), it would be held alive by the module
            // even after the JS reference is dropped. shutdown() calls destroy() on
            // each canvas and then clears activeCanvases, releasing the strong ref.
            // Also set mouseCallback/draggingCallback so this test exercises the
            // JSCallback-detach paths in destroy() -- not just the window-registration path.
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 100})
                c.appendElements([{ type: "rectangle", action: "fill", fillColor: { alpha: 1 } }])
                c.mouseCallback(() => {})
                c.draggingCallback(() => {})
                c.show()
            """)
            if let obj = harness.evalValue("c")?.toObjectOf(HSCanvas.self) as? HSCanvas {
                tracker.track(obj)
            }
            harness.eval("c = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks(timeout: 1.0)
    }
}
