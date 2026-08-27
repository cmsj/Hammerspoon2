//
//  BridgeTypesTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 06/11/2025.
//

import Testing
import JavaScriptCore
import CoreGraphics
@testable import Hammerspoon_2

/// Tests for JavaScript bridge types (HSPoint, HSSize, HSRect)
///
/// These types allow JavaScript code to work with CoreGraphics types
/// in a JavaScript-friendly way.
@Suite("Bridged type tests")
struct BridgeTypesTests {

    // MARK: - HSPoint Tests

    @Test("HSPoint can be constructed from JavaScript")
    func testHSPointConstruction() {
        let harness = JSTestHarness()

        harness.eval("var point = new HSPoint(10, 20)")

        harness.expectEqual("point.x", 10.0)
        harness.expectEqual("point.y", 20.0)
    }

    @Test("HSPoint properties can be modified")
    func testHSPointModification() {
        let harness = JSTestHarness()

        harness.eval("""
        var point = new HSPoint(10, 20);
        point.x = 30;
        point.y = 40;
        """)

        harness.expectEqual("point.x", 30.0)
        harness.expectEqual("point.y", 40.0)
    }

    @Test("HSPoint can be passed to and from Swift")
    func testHSPointBridging() {
        let harness = JSTestHarness()

        // Create a Swift CGPoint and convert to HSPoint
        let cgPoint = CGPoint(x: 100, y: 200)
        let hsPoint = cgPoint.toBridge()
        harness.context.setObject(hsPoint, forKeyedSubscript: "swiftPoint" as NSString)

        // Verify JavaScript can read it
        harness.expectEqual("swiftPoint.x", 100.0)
        harness.expectEqual("swiftPoint.y", 200.0)

        // Modify in JavaScript
        harness.eval("swiftPoint.x = 150")

        // Verify Swift can read the change
        let modifiedPoint = CGPoint(from: hsPoint)
        #expect(modifiedPoint.x == 150)
        #expect(modifiedPoint.y == 200)
    }

    // MARK: - HSSize Tests

    @Test("HSSize can be constructed from JavaScript")
    func testHSSizeConstruction() {
        let harness = JSTestHarness()

        harness.eval("var size = new HSSize(100, 200)")

        harness.expectEqual("size.w", 100.0)
        harness.expectEqual("size.h", 200.0)
    }

    @Test("HSSize properties can be modified")
    func testHSSizeModification() {
        let harness = JSTestHarness()

        harness.eval("""
        var size = new HSSize(100, 200);
        size.w = 300;
        size.h = 400;
        """)

        harness.expectEqual("size.w", 300.0)
        harness.expectEqual("size.h", 400.0)
    }

    @Test("HSSize can be passed to and from Swift")
    func testHSSizeBridging() {
        let harness = JSTestHarness()

        // Create a Swift CGSize and convert to HSSize
        let cgSize = CGSize(width: 640, height: 480)
        let hsSize = cgSize.toBridge()
        harness.context.setObject(hsSize, forKeyedSubscript: "swiftSize" as NSString)

        // Verify JavaScript can read it
        harness.expectEqual("swiftSize.w", 640.0)
        harness.expectEqual("swiftSize.h", 480.0)

        // Modify in JavaScript
        harness.eval("swiftSize.h = 720")

        // Verify Swift can read the change
        let modifiedSize = CGSize(from: hsSize)
        #expect(modifiedSize.width == 640)
        #expect(modifiedSize.height == 720)
    }

    // MARK: - HSRect Tests

    @Test("HSRect can be constructed from JavaScript")
    func testHSRectConstruction() {
        let harness = JSTestHarness()

        harness.eval("var rect = new HSRect(10, 20, 100, 200)")

        harness.expectEqual("rect.x", 10.0)
        harness.expectEqual("rect.y", 20.0)
        harness.expectEqual("rect.w", 100.0)
        harness.expectEqual("rect.h", 200.0)
    }

    @Test("HSRect properties can be modified")
    func testHSRectModification() {
        let harness = JSTestHarness()

        harness.eval("""
        var rect = new HSRect(10, 20, 100, 200);
        rect.x = 30;
        rect.y = 40;
        rect.w = 300;
        rect.h = 400;
        """)

        harness.expectEqual("rect.x", 30.0)
        harness.expectEqual("rect.y", 40.0)
        harness.expectEqual("rect.w", 300.0)
        harness.expectEqual("rect.h", 400.0)
    }

    @Test("HSRect origin property works correctly")
    func testHSRectOrigin() {
        let harness = JSTestHarness()

        harness.eval("""
        var rect = new HSRect(10, 20, 100, 200);
        var origin = rect.origin;
        """)

        harness.expectEqual("origin.x", 10.0)
        harness.expectEqual("origin.y", 20.0)
        harness.expectTrue("origin instanceof HSPoint")

        // Modify origin and check rect updates
        harness.eval("""
        rect.origin = new HSPoint(50, 60);
        """)

        harness.expectEqual("rect.x", 50.0)
        harness.expectEqual("rect.y", 60.0)
    }

    @Test("HSRect size property works correctly")
    func testHSRectSize() {
        let harness = JSTestHarness()

        harness.eval("""
        var rect = new HSRect(10, 20, 100, 200);
        var size = rect.size;
        """)

        harness.expectEqual("size.w", 100.0)
        harness.expectEqual("size.h", 200.0)
        harness.expectTrue("size instanceof HSSize")

        // Modify size and check rect updates
        harness.eval("""
        rect.size = new HSSize(300, 400);
        """)

        harness.expectEqual("rect.w", 300.0)
        harness.expectEqual("rect.h", 400.0)
    }

    @Test("HSRect can be passed to and from Swift")
    func testHSRectBridging() {
        let harness = JSTestHarness()

        // Create a Swift CGRect and convert to HSRect
        let cgRect = CGRect(x: 10, y: 20, width: 100, height: 200)
        let hsRect = cgRect.toBridge()
        harness.context.setObject(hsRect, forKeyedSubscript: "swiftRect" as NSString)

        // Verify JavaScript can read it
        harness.expectEqual("swiftRect.x", 10.0)
        harness.expectEqual("swiftRect.y", 20.0)
        harness.expectEqual("swiftRect.w", 100.0)
        harness.expectEqual("swiftRect.h", 200.0)

        // Modify in JavaScript
        harness.eval("""
        swiftRect.x = 15;
        swiftRect.w = 150;
        """)

        // Verify Swift can read the changes
        let modifiedRect = CGRect(from: hsRect)
        #expect(modifiedRect.origin.x == 15)
        #expect(modifiedRect.origin.y == 20)
        #expect(modifiedRect.size.width == 150)
        #expect(modifiedRect.size.height == 200)
    }

    // MARK: - Integration Tests

    @Test("Bridge types work in function calls")
    func testBridgeTypesInFunctionCalls() {
        let harness = JSTestHarness()

        var receivedPoint: CGPoint?
        var receivedSize: CGSize?
        var receivedRect: CGRect?

        // Register a function that accepts these types
        let testFunc: @convention(block) (HSPoint, HSSize, HSRect) -> Void = { point, size, rect in
            receivedPoint = CGPoint(from: point)
            receivedSize = CGSize(from: size)
            receivedRect = CGRect(from: rect)
        }
        harness.context.setObject(testFunc, forKeyedSubscript: "testBridgeTypes" as NSString)

        // Call from JavaScript
        harness.eval("""
        var p = new HSPoint(10, 20);
        var s = new HSSize(100, 200);
        var r = new HSRect(5, 10, 50, 100);
        testBridgeTypes(p, s, r);
        """)

        // Verify Swift received the correct values
        #expect(receivedPoint?.x == 10)
        #expect(receivedPoint?.y == 20)
        #expect(receivedSize?.width == 100)
        #expect(receivedSize?.height == 200)
        #expect(receivedRect?.origin.x == 5)
        #expect(receivedRect?.origin.y == 10)
        #expect(receivedRect?.size.width == 50)
        #expect(receivedRect?.size.height == 100)
    }

    @Test("Bridge types can be returned from functions")
    func testBridgeTypesAsReturnValues() {
        let harness = JSTestHarness()

        // Register functions that return bridge types
        let makePoint: @convention(block) () -> HSPoint = {
            HSPoint(x: 42, y: 84)
        }
        let makeSize: @convention(block) () -> HSSize = {
            HSSize(w: 640, h: 480)
        }
        let makeRect: @convention(block) () -> HSRect = {
            HSRect(x: 0, y: 0, w: 1920, h: 1080)
        }

        harness.context.setObject(makePoint, forKeyedSubscript: "makePoint" as NSString)
        harness.context.setObject(makeSize, forKeyedSubscript: "makeSize" as NSString)
        harness.context.setObject(makeRect, forKeyedSubscript: "makeRect" as NSString)

        // Call from JavaScript and verify
        harness.eval("""
        var p = makePoint();
        var s = makeSize();
        var r = makeRect();
        """)

        harness.expectEqual("p.x", 42.0)
        harness.expectEqual("p.y", 84.0)
        harness.expectEqual("s.w", 640.0)
        harness.expectEqual("s.h", 480.0)
        harness.expectEqual("r.x", 0.0)
        harness.expectEqual("r.y", 0.0)
        harness.expectEqual("r.w", 1920.0)
        harness.expectEqual("r.h", 1080.0)
    }

    @Test("Bridge types maintain identity across calls")
    func testBridgeTypeIdentity() {
        let harness = JSTestHarness()

        harness.eval("""
        var rect1 = new HSRect(10, 20, 100, 200);
        var rect2 = rect1;
        rect2.x = 50;
        """)

        // Both should reference the same object
        harness.expectEqual("rect1.x", 50.0)
        harness.expectEqual("rect2.x", 50.0)
        harness.expectTrue("rect1 === rect2")
    }

    @Test("Bridge types can be used in arrays")
    func testBridgeTypesInArrays() {
        let harness = JSTestHarness()

        harness.eval("""
        var points = [
            new HSPoint(0, 0),
            new HSPoint(10, 10),
            new HSPoint(20, 20)
        ];
        """)

        harness.expectEqual("points.length", 3)
        harness.expectEqual("points[0].x", 0.0)
        harness.expectEqual("points[1].x", 10.0)
        harness.expectEqual("points[2].x", 20.0)

        // Modify through array
        harness.eval("points[1].y = 15")
        harness.expectEqual("points[1].y", 15.0)
    }

    @Test("Bridge types work in object literals")
    func testBridgeTypesInObjects() {
        let harness = JSTestHarness()

        harness.eval("""
        var window = {
            frame: new HSRect(100, 200, 800, 600),
            minSize: new HSSize(400, 300),
            maxSize: new HSSize(1920, 1080)
        };
        """)

        harness.expectEqual("window.frame.x", 100.0)
        harness.expectEqual("window.frame.w", 800.0)
        harness.expectEqual("window.minSize.w", 400.0)
        harness.expectEqual("window.maxSize.h", 1080.0)
    }

    @Test("Fractional coordinates work correctly")
    func testFractionalCoordinates() {
        let harness = JSTestHarness()

        harness.eval("""
        var point = new HSPoint(10.5, 20.75);
        var size = new HSSize(100.25, 200.5);
        var rect = new HSRect(5.1, 10.2, 50.3, 100.4);
        """)

        harness.expectEqual("point.x", 10.5)
        harness.expectEqual("point.y", 20.75)
        harness.expectEqual("size.w", 100.25)
        harness.expectEqual("size.h", 200.5)
        harness.expectEqual("rect.x", 5.1)
        harness.expectEqual("rect.h", 100.4)
    }

    @Test("Negative coordinates work correctly")
    func testNegativeCoordinates() {
        let harness = JSTestHarness()

        harness.eval("""
        var point = new HSPoint(-10, -20);
        var rect = new HSRect(-5, -10, 100, 200);
        """)

        harness.expectEqual("point.x", -10.0)
        harness.expectEqual("point.y", -20.0)
        harness.expectEqual("rect.x", -5.0)
        harness.expectEqual("rect.y", -10.0)
    }

    @Test("Zero-sized rect works correctly")
    func testZeroSizedRect() {
        let harness = JSTestHarness()

        harness.eval("var rect = new HSRect(10, 20, 0, 0)")

        harness.expectEqual("rect.w", 0.0)
        harness.expectEqual("rect.h", 0.0)
        harness.expectEqual("rect.x", 10.0)
        harness.expectEqual("rect.y", 20.0)
    }

    @Test("Very large coordinates work correctly")
    func testLargeCoordinates() {
        let harness = JSTestHarness()

        harness.eval("""
        var point = new HSPoint(10000, 20000);
        var size = new HSSize(99999, 88888);
        """)

        harness.expectEqual("point.x", 10000.0)
        harness.expectEqual("size.w", 99999.0)
    }

    // MARK: - HSPoint Geometry Method Tests

    @Test("HSPoint angle() returns the angle from the positive x axis")
    func testHSPointAngle() throws {
        let harness = JSTestHarness()
        #expect(harness.evalDouble("new HSPoint(1, 0).angle()") == 0.0)
        let angle = try #require(harness.evalDouble("new HSPoint(0, 1).angle()"))
        #expect(abs(angle - .pi / 2) < 0.0001)
    }

    @Test("HSPoint angleTo() measures the angle to another point or rect's center")
    func testHSPointAngleTo() throws {
        let harness = JSTestHarness()
        let toPoint = try #require(harness.evalDouble("new HSPoint(0, 0).angleTo(new HSPoint(1, 1))"))
        #expect(abs(toPoint - .pi / 4) < 0.0001)

        let toRect = try #require(harness.evalDouble("new HSPoint(0, 0).angleTo(new HSRect(0, 0, 2, 2))"))
        #expect(abs(toRect - .pi / 4) < 0.0001)

        #expect(harness.evalDouble("new HSPoint(0, 0).angleTo(42)") == 0.0)
    }

    @Test("HSPoint distance() measures distance to another point or rect's center")
    func testHSPointDistance() {
        let harness = JSTestHarness()
        #expect(harness.evalDouble("new HSPoint(0, 0).distance(new HSPoint(3, 4))") == 5.0)
        #expect(harness.evalDouble("new HSPoint(0, 0).distance(new HSRect(2, 3, 2, 2))") == 5.0)
        #expect(harness.evalDouble("new HSPoint(0, 0).distance('nope')") == 0.0)
    }

    @Test("HSPoint equals() compares coordinates")
    func testHSPointEquals() {
        let harness = JSTestHarness()
        #expect(harness.evalBool("new HSPoint(1, 2).equals(new HSPoint(1, 2))") == true)
        #expect(harness.evalBool("new HSPoint(1, 2).equals(new HSPoint(1, 3))") == false)
    }

    @Test("HSPoint floor() truncates towards negative infinity")
    func testHSPointFloor() {
        let harness = JSTestHarness()
        harness.eval("var p = new HSPoint(1.7, -1.2).floor()")
        #expect(harness.evalDouble("p.x") == 1.0)
        #expect(harness.evalDouble("p.y") == -2.0)
    }

    @Test("HSPoint inside() checks containment within a rect")
    func testHSPointInside() {
        let harness = JSTestHarness()
        #expect(harness.evalBool("new HSPoint(5, 5).inside(new HSRect(0, 0, 10, 10))") == true)
        #expect(harness.evalBool("new HSPoint(15, 5).inside(new HSRect(0, 0, 10, 10))") == false)
    }

    @Test("HSPoint move() offsets by a point or size")
    func testHSPointMove() {
        let harness = JSTestHarness()
        harness.eval("var p1 = new HSPoint(1, 1).move(new HSPoint(2, 3))")
        #expect(harness.evalDouble("p1.x") == 3.0)
        #expect(harness.evalDouble("p1.y") == 4.0)

        harness.eval("var p2 = new HSPoint(1, 1).move(new HSSize(2, 3))")
        #expect(harness.evalDouble("p2.x") == 3.0)
        #expect(harness.evalDouble("p2.y") == 4.0)

        harness.eval("var p3 = new HSPoint(1, 1).move('nope')")
        #expect(harness.evalDouble("p3.x") == 1.0)
        #expect(harness.evalDouble("p3.y") == 1.0)
    }

    @Test("HSPoint normalize() produces a unit-length vector")
    func testHSPointNormalize() throws {
        let harness = JSTestHarness()
        harness.eval("var n = new HSPoint(3, 4).normalize()")
        #expect(abs(try #require(harness.evalDouble("n.x")) - 0.6) < 0.0001)
        #expect(abs(try #require(harness.evalDouble("n.y")) - 0.8) < 0.0001)

        harness.eval("var zero = new HSPoint(0, 0).normalize()")
        #expect(harness.evalDouble("zero.x") == 0.0)
        #expect(harness.evalDouble("zero.y") == 0.0)
    }

    @Test("HSPoint rotateCCW() rotates around another point")
    func testHSPointRotateCCW() throws {
        let harness = JSTestHarness()
        harness.eval("var r1 = new HSPoint(1, 0).rotateCCW(new HSPoint(0, 0), 1)")
        #expect(abs(try #require(harness.evalDouble("r1.x")) - 0.0) < 0.0001)
        #expect(abs(try #require(harness.evalDouble("r1.y")) - 1.0) < 0.0001)

        harness.eval("var r2 = new HSPoint(1, 0).rotateCCW(new HSPoint(0, 0), 2)")
        #expect(abs(try #require(harness.evalDouble("r2.x")) - (-1.0)) < 0.0001)
        #expect(abs(try #require(harness.evalDouble("r2.y")) - 0.0) < 0.0001)
    }

    @Test("HSPoint scale() scales uniformly or per-axis")
    func testHSPointScale() {
        let harness = JSTestHarness()
        harness.eval("var s1 = new HSPoint(2, 3).scale(2)")
        #expect(harness.evalDouble("s1.x") == 4.0)
        #expect(harness.evalDouble("s1.y") == 6.0)

        harness.eval("var s2 = new HSPoint(2, 3).scale(new HSSize(2, 3))")
        #expect(harness.evalDouble("s2.x") == 4.0)
        #expect(harness.evalDouble("s2.y") == 9.0)
    }

    @Test("HSPoint vector() returns the displacement to another point or rect's center")
    func testHSPointVector() {
        let harness = JSTestHarness()
        harness.eval("var v = new HSPoint(1, 1).vector(new HSPoint(4, 5))")
        #expect(harness.evalDouble("v.x") == 3.0)
        #expect(harness.evalDouble("v.y") == 4.0)
    }

    // MARK: - HSSize Geometry Method Tests

    @Test("HSSize angle() treats width/height as a vector")
    func testHSSizeAngle() throws {
        let harness = JSTestHarness()
        #expect(harness.evalDouble("new HSSize(1, 0).angle()") == 0.0)
        let angle = try #require(harness.evalDouble("new HSSize(0, 1).angle()"))
        #expect(abs(angle - .pi / 2) < 0.0001)
    }

    @Test("HSSize equals() compares width and height")
    func testHSSizeEquals() {
        let harness = JSTestHarness()
        #expect(harness.evalBool("new HSSize(10, 20).equals(new HSSize(10, 20))") == true)
        #expect(harness.evalBool("new HSSize(10, 20).equals(new HSSize(10, 21))") == false)
    }

    @Test("HSSize floor() truncates towards negative infinity")
    func testHSSizeFloor() {
        let harness = JSTestHarness()
        harness.eval("var s = new HSSize(10.9, -20.1).floor()")
        #expect(harness.evalDouble("s.w") == 10.0)
        #expect(harness.evalDouble("s.h") == -21.0)
    }

    @Test("HSSize scale() scales uniformly or per-axis")
    func testHSSizeScale() {
        let harness = JSTestHarness()
        harness.eval("var s1 = new HSSize(10, 20).scale(2)")
        #expect(harness.evalDouble("s1.w") == 20.0)
        #expect(harness.evalDouble("s1.h") == 40.0)

        harness.eval("var s2 = new HSSize(10, 20).scale('nope')")
        #expect(harness.evalDouble("s2.w") == 10.0)
        #expect(harness.evalDouble("s2.h") == 20.0)
    }

    // MARK: - HSRect Geometry Method Tests

    @Test("HSRect angleTo(), distance() and vector() use the rect's center")
    func testHSRectCenterMethods() throws {
        let harness = JSTestHarness()
        harness.eval("var r = new HSRect(0, 0, 2, 2)") // center is (1, 1)

        let angle = try #require(harness.evalDouble("r.angleTo(new HSPoint(2, 2))"))
        #expect(abs(angle - .pi / 4) < 0.0001)

        #expect(harness.evalDouble("r.distance(new HSPoint(4, 5))") == 5.0)

        harness.eval("var v = r.vector(new HSPoint(4, 5))")
        #expect(harness.evalDouble("v.x") == 3.0)
        #expect(harness.evalDouble("v.y") == 4.0)
    }

    @Test("HSRect equals() compares origin and size")
    func testHSRectEquals() {
        let harness = JSTestHarness()
        #expect(harness.evalBool("new HSRect(0, 0, 10, 10).equals(new HSRect(0, 0, 10, 10))") == true)
        #expect(harness.evalBool("new HSRect(0, 0, 10, 10).equals(new HSRect(0, 0, 10, 11))") == false)
    }

    @Test("HSRect fit() preserves aspect ratio when shrinking to bounds")
    func testHSRectFitShrinks() {
        let harness = JSTestHarness()
        harness.eval("var f = new HSRect(0, 0, 200, 100).fit(new HSRect(0, 0, 100, 100))")
        #expect(harness.evalDouble("f.w") == 100.0)
        #expect(harness.evalDouble("f.h") == 50.0)
    }

    @Test("HSRect fit() leaves a rect unchanged if it already fits")
    func testHSRectFitAlreadyFits() {
        let harness = JSTestHarness()
        harness.eval("var f = new HSRect(10, 10, 50, 50).fit(new HSRect(0, 0, 100, 100))")
        #expect(harness.evalDouble("f.x") == 10.0)
        #expect(harness.evalDouble("f.y") == 10.0)
        #expect(harness.evalDouble("f.w") == 50.0)
        #expect(harness.evalDouble("f.h") == 50.0)
    }

    @Test("HSRect fit() repositions a rect that overflows bounds")
    func testHSRectFitRepositions() {
        let harness = JSTestHarness()
        harness.eval("var f = new HSRect(50, 50, 50, 50).fit(new HSRect(0, 0, 100, 100))")
        #expect(harness.evalDouble("f.x") == 50.0)
        #expect(harness.evalDouble("f.y") == 50.0)
        #expect(harness.evalDouble("f.w") == 50.0)
        #expect(harness.evalDouble("f.h") == 50.0)

        harness.eval("var f2 = new HSRect(80, 80, 50, 50).fit(new HSRect(0, 0, 100, 100))")
        #expect(harness.evalDouble("f2.x") == 50.0)
        #expect(harness.evalDouble("f2.y") == 50.0)
    }

    @Test("HSRect floor() truncates towards negative infinity")
    func testHSRectFloor() {
        let harness = JSTestHarness()
        harness.eval("var r = new HSRect(1.7, 1.2, 10.9, 10.1).floor()")
        #expect(harness.evalDouble("r.x") == 1.0)
        #expect(harness.evalDouble("r.y") == 1.0)
        #expect(harness.evalDouble("r.w") == 10.0)
        #expect(harness.evalDouble("r.h") == 10.0)
    }

    @Test("HSRect fromUnitRect() converts normalized coordinates into a frame")
    func testHSRectFromUnitRect() {
        let harness = JSTestHarness()
        harness.eval("var r = new HSRect(0.5, 0.5, 0.5, 0.5).fromUnitRect(new HSRect(0, 0, 100, 100))")
        #expect(harness.evalDouble("r.x") == 50.0)
        #expect(harness.evalDouble("r.y") == 50.0)
        #expect(harness.evalDouble("r.w") == 50.0)
        #expect(harness.evalDouble("r.h") == 50.0)
    }

    @Test("HSRect inside() checks full containment within another rect")
    func testHSRectInside() {
        let harness = JSTestHarness()
        #expect(harness.evalBool("new HSRect(1, 1, 5, 5).inside(new HSRect(0, 0, 10, 10))") == true)
        #expect(harness.evalBool("new HSRect(5, 5, 10, 10).inside(new HSRect(0, 0, 10, 10))") == false)
    }

    @Test("HSRect intersect() returns the overlapping area")
    func testHSRectIntersect() {
        let harness = JSTestHarness()
        harness.eval("var r = new HSRect(0, 0, 10, 10).intersect(new HSRect(5, 5, 10, 10))")
        #expect(harness.evalDouble("r.x") == 5.0)
        #expect(harness.evalDouble("r.y") == 5.0)
        #expect(harness.evalDouble("r.w") == 5.0)
        #expect(harness.evalDouble("r.h") == 5.0)

        harness.eval("var empty = new HSRect(0, 0, 5, 5).intersect(new HSRect(20, 20, 5, 5))")
        #expect(harness.evalDouble("empty.w") == 0.0)
        #expect(harness.evalDouble("empty.h") == 0.0)
    }

    @Test("HSRect move() offsets the origin, keeping size constant")
    func testHSRectMove() {
        let harness = JSTestHarness()
        harness.eval("var r = new HSRect(0, 0, 10, 10).move(new HSPoint(5, 5))")
        #expect(harness.evalDouble("r.x") == 5.0)
        #expect(harness.evalDouble("r.y") == 5.0)
        #expect(harness.evalDouble("r.w") == 10.0)
        #expect(harness.evalDouble("r.h") == 10.0)
    }

    @Test("HSRect scale() scales size while keeping the center constant")
    func testHSRectScale() {
        let harness = JSTestHarness()
        harness.eval("var r = new HSRect(0, 0, 10, 10).scale(2)")
        #expect(harness.evalDouble("r.x") == -5.0)
        #expect(harness.evalDouble("r.y") == -5.0)
        #expect(harness.evalDouble("r.w") == 20.0)
        #expect(harness.evalDouble("r.h") == 20.0)

        harness.eval("var unchanged = new HSRect(0, 0, 10, 10).scale(-1)")
        #expect(harness.evalDouble("unchanged.w") == 10.0)
        #expect(harness.evalDouble("unchanged.h") == 10.0)
    }

    @Test("HSRect toUnitRect() normalizes coordinates within a frame")
    func testHSRectToUnitRect() {
        let harness = JSTestHarness()
        harness.eval("var r = new HSRect(50, 50, 50, 50).toUnitRect(new HSRect(0, 0, 100, 100))")
        #expect(harness.evalDouble("r.x") == 0.5)
        #expect(harness.evalDouble("r.y") == 0.5)
        #expect(harness.evalDouble("r.w") == 0.5)
        #expect(harness.evalDouble("r.h") == 0.5)
    }

    @Test("HSRect union() returns the smallest enclosing rect")
    func testHSRectUnion() {
        let harness = JSTestHarness()
        harness.eval("var r = new HSRect(0, 0, 10, 10).union(new HSRect(5, 5, 10, 10))")
        #expect(harness.evalDouble("r.x") == 0.0)
        #expect(harness.evalDouble("r.y") == 0.0)
        #expect(harness.evalDouble("r.w") == 15.0)
        #expect(harness.evalDouble("r.h") == 15.0)
    }
}
