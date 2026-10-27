//
//  HSCanvasIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
import SwiftUI
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

        @Test("show() after destroy() throws, and doesn't bring the canvas back")
        @MainActor
        func showAfterDestroyThrows() {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}); c.show(); c.destroy()")
            #expect(!harness.hasException)

            harness.eval("c.show()")
            #expect(harness.exceptionMessage?.contains("destroyed") == true)
            #expect(harness.evalBool("c.isShowing()") == false)
        }

        @Test("Methods that would give a destroyed canvas elements or callbacks again throw",
              arguments: [
                  "appendElements([{ type: 'rectangle' }])",
                  "insertElement({ type: 'rectangle' }, 0)",
                  "assignElement({ type: 'rectangle' }, 0)",
                  "replaceElements([{ type: 'rectangle' }])",
                  "mouseCallback(() => {})",
                  "draggingCallback(() => {})",
                  "duplicate()",
              ])
        @MainActor
        func methodsThrowAfterDestroy(call: String) {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}); c.destroy()")
            #expect(!harness.hasException)

            harness.eval("c.\(call)")
            let method = String(call.prefix(while: { $0 != "(" }))
            #expect(harness.exceptionMessage?.contains("\(method)() can't be called on a canvas that has been destroyed") == true)
            #expect(harness.evalInt("c.elementCount()") == 0)
        }

        @Test("imageFromCanvas() returns null after destroy()")
        @MainActor
        func imageFromCanvasAfterDestroy() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill", fillColor: { red: 1 } }])
                var before = c.imageFromCanvas()
                c.destroy()
                var after = c.imageFromCanvas()
                """)
            #expect(!harness.hasException)
            #expect(harness.evalBool("before !== null && before !== undefined") == true, "A live canvas must render, for the test to mean anything")
            // JSC bridges a nil return as undefined, so match either until nil returns are
            // mapped to null everywhere.
            #expect(harness.evalBool("after == null") == true)
        }

        @Test("hide() after destroy() does nothing")
        @MainActor
        func hideAfterDestroyIsHarmless() {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}); c.show(); c.destroy(); var r = c.hide()")
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("r") == "object")
        }

        @Test("destroy() releases the canvas's elements, and the images they hold, while the canvas is still referenced")
        @MainActor
        func destroyReleasesElements() {
            let harness = makeHarness()
            weak var image: HSImage?
            autoreleasepool {
                harness.eval("""
                    var src = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                    src.appendElements([{ type: "rectangle", action: "fill", fillColor: { red: 1 } }])
                    var img = src.imageFromCanvas()
                    var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                    c.appendElements([{ type: "image", image: img }])
                    c.show()
                    void 0
                """)
                image = harness.evalValue("img")?.toObjectOf(HSImage.self) as? HSImage
                // Checked while JS still references the image: once it doesn't, a collection
                // could free it at any point.
                #expect(image != nil, "The image must have been made for the test to mean anything")
                harness.eval("img = null; src.destroy(); c.destroy(); void 0")
            }
            #expect(harness.evalInt("c.elementCount()") == 0)

            harness.collectGarbage()
            #expect(image == nil, "A destroyed canvas must not keep its elements' images alive")
            #expect(!harness.hasException)
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

        @Test("behaviorList() applies the combined behavior to a shown window")
        @MainActor
        func behaviorListAppliesToWindow() throws {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).show()
                c.behaviorList(["canJoinAllSpaces", "stationary"])
                void 0
                """)
            let canvas = try #require(harness.evalValue("c")?.toObjectOf(HSCanvas.self) as? HSCanvas)
            #expect(canvas.windowCollectionBehavior == [.canJoinAllSpaces, .stationary])
            #expect(!harness.hasException)
            harness.eval("c.destroy()")
        }

        // canJoinAllSpaces + moveToActiveSpace makes AppKit raise an uncaught
        // NSInternalInconsistencyException, so without the check this test would crash the runner
        @Test("behaviorList() and behaviorValue() throw for mutually exclusive behaviors and keep the old one")
        @MainActor
        func conflictingBehaviorsThrow() throws {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).show()
                c.behavior("stationary")
                var listError = null
                try { c.behaviorList(["canJoinAllSpaces", "moveToActiveSpace"]) } catch (e) { listError = e.message }
                var valueError = null
                var b = hs.canvas.windowBehaviors
                try { c.behaviorValue(b.canJoinAllSpaces | b.moveToActiveSpace) } catch (e) { valueError = e.message }
                void 0
                """)
            #expect(!harness.hasException)
            #expect(harness.evalString("listError")?.contains("'canJoinAllSpaces' and 'moveToActiveSpace' cannot be combined") == true)
            #expect(harness.evalString("valueError")?.contains("cannot be combined") == true)
            let canvas = try #require(harness.evalValue("c")?.toObjectOf(HSCanvas.self) as? HSCanvas)
            #expect(canvas.windowCollectionBehavior == [.stationary])
            harness.eval("c.destroy()")
        }

        @Test("behaviorValue() with a negative bitmask throws instead of trapping")
        @MainActor
        func negativeBehaviorValueThrows() {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}); c.behaviorValue(-1)")
            harness.expectException()
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

        @Test("setSize() resizes the window without moving its top-left corner")
        @MainActor
        func setSizePreservesTopLeft() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 30, y: 40, w: 100, h: 100})
                c.show()
                c.setSize({w: 200, h: 150})
                var f = c.frame()
                var tl = c.topLeft()
                """)
            #expect(!harness.hasException)
            // The origin (bottom-left, f.x/f.y) is expected to move -- only the top-left
            // corner (tl) is promised to stay fixed when the height changes.
            harness.expectEqual("f.x", 30)
            harness.expectEqual("f.y", -10) // topY (40 + 100 = 140) - new height (150)
            harness.expectEqual("f.w", 200)
            harness.expectEqual("f.h", 150)
            harness.expectEqual("tl.x", 30)
            harness.expectEqual("tl.y", 140) // unchanged from before the resize
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

        @Test("elementBounds() reflects the whole-canvas transformation")
        func elementBoundsReflectsCanvasTransform() {
            // Drawing already applies setTransformation() at render time -- elementBounds()
            // has to apply the same transform to what it reports, or the bounds disagree
            // with the shape actually on screen.
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 100})
                c.appendElements([{ type: "rectangle", action: "fill", frame: {x: 0, y: 0, w: 10, h: 10} }])
                var before = c.elementBounds(0)
                c.setTransformation({m11: 1, m12: 0, m21: 0, m22: 1, tX: 50, tY: 50})
                var after = c.elementBounds(0)
                """)
            #expect(!harness.hasException)
            harness.expectEqual("before.x", 0)
            harness.expectEqual("before.y", 0)
            harness.expectEqual("after.x", 50)
            harness.expectEqual("after.y", 50)
        }

        @Test("An HSColor or hex string set from JS is stored so it draws as that color")
        func colorFormsFromJS() throws {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 100})
                c.appendElements([{ type: "rectangle", action: "fill", fillColor: HSColor.hex("#00FF00") }])
                c.setElementAttribute(0, "strokeColor", "#0000FF")
                """)
            #expect(!harness.hasException)
            let element = try #require(harness.evalValue("c.canvasElements()[0]")?.toDictionary() as? [String: Any])
            let fillColor = try #require(CanvasElementDrawing.parseColor(element["fillColor"]))
            let strokeColor = try #require(CanvasElementDrawing.parseColor(element["strokeColor"]))
            let fill = try #require(NSColor(fillColor).usingColorSpace(.sRGB))
            let stroke = try #require(NSColor(strokeColor).usingColorSpace(.sRGB))
            #expect(fill.greenComponent == 1 && fill.redComponent == 0)
            #expect(stroke.blueComponent == 1 && stroke.redComponent == 0)
        }

        @Test("minimumTextSize() returns a numeric size for a text element's font attributes")
        func minimumTextSize() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 200, h: 200})
                c.appendElements([{ type: "text", text: "placeholder", textSize: 24 }])
                var size = c.minimumTextSize(0, "Hammerspoon")
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("size.w") == "number")
            #expect(harness.evalTypeOf("size.h") == "number")
        }

        @Test("minimumTextSize() measures multi-line text taller than the same text on one line")
        func minimumTextSizeMultiLine() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 200, h: 200})
                c.appendElements([{ type: "text", text: "placeholder", textSize: 24 }])
                var oneLine = c.minimumTextSize(0, "Hammerspoon")
                var twoLines = c.minimumTextSize(0, "Hammer\\nspoon")
                var tallerWhenWrapped = twoLines.h > oneLine.h
                """)
            #expect(!harness.hasException)
            harness.expectEqual("tallerWhenWrapped", true)
        }

        @Test("minimumTextSize() returns an empty object for an out-of-bounds index")
        func minimumTextSizeOutOfBounds() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 200, h: 200})
                var size = c.minimumTextSize(0, "Hammerspoon")
                var keyCount = Object.keys(size).length
                """)
            #expect(!harness.hasException)
            harness.expectEqual("keyCount", 0)
        }

        @Test("minimumTextSize(text) measures with the default font attributes on an empty canvas")
        func minimumTextSizeTextOnly() {
            let harness = makeHarness()
            harness.eval("""
                var empty = hs.canvas.create({x: 0, y: 0, w: 200, h: 200})
                var defaults = empty.minimumTextSize("Hammerspoon")
                var c = hs.canvas.create({x: 0, y: 0, w: 200, h: 200})
                c.appendElements([{ type: "text", text: "placeholder" }])
                var fromElement = c.minimumTextSize(0, "Hammerspoon")
                """)
            #expect(!harness.hasException)
            #expect(harness.evalDouble("defaults.w") ?? 0 > 0)
            #expect(harness.evalDouble("defaults.w") == harness.evalDouble("fromElement.w"))
            #expect(harness.evalDouble("defaults.h") == harness.evalDouble("fromElement.h"))
        }

        @Test("minimumTextSize(attributes, text) measures with an object's font attributes")
        func minimumTextSizeAttributes() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 200, h: 200})
                c.appendElements([{ type: "text", text: "placeholder", textSize: 40 }])
                var fromObject = c.minimumTextSize({ textSize: 40 }, "Hammerspoon")
                var fromElement = c.minimumTextSize(0, "Hammerspoon")
                var small = c.minimumTextSize({ textSize: 10 }, "Hammerspoon")
                """)
            #expect(!harness.hasException)
            #expect(harness.evalDouble("fromObject.w") == harness.evalDouble("fromElement.w"))
            #expect(harness.evalDouble("fromObject.h") == harness.evalDouble("fromElement.h"))
            harness.expectTrue("small.w < fromObject.w && small.h < fromObject.h")
        }

        @Test("minimumTextSize() uses the font attributes of a non-text element")
        func minimumTextSizeNonTextElement() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 200, h: 200})
                c.appendElements([{ type: "rectangle", action: "fill", textSize: 40 }])
                var fromRectangle = c.minimumTextSize(0, "Hammerspoon")
                var fromObject = c.minimumTextSize({ textSize: 40 }, "Hammerspoon")
                """)
            #expect(!harness.hasException)
            #expect(harness.evalDouble("fromRectangle.w") == harness.evalDouble("fromObject.w"))
        }

        @Test("minimumTextSize() returns an empty object for invalid arguments", arguments: [
            "c.minimumTextSize(0)",
            "c.minimumTextSize(0, 42)",
            "c.minimumTextSize(true, 'Hammerspoon')",
            "c.minimumTextSize()",
            "c.minimumTextSize(4294967296, 'Hammerspoon')",
            "c.minimumTextSize(-1, 'Hammerspoon')",
            "c.minimumTextSize(NaN, 'Hammerspoon')",
        ])
        func minimumTextSizeInvalidArguments(call: String) {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 200, h: 200})
                c.appendElements([{ type: "text", text: "placeholder" }])
                var keyCount = Object.keys(\(call)).length
                """)
            #expect(!harness.hasException)
            harness.expectEqual("keyCount", 0)
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

        @Test("canvasMouseEvents() accepts right-button flags, and still accepts the original four")
        @MainActor
        func canvasMouseEventsRightButton() {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "circle", action: "fill", trackRightMouseDown: true, trackRightMouseUp: true, id: "dot" }])
                var withRight = c.canvasMouseEvents(true, true, true, true, true, true)
                var withoutRight = c.canvasMouseEvents(true, false, false, false)
                var stored = c.elementAttribute(0, "trackRightMouseDown")
                """)
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("withRight") == "object")
            #expect(harness.evalTypeOf("withoutRight") == "object")
            harness.expectTrue("stored === true")
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

    // MARK: - Opacity and fading (issue #289)

    @Suite("hs.canvas opacity and fading tests", .serialized)
    @MainActor
    struct FadeTests {
        // Tests that wait for a fade to finish are async: AppKit delivers the fade's
        // completion through the main queue, which a sync @MainActor test blocks while it
        // spins the run loop in waitFor(), so the fade would never seem to finish.

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            return harness
        }

        private func canvas(_ harness: JSTestHarness, _ name: String = "c") -> HSCanvas? {
            harness.evalValue(name)?.toObjectOf(HSCanvas.self) as? HSCanvas
        }

        @Test("alpha() defaults to 1, and setAlpha() clamps to 0...1 and chains")
        func alphaRoundTrip() {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})")
            #expect(harness.evalDouble("c.alpha()") == 1)
            #expect(harness.evalDouble("c.setAlpha(0.25).alpha()") == 0.25)
            #expect(harness.evalDouble("c.setAlpha(3).alpha()") == 1)
            #expect(harness.evalDouble("c.setAlpha(-1).alpha()") == 0)
            #expect(!harness.hasException)
        }

        @Test("setAlpha() with no number leaves the opacity alone")
        func alphaIgnoresMissingValue() {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).setAlpha(0.5); c.setAlpha()")
            #expect(harness.evalDouble("c.alpha()") == 0.5)
            #expect(!harness.hasException)
        }

        @Test("setAlpha() applies to a shown window straight away")
        func alphaAppliesToShownWindow() {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}); c.show(); c.setAlpha(0.4)")
            #expect(canvas(harness)?.windowAlphaValue == 0.4)
            harness.eval("c.destroy()")
        }

        @Test("show() with no fade time shows the canvas immediately at its alpha")
        func showWithoutFade() {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).setAlpha(0.6).show()")
            #expect(harness.evalBool("c.isShowing()") == true)
            #expect(canvas(harness)?.windowAlphaValue == 0.6)
            harness.eval("c.hide(); c.destroy()")
            #expect(!harness.hasException)
        }

        @Test("show(t) fades the window in from transparent to the canvas's alpha")
        func showFadesIn() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).setAlpha(0.8).show(0.1)")
            let c = canvas(harness)
            #expect(harness.evalBool("c.isShowing()") == true)
            #expect((c?.windowAlphaValue ?? 1) < 0.8, "A fade-in must start below the target alpha")
            #expect(await harness.waitForAsync(timeout: 1.0) { c?.windowAlphaValue == 0.8 })
            harness.eval("c.destroy()")
        }

        @Test("hide(t) keeps the canvas showing until the fade ends, then restores its alpha")
        func hideFadesOut() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).setAlpha(0.5).show(); c.hide(0.1)")
            let c = canvas(harness)
            #expect(harness.evalBool("c.isShowing()") == true, "The canvas stays on screen while it fades")
            #expect(await harness.waitForAsync(timeout: 1.0) { c?.isShowing() == false })
            #expect(c?.windowAlphaValue == 0.5, "The next show() must come back at the canvas's alpha")
            #expect(harness.evalDouble("c.alpha()") == 0.5)
            harness.eval("c.destroy()")
        }

        @Test("show() during a fade-out cancels it, and the canvas stays shown at its alpha")
        func showCancelsFadeOut() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).setAlpha(0.5).show(); c.hide(0.1); c.show()")
            let c = canvas(harness)
            try? await Task.sleep(for: .milliseconds(300))
            #expect(c?.isShowing() == true, "The cancelled fade-out must not hide the canvas")
            #expect(c?.windowAlphaValue == 0.5)
            harness.eval("c.destroy()")
        }

        @Test("show(t) during a fade-out fades back in to the canvas's alpha, not to 0")
        func fadeInDuringFadeOut() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).setAlpha(0.7).show(); c.hide(0.2)")
            let c = canvas(harness)
            try? await Task.sleep(for: .milliseconds(50))
            harness.eval("c.show(0.05)")
            try? await Task.sleep(for: .milliseconds(400))
            #expect(c?.isShowing() == true)
            #expect(c?.windowAlphaValue == 0.7)
            harness.eval("c.destroy()")
        }

        @Test("hide() during a fade-in hides at once, and the next show() is at the canvas's alpha")
        func hideDuringFadeIn() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).setAlpha(0.9).show(0.2); c.hide()")
            let c = canvas(harness)
            #expect(c?.isShowing() == false)
            try? await Task.sleep(for: .milliseconds(300))
            harness.eval("c.show()")
            #expect(c?.windowAlphaValue == 0.9)
            harness.eval("c.destroy()")
        }

        @Test("setAlpha() during a fade-out lets the fade finish, and the next show() uses the new opacity")
        func setAlphaDuringFadeOut() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).show(); c.hide(0.2); c.setAlpha(0.3)")
            let c = canvas(harness)
            #expect(c?.isShowing() == true, "Changing the opacity doesn't cut the fade-out short")
            #expect(await harness.waitForAsync(timeout: 1.0) { c?.isShowing() == false })
            harness.eval("c.show()")
            #expect(c?.windowAlphaValue == 0.3)
            harness.eval("c.destroy()")
        }

        @Test("setAlpha() during a fade-in jumps to the new opacity and keeps it after the fade would have ended")
        func setAlphaDuringFadeIn() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).show(0.2); c.setAlpha(0.3)")
            let c = canvas(harness)
            #expect(c?.windowAlphaValue == 0.3)
            try? await Task.sleep(for: .milliseconds(300))
            #expect(c?.windowAlphaValue == 0.3)
            #expect(c?.isShowing() == true)
            harness.eval("c.destroy()")
        }

        @Test("destroy(t) fades out before tearing the window down")
        func destroyFadesOut() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).show(); c.destroy(0.1)")
            let c = canvas(harness)
            #expect(c?.isShowing() == true, "The canvas stays on screen while it fades")
            #expect(await harness.waitForAsync(timeout: 1.0) { c?.isShowing() == false })
            #expect(c?.windowAlphaValue == nil, "The window is released once the fade ends")
        }

        @Test("show() during a destroy(t) fade throws, and the canvas is still destroyed when the fade ends")
        func showDuringDestroyFadeThrows() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).show(); c.destroy(0.1)")
            let c = canvas(harness)

            harness.eval("c.show()")
            #expect(harness.exceptionMessage?.contains("destroyed") == true)
            #expect(await harness.waitForAsync(timeout: 1.0) { c?.windowAlphaValue == nil })
            #expect(c?.isShowing() == false)
        }

        @Test("hide() during a destroy(t) fade doesn't stop the canvas being destroyed")
        func hideDuringDestroyFade() async {
            let harness = makeHarness()
            harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).show(); c.destroy(0.1); c.hide()")
            let c = canvas(harness)
            #expect(!harness.hasException)
            #expect(c?.isShowing() == true, "hide() must not cut the destroy fade short")
            #expect(await harness.waitForAsync(timeout: 1.0) { c?.windowAlphaValue == nil })
        }

        @Test("A canvas fading out that nobody references stays alive until the fade ends, then is collected")
        func fadingCanvasLifetime() async {
            let harness = makeHarness()
            weak var c: HSCanvas?
            autoreleasepool {
                harness.eval("var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50}).show(); c.hide(0.2); void 0")
                c = canvas(harness)
                harness.eval("c = null; void 0")
            }
            harness.collectGarbage()
            #expect(c?.isShowing() == true, "A fading canvas must not be collected mid-fade")

            #expect(await harness.waitForAsync(timeout: 1.0) { c?.isShowing() != true })
            harness.collectGarbage()
            #expect(c == nil, "A canvas that has faded out and that nobody references must be collected")
        }
    }

    // MARK: - Garbage collection (issue #267)

    @Test("A shown canvas the caller didn't keep stays on screen after garbage collection, and is collected once hidden")
    @MainActor
    func testShownCanvasLifetime() {
        let harness = JSTestHarness()
        harness.loadModule(HSCanvasModule.self, as: "canvas")

        weak var canvas: HSCanvas?
        autoreleasepool {
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 50, h: 50})
                c.appendElements([{ type: "rectangle", action: "fill", fillColor: { alpha: 1 } }])
                c.mouseCallback(() => {})
                c.show()
                void 0
            """)
            canvas = harness.evalValue("c")?.toObjectOf(HSCanvas.self) as? HSCanvas
            harness.eval("c = null; void 0")
        }
        harness.collectGarbage()
        #expect(canvas?.isShowing() == true, "A shown canvas must not be collected")

        _ = canvas?.hide(0)
        harness.collectGarbage()
        #expect(canvas == nil, "A hidden canvas nobody references must not be kept alive")
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
            // show() makes the canvas active in the module's tracker, which keeps it alive
            // even after the JS reference is dropped. shutdown() calls destroy() on each
            // canvas and then removeAllObjects(), releasing it.
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

    @Test("shutdown() with multiple shown canvases destroys all of them without trapping")
    @MainActor
    func testShutdownWithMultipleCanvases() {
        // Regression test: HSCanvasModule.shutdown() used to iterate its canvas dictionary
        // directly while each canvas.destroy() call synchronously mutated it -- mutating a
        // Dictionary while enumerating it traps at runtime. A single canvas doesn't reliably
        // exercise this; several do.
        let trackers = (0..<5).map { _ in WeakLeakTracker() }
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            harness.eval("""
                var canvases = []
                for (var i = 0; i < 5; i++) {
                    var c = hs.canvas.create({x: i * 10, y: 0, w: 50, h: 50})
                    c.appendElements([{ type: "rectangle", action: "fill", fillColor: { alpha: 1 } }])
                    c.show()
                    canvases.push(c)
                }
            """)
            for (index, tracker) in trackers.enumerated() {
                if let obj = harness.evalValue("canvases[\(index)]")?.toObjectOf(HSCanvas.self) as? HSCanvas {
                    tracker.track(obj)
                }
            }
            harness.eval("canvases = null")
            harness.shutdownForLeakTest()
        }
        for tracker in trackers {
            tracker.assertNoLeaks(timeout: 1.0)
        }
    }
}
