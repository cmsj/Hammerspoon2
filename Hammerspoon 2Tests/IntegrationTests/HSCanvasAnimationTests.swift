//
//  HSCanvasAnimationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
@testable import Hammerspoon_2

/// Tests for `hs.canvas.animate()`. What's drawn is a pure function of time
/// (`CanvasElementStore.presentationElements(at:containerSize:)`), so most of these check the
/// interpolated values at chosen moments rather than waiting for frames.
@Suite("hs.canvas animation tests", .serialized)
struct HSCanvasAnimationTests {
    init() async {
        await JSTestHarness.drainMainActorQueue()
    }

    private static func number(_ raw: Any?) -> Double? {
        (raw as? NSNumber)?.doubleValue
    }

    // MARK: - Curves

    @Suite("Animation curves")
    struct CurveTests {
        @Test("Every named curve starts at 0 and ends at 1")
        func endpoints() {
            for (name, curve) in CanvasAnimationCurve.named {
                #expect(abs(curve.progress(0)) < 0.001, "\(name)")
                #expect(abs(curve.progress(1) - 1) < 0.001, "\(name)")
            }
        }

        @Test("easeIn starts slowly and easeOut starts quickly")
        func easing() {
            #expect(CanvasAnimationCurve.linear.progress(0.25) == 0.25)
            #expect(CanvasAnimationCurve.easeIn.progress(0.25) < 0.25)
            #expect(CanvasAnimationCurve.easeOut.progress(0.25) > 0.25)
            #expect(abs(CanvasAnimationCurve.easeInOut.progress(0.5) - 0.5) < 0.001)
        }

        @Test("Curves parse from names and control points, and reject anything else")
        func parsing() throws {
            #expect(try CanvasAnimationCurve.parse(nil).get() == .easeInOut)
            #expect(try CanvasAnimationCurve.parse("linear").get() == .linear)
            #expect(try CanvasAnimationCurve.parse([0.1, 0.2, 0.3, 1.5]).get()
                == CanvasAnimationCurve(x1: 0.1, y1: 0.2, x2: 0.3, y2: 1.5))
            #expect(throws: CanvasAnimationOptionError.self) { try CanvasAnimationCurve.parse("bouncy").get() }
            #expect(throws: CanvasAnimationOptionError.self) { try CanvasAnimationCurve.parse([0.1, 0.2]).get() }
            #expect(throws: CanvasAnimationOptionError.self) { try CanvasAnimationCurve.parse([2, 0, 0.5, 1]).get() }
        }
    }

    // MARK: - Interpolation

    @Suite("Attribute interpolation")
    struct InterpolationTests {
        private let size = CGSize(width: 200, height: 100)

        private func midpoint(_ key: String, _ from: Any?, _ to: Any?) -> Any? {
            guard let a = CanvasAnimatable.make(from, key: key), let b = CanvasAnimatable.make(to, key: key),
                  a.isCompatible(with: b) else { return nil }
            return CanvasAnimatable.interpolate(a, b, progress: 0.5, axis: .minimum, containerSize: size).rawValue
        }

        @Test("Numbers interpolate")
        func numbers() {
            #expect(HSCanvasAnimationTests.number(midpoint("strokeWidth", 2, 10)) == 6)
        }

        @Test("Percentages interpolate as percentages, and against numbers in points")
        func percentages() throws {
            let frame = try #require(midpoint("frame", ["x": "0%", "y": 0, "w": "100%", "h": 50],
                                              ["x": "50%", "y": 20, "w": 50, "h": 50]) as? [String: Any])
            #expect(frame["x"] as? String == "25.0%")
            #expect(HSCanvasAnimationTests.number(frame["y"]) == 10)
            // "100%" of the 200-wide canvas is 200 points, so halfway to 50 is 125
            #expect(HSCanvasAnimationTests.number(frame["w"]) == 125)
            // A top-level percentage resolves against the smaller dimension, as radius does
            #expect(HSCanvasAnimationTests.number(midpoint("radius", "50%", 10)) == 30)
        }

        @Test("Missing frame keys are filled from the renderer's defaults")
        func frameDefaults() throws {
            let frame = try #require(midpoint("frame", ["w": 100, "h": 100], ["x": 20, "y": 40, "w": 100, "h": 100]) as? [String: Any])
            #expect(HSCanvasAnimationTests.number(frame["x"]) == 10)
            #expect(HSCanvasAnimationTests.number(frame["y"]) == 20)
            // An unset attribute starts from what the renderer draws for it
            #expect(HSCanvasAnimationTests.number(midpoint("rotation", nil, 90)) == 45)
        }

        @Test("Colors interpolate across their forms")
        func colors() throws {
            let color = try #require(midpoint("fillColor", "#000000", ["red": 1, "green": 0.5, "blue": 0, "alpha": 0]) as? [String: Any])
            #expect(abs((HSCanvasAnimationTests.number(color["red"]) ?? 0) - 0.5) < 0.001)
            #expect(abs((HSCanvasAnimationTests.number(color["green"]) ?? 0) - 0.25) < 0.001)
            #expect(abs((HSCanvasAnimationTests.number(color["alpha"]) ?? 0) - 0.5) < 0.001)
        }

        @Test("Values of different shapes, booleans and unlisted keys don't animate")
        func notAnimatable() {
            #expect(midpoint("coordinates", [["x": 0, "y": 0]], [["x": 0, "y": 0], ["x": 1, "y": 1]]) == nil)
            #expect(CanvasAnimatable.make(true, key: "strokeWidth") == nil)
            #expect(CanvasAnimatable.make(5, key: "id") == nil)
            #expect(CanvasAnimatable.make("hello", key: "text") == nil)
        }
    }

    // MARK: - JS API

    @Suite("hs.canvas.animate()")
    struct AnimateTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCanvasModule.self, as: "canvas")
            return harness
        }

        private func canvas(_ harness: JSTestHarness, _ name: String = "c") throws -> HSCanvas {
            try #require(harness.evalValue(name)?.toObjectOf(HSCanvas.self) as? HSCanvas)
        }

        private func setUp(_ harness: JSTestHarness) {
            harness.eval("""
                var c = hs.canvas.create({x: 0, y: 0, w: 200, h: 100});
                c.appendElements([{type: "rectangle", frame: {x: 0, y: 0, w: 20, h: 20}, fillColor: "#FF0000"}]);
            """)
        }

        @Test("Getters return the new value straight away, while the drawn value animates to it")
        func modelAndPresentation() throws {
            let harness = makeHarness()
            setUp(harness)
            let start = Date.now
            harness.eval("""
                var p = hs.canvas.animate({duration: 10, curve: "linear"}, () => {
                    c.setElementAttribute(0, "frame", {x: 100, y: 0, w: 20, h: 20});
                    c.setElementAttribute(0, "text", "changed");
                });
            """)
            #expect(!harness.hasException)
            #expect(harness.evalBool("p instanceof Promise") == true)
            #expect(harness.evalDouble("c.elementAttribute(0, 'frame').x") == 100)

            let canvas = try canvas(harness)
            #expect(canvas.isAnimating)
            let middle = try #require(canvas.presentationElements(at: start.addingTimeInterval(5))[0]["frame"] as? [String: Any])
            let x = try #require(HSCanvasAnimationTests.number(middle["x"]))
            #expect(abs(x - 50) < 1)
            let end = try #require(canvas.presentationElements(at: start.addingTimeInterval(11))[0]["frame"] as? [String: Any])
            #expect(HSCanvasAnimationTests.number(end["x"]) == 100)
            // Attributes that don't animate change immediately
            #expect(canvas.presentationElements(at: start)[0]["text"] as? String == "changed")
        }

        @Test("The promise resolves true once the animation finishes")
        func resolvesTrue() async {
            let harness = makeHarness()
            setUp(harness)
            var result: Bool?
            harness.registerCallback("done") { (finished: Bool) in result = finished }
            harness.eval("""
                hs.canvas.animate({duration: 0.05}, () => c.setElementAttribute(0, "strokeWidth", 5))
                    .then(finished => done(finished));
            """)
            #expect(await harness.waitForAsync(timeout: 2) { result != nil })
            #expect(result == true)
            #expect(harness.evalBool("c.elementAttribute(0, 'strokeWidth') === 5") == true)
        }

        @Test("Changing an animating attribute again interrupts the first animation")
        func interrupted() async throws {
            let harness = makeHarness()
            setUp(harness)
            var results: [String: Bool] = [:]
            harness.registerCallback("first") { (finished: Bool) in results["first"] = finished }
            harness.registerCallback("second") { (finished: Bool) in results["second"] = finished }
            harness.eval("""
                hs.canvas.animate({duration: 0.1}, () => c.setElementAttribute(0, "strokeWidth", 5)).then(first);
                hs.canvas.animate({duration: 0.1}, () => c.setElementAttribute(0, "strokeWidth", 9)).then(second);
            """)
            #expect(await harness.waitForAsync(timeout: 2) { results.count == 2 })
            #expect(results["first"] == false)
            #expect(results["second"] == true)
        }

        @Test("Destroying a canvas interrupts its animations")
        func destroyInterrupts() async {
            let harness = makeHarness()
            setUp(harness)
            var result: Bool?
            harness.registerCallback("done") { (finished: Bool) in result = finished }
            harness.eval("""
                hs.canvas.animate({duration: 0.1}, () => c.setElementAttribute(0, "strokeWidth", 5)).then(done);
                c.destroy();
            """)
            #expect(await harness.waitForAsync(timeout: 2) { result != nil })
            #expect(result == false)
        }

        @Test("A change with nothing to animate resolves straight away")
        func nothingToAnimate() async throws {
            let harness = makeHarness()
            setUp(harness)
            var result: Bool?
            harness.registerCallback("done") { (finished: Bool) in result = finished }
            harness.eval("hs.canvas.animate({duration: 30}, () => c.setElementAttribute(0, 'text', 'x')).then(done)")
            #expect(await harness.waitForAsync(timeout: 1) { result != nil })
            #expect(result == true)
            #expect(try !canvas(harness).isAnimating)
        }

        @Test("A zero duration makes changes without animating them, even inside another animate()")
        func zeroDuration() throws {
            let harness = makeHarness()
            setUp(harness)
            harness.eval("""
                hs.canvas.animate({duration: 30}, () => {
                    hs.canvas.animate({duration: 0}, () => c.setElementAttribute(0, "strokeWidth", 5));
                });
            """)
            #expect(!harness.hasException)
            #expect(try !canvas(harness).isAnimating)
        }

        @Test("A nested animate() uses its own options, and the outer one carries on afterwards")
        func nested() throws {
            let harness = makeHarness()
            setUp(harness)
            let start = Date.now
            harness.eval("""
                hs.canvas.animate({duration: 10, curve: "linear"}, () => {
                    hs.canvas.animate({duration: 20, curve: "linear"}, () => c.setElementAttribute(0, "strokeWidth", 21));
                    c.setElementAttribute(0, "rotation", 100);
                });
            """)
            let element = try canvas(harness).presentationElements(at: start.addingTimeInterval(10))[0]
            #expect(abs((HSCanvasAnimationTests.number(element["strokeWidth"]) ?? 0) - 11) < 0.5)
            #expect(abs((HSCanvasAnimationTests.number(element["rotation"]) ?? 0) - 100) < 0.5)
        }

        @Test("One animate() can animate several canvases")
        func severalCanvases() throws {
            let harness = makeHarness()
            setUp(harness)
            harness.eval("""
                var d = c.duplicate();
                hs.canvas.animate({duration: 10}, () => {
                    c.setElementAttribute(0, "strokeWidth", 5);
                    d.setElementAttribute(0, "strokeWidth", 5);
                });
            """)
            #expect(try canvas(harness).isAnimating)
            #expect(try canvas(harness, "d").isAnimating)
        }

        @Test("An animation follows its element when elements before it are added or removed")
        func identity() throws {
            let harness = makeHarness()
            setUp(harness)
            let start = Date.now
            harness.eval("""
                hs.canvas.animate({duration: 10, curve: "linear"}, () => c.setElementAttribute(0, "rotation", 90));
                c.insertElement({type: "circle"}, 0);
            """)
            let canvas = try canvas(harness)
            var elements = canvas.presentationElements(at: start.addingTimeInterval(5))
            #expect(elements[0]["rotation"] == nil)
            #expect(abs((HSCanvasAnimationTests.number(elements[1]["rotation"]) ?? 0) - 45) < 1)

            harness.eval("c.removeElement(0)")
            elements = canvas.presentationElements(at: start.addingTimeInterval(5))
            #expect(abs((HSCanvasAnimationTests.number(elements[0]["rotation"]) ?? 0) - 45) < 1)

            harness.eval("c.removeElement(0)")
            #expect(!canvas.isAnimating)
        }

        @Test("assignElement() animates each attribute that differs")
        func assignElement() throws {
            let harness = makeHarness()
            setUp(harness)
            let start = Date.now
            harness.eval("""
                hs.canvas.animate({duration: 10, curve: "linear"}, () => {
                    c.assignElement({type: "rectangle", frame: {x: 0, y: 0, w: 60, h: 20}, fillColor: "#0000FF"}, 0);
                });
            """)
            let element = try canvas(harness).presentationElements(at: start.addingTimeInterval(5))[0]
            let frame = try #require(element["frame"] as? [String: Any])
            #expect(abs((HSCanvasAnimationTests.number(frame["w"]) ?? 0) - 40) < 1)
            let color = try #require(element["fillColor"] as? [String: Any])
            #expect(abs((HSCanvasAnimationTests.number(color["blue"]) ?? 0) - 0.5) < 0.02)
        }

        @Test("setTransformation() animates the canvas-wide transform")
        func canvasTransform() throws {
            let harness = makeHarness()
            setUp(harness)
            let start = Date.now
            harness.eval("hs.canvas.animate({duration: 10, curve: 'linear'}, () => c.setTransformation({tX: 100}))")
            let transform = try #require(try canvas(harness).presentationTransform(at: start.addingTimeInterval(5)))
            #expect(abs(transform.tx - 50) < 1)
        }

        @Test("An error in the changes function propagates, and the changes before it still animate")
        func throwingChanges() throws {
            let harness = makeHarness()
            setUp(harness)
            harness.eval("""
                hs.canvas.animate({duration: 10}, () => {
                    c.setElementAttribute(0, "strokeWidth", 5);
                    throw new Error("boom");
                });
            """)
            harness.expectException()
            #expect(try canvas(harness).isAnimating)
            // The animation context was closed despite the error
            harness.eval("c.setElementAttribute(0, 'rotation', 10)")
            let element = try canvas(harness).presentationElements(at: .now)[0]
            #expect(HSCanvasAnimationTests.number(element["rotation"]) == 10)
        }

        @Test("Invalid options and a missing function throw")
        func invalidArguments() {
            for script in [
                "hs.canvas.animate({duration: -1}, () => {})",
                "hs.canvas.animate({duration: 'slow'}, () => {})",
                "hs.canvas.animate({curve: 'wobbly'}, () => {})",
                "hs.canvas.animate({duration: 1})",
            ] {
                let harness = makeHarness()
                harness.eval(script)
                harness.expectException()
            }
        }

        @Test("frame() returns where the window is moving to while it animates")
        func windowFrame() throws {
            let harness = makeHarness()
            harness.eval("""
                var c = hs.canvas.create({x: 100, y: 100, w: 200, h: 100}).show();
                hs.canvas.animate({duration: 10}, () => c.setTopLeft({x: 300, y: 200}));
            """)
            #expect(!harness.hasException)
            #expect(harness.evalDouble("c.frame().x") == 300)
            #expect(harness.evalDouble("c.topLeft().y") == 200)
            // Setting the frame outside animate() replaces the animation
            harness.eval("c.setTopLeft({x: 50, y: 60})")
            #expect(harness.evalDouble("c.frame().x") == 50)
            harness.eval("c.destroy()")
        }
    }

    // MARK: - Lifetime

    @Suite("Animation lifetime")
    struct LifetimeTests {
        @Test("An animating canvas is released after shutdown, with its animation abandoned")
        func testAnimatingCanvasDoesNotLeakAfterReload() {
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = JSTestHarness()
                harness.loadModule(HSCanvasModule.self, as: "canvas")
                harness.eval("""
                    var c = hs.canvas.create({x: 0, y: 0, w: 100, h: 100}).show();
                    c.appendElements([{type: "rectangle", fillColor: "#FF0000"}]);
                    var p = hs.canvas.animate({duration: 30}, () => {
                        c.setElementAttribute(0, "fillColor", "#00FF00");
                        c.setTopLeft({x: 50, y: 50});
                        c.setAlpha(0.5);
                    });
                """)
                if let canvas = harness.evalValue("c")?.toObjectOf(HSCanvas.self) as? HSCanvas {
                    tracker.track(canvas)
                }
                harness.eval("c = null; p = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }
}
