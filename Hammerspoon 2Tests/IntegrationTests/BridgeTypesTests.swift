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
}
