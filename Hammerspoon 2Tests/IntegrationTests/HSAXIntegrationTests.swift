//
//  HSAXIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
import AXSwift
@testable import Hammerspoon_2

private nonisolated func isAccessibilityEnabled() -> Bool {
    return AXIsProcessTrusted()
}

@Suite("hs.ax tests")
struct HSAXTests {

    // MARK: - Suite 1: Module structure (no accessibility permissions required)

    /// Tests that verify the module's API surface is complete and correctly shaped.
    /// These tests do not call the macOS Accessibility API and run in any environment.
    @Suite("hs.ax module structure tests")
    struct HSAXModuleStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSAXModule.self, as: "ax")
            harness.loadModule(HSApplicationModule.self, as: "application")
            return harness
        }

        // MARK: - notificationTypes dictionary

        @Test("notificationTypes is a non-null object")
        func testNotificationTypesIsObject() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.ax.notificationTypes === 'object' && hs.ax.notificationTypes !== null")
        }

        @Test("notificationTypes is non-empty")
        func testNotificationTypesNonEmpty() {
            let harness = makeHarness()
            harness.expectTrue("Object.keys(hs.ax.notificationTypes).length > 0")
        }

        @Test("notificationTypes values all start with AX")
        func testNotificationTypesValuesHaveAXPrefix() {
            let harness = makeHarness()
            harness.expectTrue("Object.values(hs.ax.notificationTypes).every(function(v) { return v.startsWith('AX'); })")
        }

        @Test("notificationTypes keys are camelCase (start with a lowercase letter)")
        func testNotificationTypesKeysAreCamelCase() {
            let harness = makeHarness()
            harness.expectTrue("""
            Object.keys(hs.ax.notificationTypes).every(function(k) {
                return k.length > 0 && k[0] === k[0].toLowerCase() && /[a-z]/.test(k[0]);
            })
        """)
        }

        @Test("notificationTypes['windowCreated'] equals 'AXWindowCreated'")
        func testNotificationTypesWindowCreated() {
            let harness = makeHarness()
            harness.expectEqual("hs.ax.notificationTypes['windowCreated']", "AXWindowCreated")
        }

        @Test("notificationTypes contains focusedUIElementChanged")
        func testNotificationTypesContainsFocusedUIElementChanged() {
            let harness = makeHarness()
            harness.expectTrue("'focusedUIElementChanged' in hs.ax.notificationTypes")
        }

        @Test("notificationTypes contains applicationActivated")
        func testNotificationTypesContainsApplicationActivated() {
            let harness = makeHarness()
            harness.expectTrue("'applicationActivated' in hs.ax.notificationTypes")
        }

        @Test("notificationTypes contains titleChanged")
        func testNotificationTypesContainsTitleChanged() {
            let harness = makeHarness()
            harness.expectTrue("'titleChanged' in hs.ax.notificationTypes")
        }

        @Test("notificationTypes contains valueChanged")
        func testNotificationTypesContainsValueChanged() {
            let harness = makeHarness()
            harness.expectTrue("'valueChanged' in hs.ax.notificationTypes")
        }

        @Test("notificationTypes keys and values form a one-to-one mapping")
        func testNotificationTypesNoDuplicateValues() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var vals = Object.values(hs.ax.notificationTypes);
                return vals.length === new Set(vals).size;
            })()
        """)
        }

        // MARK: - roles dictionary

        @Test("roles is a non-null object")
        func testRolesIsObject() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.ax.roles === 'object' && hs.ax.roles !== null")
        }

        @Test("roles is non-empty")
        func testRolesNonEmpty() {
            let harness = makeHarness()
            harness.expectTrue("Object.keys(hs.ax.roles).length > 0")
        }

        @Test("roles values all start with AX")
        func testRolesValuesHaveAXPrefix() {
            let harness = makeHarness()
            harness.expectTrue("Object.values(hs.ax.roles).every(function(v) { return v.startsWith('AX'); })")
        }

        @Test("roles keys are camelCase (start with a lowercase letter)")
        func testRolesKeysAreCamelCase() {
            let harness = makeHarness()
            harness.expectTrue("""
            Object.keys(hs.ax.roles).every(function(k) {
                return k.length > 0 && k[0] === k[0].toLowerCase() && /[a-z]/.test(k[0]);
            })
        """)
        }

        @Test("roles['button'] equals 'AXButton'")
        func testRolesButton() {
            let harness = makeHarness()
            harness.expectEqual("hs.ax.roles['button']", "AXButton")
        }

        @Test("roles contains textField")
        func testRolesContainsTextField() {
            let harness = makeHarness()
            harness.expectTrue("'textField' in hs.ax.roles")
        }

        @Test("roles contains window")
        func testRolesContainsWindow() {
            let harness = makeHarness()
            harness.expectTrue("'window' in hs.ax.roles")
        }

        @Test("roles contains application")
        func testRolesContainsApplication() {
            let harness = makeHarness()
            harness.expectTrue("'application' in hs.ax.roles")
        }

        @Test("roles keys and values form a one-to-one mapping")
        func testRolesNoDuplicateValues() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var vals = Object.values(hs.ax.roles);
                return vals.length === new Set(vals).size;
            })()
        """)
        }

        // MARK: - Core Swift API presence

        @Test("systemWideElement is a function")
        func testSystemWideElementIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.systemWideElement") == "function")
        }

        @Test("applicationElement is a function")
        func testApplicationElementIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.applicationElement") == "function")
        }

        @Test("windowElement is a function")
        func testWindowElementIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.windowElement") == "function")
        }

        @Test("elementAtPoint is a function")
        func testElementAtPointIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.elementAtPoint") == "function")
        }

        @Test("on is a function")
        func testOnIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.on") == "function")
        }

        @Test("off is a function")
        func testOffIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.off") == "function")
        }

        @Test("once is a function")
        func testOnceIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.once") == "function")
        }

        // MARK: - JS enhancement API presence

        @Test("_watcherEmitter is initialized by hs.ax.js")
        func testWatcherEmitterInitialized() {
            let harness = makeHarness()
            harness.expectTrue("hs.ax._watcherEmitter !== null && hs.ax._watcherEmitter !== undefined")
        }

        @Test("focusedElement is a function")
        func testFocusedElementIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.focusedElement") == "function")
        }

        @Test("findByRole is a function")
        func testFindByRoleIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.findByRole") == "function")
        }

        @Test("findByTitle is a function")
        func testFindByTitleIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.findByTitle") == "function")
        }

        @Test("printHierarchy is a function")
        func testPrintHierarchyIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.printHierarchy") == "function")
        }

        // MARK: - Graceful returns without accessibility permissions

        @Test("systemWideElement returns null when accessibility is not granted")
        func testSystemWideElementNullWithoutAX() {
            guard !isAccessibilityEnabled() else { return }
            let harness = makeHarness()
            let result = harness.evalValue("hs.ax.systemWideElement()")
            #expect(result?.isNull == true || result?.isUndefined == true)
        }

        @Test("elementAtPoint returns null when accessibility is not granted")
        func testElementAtPointNullWithoutAX() {
            guard !isAccessibilityEnabled() else { return }
            let harness = makeHarness()
            // HSPoint-shaped object as argument
            let result = harness.evalValue("hs.ax.elementAtPoint({x: 0, y: 0})")
            #expect(result?.isNull == true || result?.isUndefined == true)
        }
    }

    // MARK: - Suite 2: Element inspection (requires accessibility permissions)

    /// Tests that inspect real AX elements. Uses the Hammerspoon 2 Test App (``TestAppControl``)
    /// as the target application: one copy runs for the whole suite.
    @Suite("hs.ax element inspection tests", .serialized,
           .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"),
           .testApp)
    struct HSAXElementInspectionTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSAXModule.self, as: "ax")
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.eval("var testAppPID = \(TestAppControl.pid ?? -1);")
            TestAppControl.showCurrentTest()
            return harness
        }

        // MARK: - System-wide element

        @Test("systemWideElement returns a non-null object")
        func testSystemWideElementReturnsObject() {
            let harness = makeHarness()
            let result = harness.evalValue("hs.ax.systemWideElement()")
            #expect(result?.isObject == true)
        }

        @Test("systemWideElement role is AXSystemWide")
        func testSystemWideElementRole() {
            let harness = makeHarness()
            harness.expectEqual("hs.ax.systemWideElement().role", "AXSystemWide")
        }

        @Test("systemWideElement pid is a number")
        func testSystemWideElementPid() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.ax.systemWideElement().pid") == "number")
        }

        // MARK: - Application element

        @Test("applicationElement returns non-null for the test app")
        func testApplicationElementNonNull() {
            let harness = makeHarness()
            let result = harness.evalValue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                return app ? hs.ax.applicationElement(app) : null;
            })()
        """)
            #expect(result?.isObject == true)
        }

        @Test("applicationElement role is AXApplication")
        func testApplicationElementRoleIsAXApplication() {
            let harness = makeHarness()
            harness.expectEqual("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem ? elem.role : null;
            })()
        """, "AXApplication")
        }

        @Test("applicationElement title is the application's name")
        func testApplicationElementTitle() {
            let harness = makeHarness()
            harness.expectEqual("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem ? elem.title : null;
            })()
        """, "Hammerspoon 2 Test App")
        }

        @Test("applicationElement pid matches the running application's pid")
        func testApplicationElementPidMatchesApp() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem && elem.pid === app.pid;
            })()
        """)
        }

        @Test("applicationElement pid is a positive integer")
        func testApplicationElementPidIsPositive() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem && typeof elem.pid === 'number' && elem.pid > 0;
            })()
        """)
        }

        // MARK: - Issue #269: setAttributeValue is exported under its documented name

        @Test("setAttributeValue is callable by its documented name, not its selector name")
        func testSetAttributeValueJSName() {
            let harness = makeHarness()
            harness.eval("""
            var elem = hs.ax.applicationElement(hs.application.fromPID(testAppPID));
            """)
            #expect(harness.evalTypeOf("elem.setAttributeValue") == "function")
            #expect(harness.evalTypeOf("elem.setAttributeValueValue") == "undefined")
            // An attribute the test app doesn't have, so this changes nothing but still reaches the setter.
            #expect(harness.evalBool("elem.setAttributeValue('AXHammerspoonNonexistent', true)") == false)
            #expect(!harness.hasException)
        }

        // MARK: - setAttributeValue type validation

        @Test("setAttributeValue throws, naming HSPoint, when AXPosition is given a plain {x, y} object")
        func testSetAttributeValuePlainPointThrows() {
            let harness = makeHarness()
            harness.eval("""
            var elem = hs.ax.applicationElement(hs.application.fromPID(testAppPID));
            elem.setAttributeValue('AXPosition', {x: 10, y: 20});
            """)
            harness.expectException()
            #expect(harness.exceptionMessage?.contains("AXPosition requires an HSPoint") == true)
            #expect(harness.exceptionMessage?.contains("got a plain object") == true)
        }

        @Test("setAttributeValue throws when AXPosition is given the wrong bridged type")
        func testSetAttributeValueWrongBridgedTypeThrows() {
            let harness = makeHarness()
            harness.eval("""
            var elem = hs.ax.applicationElement(hs.application.fromPID(testAppPID));
            elem.setAttributeValue('AXPosition', new HSSize(10, 20));
            """)
            harness.expectException()
            #expect(harness.exceptionMessage?.contains("got an HSSize") == true)
        }

        @Test("setAttributeValue throws when AXSize or AXFrame are given plain objects")
        func testSetAttributeValuePlainSizeAndFrameThrow() {
            let harness = makeHarness()
            harness.eval("var elem = hs.ax.applicationElement(hs.application.fromPID(testAppPID));")
            harness.eval("elem.setAttributeValue('AXSize', {w: 10, h: 20})")
            #expect(harness.exceptionMessage?.contains("AXSize requires an HSSize") == true)
            harness.eval("elem.setAttributeValue('AXFrame', {x: 0, y: 0, w: 10, h: 20})")
            #expect(harness.exceptionMessage?.contains("AXFrame requires an HSRect") == true)
        }

        @Test("setAttributeValue throws when a boolean attribute is given a string")
        func testSetAttributeValueBooleanAttributeThrows() {
            let harness = makeHarness()
            harness.eval("""
            var elem = hs.ax.applicationElement(hs.application.fromPID(testAppPID));
            elem.setAttributeValue('AXMinimized', 'true');
            """)
            harness.expectException()
            #expect(harness.exceptionMessage?.contains("AXMinimized requires a boolean, got a string") == true)
        }

        @Test("setAttributeValue throws when a boolean attribute is given a number", arguments: ["0", "1"])
        func testSetAttributeValueBooleanAttributeRejectsNumbers(number: String) {
            let harness = makeHarness()
            harness.eval("var elem = hs.ax.applicationElement(hs.application.fromPID(testAppPID));")
            harness.eval("elem.setAttributeValue('AXMinimized', \(number))")
            #expect(harness.exceptionMessage?.contains("AXMinimized requires a boolean, got a number") == true)
        }

        @Test("setAttributeValue passes booleans for a boolean attribute through to the Accessibility API", arguments: ["true", "false"])
        func testSetAttributeValueBooleanAttributeAcceptsBooleans(boolean: String) {
            let harness = makeHarness()
            harness.eval("var elem = hs.ax.applicationElement(hs.application.fromPID(testAppPID));")
            // An application element has no AXMinimized, so the API refuses it, but without a type error.
            #expect(harness.evalBool("elem.setAttributeValue('AXMinimized', \(boolean))") == false)
            #expect(!harness.hasException)
        }

        @Test("setAttributeValue moves a window when AXPosition is given an HSPoint")
        func testSetAttributeValuePositionWithHSPoint() {
            let harness = makeHarness()
            harness.eval("""
            var win = hs.ax.applicationElement(hs.application.fromPID(testAppPID)).attributeValue('AXWindows')[0];
            var before = win.attributeValue('AXPosition');
            var target = new HSPoint(before.x + 10, before.y + 10);
            """)
            #expect(harness.evalBool("win.setAttributeValue('AXPosition', target)") == true)
            #expect(!harness.hasException)
            harness.expectTrue("win.attributeValue('AXPosition').equals(target)")
            #expect(harness.evalBool("win.setAttributeValue('AXPosition', before)") == true)
        }

        // MARK: - Element identity

        @Test("isEqualToElement is true for two lookups of the same element")
        func testIsEqualToElementSameElement() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var a = hs.ax.applicationElement(app);
                var b = hs.ax.applicationElement(app);
                return a.isEqualToElement(b);
            })()
        """)
        }

        @Test("isEqualToElement is false for two different elements")
        func testIsEqualToElementDifferentElements() {
            let harness = makeHarness()
            harness.expectFalse("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                var sysElem = hs.ax.systemWideElement();
                return appElem.isEqualToElement(sysElem);
            })()
        """)
        }

        // MARK: - Basic element properties

        @Test("element isEnabled is a boolean")
        func testElementIsEnabledIsBoolean() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem && typeof elem.isEnabled === 'boolean';
            })()
        """)
        }

        @Test("element isFocused is a boolean")
        func testElementIsFocusedIsBoolean() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem && typeof elem.isFocused === 'boolean';
            })()
        """)
        }

        @Test("element subrole is null or a string")
        func testElementSubroleIsNullOrString() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                var s = elem.subrole;
                return s === null || s === undefined || typeof s === 'string';
            })()
        """)
        }

        @Test("element elementDescription is null or a string")
        func testElementDescriptionIsNullOrString() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                var d = elem.elementDescription;
                return d === null || d === undefined || typeof d === 'string';
            })()
        """)
        }

        @Test("element value access does not throw")
        func testElementValueAccessDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (elem) { var _unused = elem.value; }
            })()
        """)
            #expect(!harness.hasException)
        }

        // MARK: - Geometry properties

        @Test("element position is null or an object")
        func testElementPositionIsNullOrObject() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                var p = elem.position;
                return p === null || p === undefined || typeof p === 'object';
            })()
        """)
            #expect(!harness.hasException)
        }

        @Test("element size is null or an object")
        func testElementSizeIsNullOrObject() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                var s = elem.size;
                return s === null || s === undefined || typeof s === 'object';
            })()
        """)
            #expect(!harness.hasException)
        }

        @Test("element frame is null or an object")
        func testElementFrameIsNullOrObject() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                var f = elem.frame;
                return f === null || f === undefined || typeof f === 'object';
            })()
        """)
            #expect(!harness.hasException)
        }

        @Test("AXWindow element position is an object")
        func testWindowElementPositionIsObject() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (!appElem) return false;
                var win = appElem.children().find(function(c) { return c.role === 'AXWindow'; });
                if (!win) return false;
                var p = win.position;
                return p !== null && p !== undefined && typeof p === 'object';
            })()
        """)
        }

        @Test("AXWindow element size is an object")
        func testWindowElementSizeIsObject() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (!appElem) return false;
                var win = appElem.children().find(function(c) { return c.role === 'AXWindow'; });
                if (!win) return false;
                var s = win.size;
                return s !== null && s !== undefined && typeof s === 'object';
            })()
        """)
        }

        // MARK: - Hierarchy

        @Test("children() returns an array")
        func testChildrenReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem && Array.isArray(elem.children());
            })()
        """)
        }

        @Test("application element children() is not empty")
        func testApplicationChildrenNotEmpty() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                // The test app always has its main window and its menu bar
                return elem.children().length > 0;
            })()
        """)
        }

        @Test("AXMenuBar children() returns a non-empty array")
        func testMenuBarChildrenIsNonEmpty() {
            // Regression test: children() previously used a whole-array `as?` cast
            // (`element.attribute(.children)`) which always fails for AX array
            // attributes and silently returns []. AXMenuBar always has items
            // regardless of window state, so this is a reliable, deterministic check.
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (!appElem) return false;
                var menuBar = appElem.attributeValue('AXMenuBar');
                if (!menuBar) return false;
                return menuBar.children().length > 0;
            })()
        """)
        }

        @Test("AXWindow child has a non-null position")
        func testWindowChildPositionWhenPresent() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (!appElem) return false;
                var win = appElem.children().find(function(c) { return c.role === 'AXWindow'; });
                if (!win) return false;
                return win.position !== null && win.position !== undefined;
            })()
        """)
        }

        @Test("childAtIndex(0) returns the first child when children exist")
        func testChildAtIndexZeroReturnsFirstChild() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                var children = elem.children();
                if (children.length === 0) return true;
                var child = elem.childAtIndex(0);
                return child !== null && child !== undefined;
            })()
        """)
        }

        @Test("childAtIndex(-1) returns null")
        func testChildAtIndexNegativeReturnsNull() {
            let harness = makeHarness()
            let result = harness.evalValue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem ? elem.childAtIndex(-1) : null;
            })()
        """)
            #expect(result?.isNull == true || result?.isUndefined == true)
        }

        @Test("childAtIndex(9999) returns null for an out-of-bounds index")
        func testChildAtIndexOutOfBoundsReturnsNull() {
            let harness = makeHarness()
            let result = harness.evalValue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem ? elem.childAtIndex(9999) : null;
            })()
        """)
            #expect(result?.isNull == true || result?.isUndefined == true)
        }

        @Test("child element's parent is non-null")
        func testChildParentIsNonNull() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (!appElem) return false;
                var children = appElem.children();
                if (children.length === 0) return true;
                var parent = children[0].parent;
                return parent !== null && parent !== undefined;
            })()
        """)
        }

        @Test("child element's parent has role AXApplication")
        func testChildParentRoleIsAXApplication() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (!appElem) return false;
                var children = appElem.children();
                if (children.length === 0) return true;
                var parent = children[0].parent;
                return parent && parent.role === 'AXApplication';
            })()
        """)
        }

        // MARK: - Attributes

        @Test("attributeNames() returns a non-empty array")
        func testAttributeNamesNonEmpty() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                var names = elem.attributeNames();
                return Array.isArray(names) && names.length > 0;
            })()
        """)
        }

        @Test("attributeNames() contains AXRole")
        func testAttributeNamesContainsAXRole() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                return elem.attributeNames().indexOf('AXRole') !== -1;
            })()
        """)
        }

        @Test("attributeNames() contains AXChildren")
        func testAttributeNamesContainsAXChildren() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                return elem.attributeNames().indexOf('AXChildren') !== -1;
            })()
        """)
        }

        @Test("attributeValue('AXRole') matches the role property")
        func testAttributeValueAXRoleMatchesRole() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                return elem.attributeValue('AXRole') === elem.role;
            })()
        """)
        }

        @Test("attributeValue('AXChildren') returns usable element objects, not plain objects")
        func testAttributeValueAXChildrenReturnsElements() {
            // Regression test for #221: AXSwift's getMultipleAttributes() only
            // unwraps a raw AXUIElement into its UIElement wrapper for scalar
            // attributes; for array-valued attributes like AXChildren, the
            // array's elements were left as raw AXUIElement values that
            // bridgeValue() didn't recognize, so JavaScriptCore exposed them as
            // empty, unusable plain objects.
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (!appElem) return false;
                var kids = appElem.attributeValue('AXChildren');
                if (!Array.isArray(kids) || kids.length === 0) return false;
                return kids.every(function(k) {
                    return k.typeName === 'HSAXElement' && typeof k.role === 'string';
                });
            })()
        """)
        }

        @Test("attributeValue for a non-existent attribute returns null or undefined")
        func testAttributeValueNonExistentReturnsNull() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                var v = elem.attributeValue('AXNonExistentAttribute12345');
                return v === null || v === undefined;
            })()
        """)
        }

        @Test("isAttributeSettable('AXRole') returns false")
        func testIsAttributeSettableAXRoleReturnsFalse() {
            let harness = makeHarness()
            harness.expectFalse("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem ? elem.isAttributeSettable('AXRole') : false;
            })()
        """)
        }

        @Test("isAttributeSettable returns a boolean")
        func testIsAttributeSettableReturnsBoolean() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                if (!elem) return false;
                return typeof elem.isAttributeSettable('AXRole') === 'boolean';
            })()
        """)
        }

        // MARK: - Actions

        @Test("actionNames() returns an array")
        func testActionNamesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem && Array.isArray(elem.actionNames());
            })()
        """)
        }

        @Test("performAction with an invalid action name returns false")
        func testPerformActionInvalidReturnsFalse() {
            let harness = makeHarness()
            harness.expectFalse("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var elem = hs.ax.applicationElement(app);
                return elem ? elem.performAction('AXNonExistentAction12345') : false;
            })()
        """)
        }
    }

    // MARK: - Suite 3: JS helper functions (requires accessibility permissions)

    /// Tests for the Swift convenience functions (focusedElement, findByRole, findByTitle, printHierarchy).
    ///
    /// The searches run on the test app: its element tree is small, and it has a window and a menu
    /// item titled "New Window". Searching Finder's whole tree took over a minute per test.
    @Suite("hs.ax convenience function tests", .serialized,
           .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"),
           .testApp)
    struct HSAXJSHelperTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSAXModule.self, as: "ax")
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.eval("var testAppPID = \(TestAppControl.pid ?? -1);")
            TestAppControl.showCurrentTest()
            return harness
        }

        // MARK: - findByRole

        @Test("findByRole returns an array")
        func testFindByRoleReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                return Array.isArray(hs.ax.findByRole('AXWindow', appElem));
            })()
        """)
        }

        @Test("findByRole results all have the requested role")
        func testFindByRoleResultsMatchRequestedRole() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                var results = hs.ax.findByRole('AXWindow', appElem);
                return results.length > 0 && results.every(function(e) { return e.role === 'AXWindow'; });
            })()
        """)
        }

        @Test("findByRole returns empty array for a non-existent role")
        func testFindByRoleNonExistentRoleReturnsEmpty() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                var results = hs.ax.findByRole('AXNonExistentRole12345', appElem);
                return Array.isArray(results) && results.length === 0;
            })()
        """)
        }

        @Test("findByRole with an application element finds the root element itself")
        func testFindByRoleApplicationElementFindsItself() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (!appElem) return false;
                // findByRole includes the root; AXApplication should be found immediately
                var results = hs.ax.findByRole('AXApplication', appElem);
                return Array.isArray(results) && results.length >= 1;
            })()
        """)
        }

        // MARK: - findByTitle

        @Test("findByTitle returns an array")
        func testFindByTitleReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                return Array.isArray(hs.ax.findByTitle('New Window', appElem));
            })()
        """)
        }

        @Test("findByTitle returns empty array for a non-existent title")
        func testFindByTitleNonExistentTitleReturnsEmpty() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                var results = hs.ax.findByTitle('zzz_nonexistent_title_zzz_12345', appElem);
                return Array.isArray(results) && results.length === 0;
            })()
        """)
        }

        @Test("findByTitle results all include the searched string in their title")
        func testFindByTitleResultsContainSearchString() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                var results = hs.ax.findByTitle('New Window', appElem);
                return results.length > 0 && results.every(function(e) { return e.title && e.title.includes('New Window'); });
            })()
        """)
        }

        // MARK: - focusedElement

        @Test("focusedElement returns null or a valid element object")
        func testFocusedElementReturnsNullOrObject() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var elem = hs.ax.focusedElement();
                return elem === null || elem === undefined || typeof elem === 'object';
            })()
        """)
        }

        @Test("focusedElement does not throw")
        func testFocusedElementDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("hs.ax.focusedElement()")
            #expect(!harness.hasException)
        }

        // MARK: - printHierarchy

        @Test("printHierarchy with a valid element does not throw")
        func testPrintHierarchyWithElementDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (appElem) { hs.ax.printHierarchy(appElem); }
            })()
        """)
            #expect(!harness.hasException)
        }

        @Test("printHierarchy with no argument does not throw")
        func testPrintHierarchyWithNoArgDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("hs.ax.printHierarchy()")
            #expect(!harness.hasException)
        }

        @Test("printHierarchy with an explicit depth does not throw")
        func testPrintHierarchyWithDepthDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("""
            (function() {
                var app = hs.application.fromPID(testAppPID);
                var appElem = hs.ax.applicationElement(app);
                if (appElem) { hs.ax.printHierarchy(appElem, 2); }
            })()
        """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 4a: Watcher registration failures (no accessibility permissions required)

    /// on()/once() must throw when native registration fails, recording nothing (issue #254).
    /// Native registration is simulated by stubbing `_addWatcher`/`_removeWatcher`, so these
    /// never register real AX observers. The element is built directly in Swift rather than via
    /// hs.ax.systemWideElement(), which returns null without accessibility permissions - so this
    /// suite runs in CI too.
    @Suite("hs.ax watcher registration failure tests")
    struct HSAXWatcherFailureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSAXModule.self, as: "ax")
            let element = HSAXElement(element: SystemWideElement(AXUIElementCreateSystemWide()))
            harness.context.setObject(element, forKeyedSubscript: "sys" as NSString)
            // `failing` lists the notification names whose native registration should fail;
            // `added`/`removed` record which notifications reached the native layer.
            harness.eval("""
            var failing = [];
            var added = [];
            var removed = [];
            Object.defineProperty(hs.ax, '_addWatcher', {
                value: function(element, notification, callback) {
                    added.push(notification);
                    return !failing.includes(notification);
                },
                writable: true, configurable: true
            });
            Object.defineProperty(hs.ax, '_removeWatcher', {
                value: function(element, notification) { removed.push(notification); },
                writable: true, configurable: true
            });
            """)
            return harness
        }

        @Test("on() throws when native registration fails, and a later on() retries it")
        func testOnThrowsOnNativeFailure() {
            let harness = makeHarness()
            harness.eval("""
            failing = ['AXValueChanged'];
            var threw = false;
            try { hs.ax.on(sys, 'AXValueChanged', function() {}); } catch (e) { threw = true; }
            failing = [];
            hs.ax.on(sys, 'AXValueChanged', function() {});
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
            // Nothing was recorded by the failed call, so the retry reached the native layer again.
            #expect(harness.evalInt("added.length") == 2)
        }

        @Test("once() throws when native registration fails")
        func testOnceThrowsOnNativeFailure() {
            let harness = makeHarness()
            harness.eval("""
            failing = ['AXValueChanged'];
            var threw = false;
            try { hs.ax.once(sys, 'AXValueChanged', function() {}); } catch (e) { threw = true; }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
        }

        @Test("once() throws when listener is not a function")
        func testOnceThrowsForNonFunctionListener() {
            let harness = makeHarness()
            harness.eval("hs.ax.once(sys, 'AXValueChanged', 'not a function')")
            #expect(harness.hasException)
            #expect(harness.evalInt("added.length") == 0)
        }

        @Test("on() with an array rolls back earlier notifications when a later one fails")
        func testOnArrayIsAllOrNothing() {
            let harness = makeHarness()
            harness.eval("""
            failing = ['AXWindowMoved'];
            var threw = false;
            try {
                hs.ax.on(sys, ['AXWindowCreated', 'AXWindowMoved'], function() {});
            } catch (e) { threw = true; }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
            #expect(harness.evalString("removed.join(',')") == "AXWindowCreated")
        }

        @Test("on() array rollback leaves a registration that existed before the call")
        func testOnArrayRollbackKeepsPriorRegistration() {
            let harness = makeHarness()
            harness.eval("""
            var fn = function() {};
            hs.ax.on(sys, 'AXWindowCreated', fn);
            failing = ['AXWindowMoved'];
            var threw = false;
            try { hs.ax.on(sys, ['AXWindowCreated', 'AXWindowMoved'], fn); } catch (e) { threw = true; }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
            #expect(harness.evalInt("removed.length") == 0)
        }

        @Test("once() with an array rolls back earlier notifications when a later one fails")
        func testOnceArrayIsAllOrNothing() {
            let harness = makeHarness()
            harness.eval("""
            failing = ['AXWindowMoved'];
            var threw = false;
            try {
                hs.ax.once(sys, ['AXWindowCreated', 'AXWindowMoved'], function() {});
            } catch (e) { threw = true; }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
            #expect(harness.evalString("removed.join(',')") == "AXWindowCreated")
        }

        @Test("on() with an invalid notification type throws without registering")
        func testOnInvalidNotificationTypeThrows() {
            let harness = makeHarness()
            harness.eval("hs.ax.on(sys, 42, function() {})")
            #expect(harness.hasException)
            #expect(harness.evalInt("added.length") == 0)
        }

        @Test("a once() failure names once() in its error, not on()")
        func testOnceFailureNamesOnce() {
            let harness = makeHarness()
            harness.eval("""
            failing = ['AXValueChanged'];
            var message = null;
            try { hs.ax.once(sys, 'AXValueChanged', function() {}); } catch (e) { message = e.message; }
            """)
            #expect(!harness.hasException)
            #expect(harness.evalString("message") == "hs.ax.once(): failed to start watcher for 'AXValueChanged'")
        }

        @Test("on()/once() with an empty notification array throws without registering", arguments: ["on", "once"])
        func testEmptyNotificationArrayThrows(method: String) {
            let harness = makeHarness()
            harness.eval("hs.ax.\(method)(sys, [], 'not a function')")
            #expect(harness.hasException)
            #expect(harness.evalInt("added.length") == 0)
        }

        @Test("a failing removal during rollback doesn't stop the rest, and the original error is rethrown")
        func testRollbackContinuesPastFailingRemoval() {
            let harness = makeHarness()
            harness.eval("""
            Object.defineProperty(hs.ax, '_removeWatcher', {
                value: function(element, notification) {
                    removed.push(notification);
                    if (notification === 'AXWindowCreated') { throw new Error('removal failed'); }
                },
                writable: true, configurable: true
            });
            failing = ['AXWindowResized'];
            var message = null;
            try {
                hs.ax.on(sys, ['AXWindowCreated', 'AXWindowMoved', 'AXWindowResized'], function() {});
            } catch (e) { message = e.message; }
            """)
            #expect(!harness.hasException)
            #expect(harness.evalString("removed.join(',')") == "AXWindowCreated,AXWindowMoved")
            #expect(harness.evalString("message") == "hs.ax.on(): failed to start watcher for 'AXWindowResized'")
        }

        @Test("on() throws if the watcher emitter is unavailable")
        func testOnThrowsWithoutEmitter() {
            let harness = makeHarness()
            harness.eval("hs.ax._watcherEmitter = null")
            harness.eval("hs.ax.on(sys, 'AXValueChanged', function() {})")
            #expect(harness.hasException)
            #expect(harness.evalInt("added.length") == 0)
        }
    }

    // MARK: - Suite 4: Watcher lifecycle (requires accessibility permissions)

    /// Tests that verify the add/remove watcher API is correct and safe, without
    /// requiring actual AX notifications to fire.
    @Suite("hs.ax watcher lifecycle tests", .serialized,
           .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"),
           .testApp)
    struct HSAXWatcherLifecycleTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSAXModule.self, as: "ax")
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.eval("var testAppPID = \(TestAppControl.pid ?? -1);")
            TestAppControl.showCurrentTest()
            return harness
        }

        @Test("on and off cycle completes without error")
        func testAddRemoveCycleIsSafe() {
            let harness = makeHarness()
            harness.eval("""
            var _lc1App = hs.application.fromPID(testAppPID);
            var _lc1Elem = hs.ax.applicationElement(_lc1App);
            var _lc1Fn = function(notification, elem) {};
            hs.ax.on(_lc1Elem, 'AXWindowCreated', _lc1Fn);
            hs.ax.off(_lc1Elem, 'AXWindowCreated', _lc1Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("off with an unregistered listener does not throw")
        func testRemoveUnregisteredListenerIsSafe() {
            let harness = makeHarness()
            harness.eval("""
            var _lc2App = hs.application.fromPID(testAppPID);
            var _lc2Elem = hs.ax.applicationElement(_lc2App);
            hs.ax.off(_lc2Elem, 'AXWindowCreated', function() {});
        """)
            #expect(!harness.hasException)
        }

        @Test("adding the same listener twice is idempotent (no crash)")
        func testAddSameListenerTwiceIsIdempotent() {
            let harness = makeHarness()
            harness.eval("""
            var _lc3App = hs.application.fromPID(testAppPID);
            var _lc3Elem = hs.ax.applicationElement(_lc3App);
            var _lc3Fn = function(notification, elem) {};
            hs.ax.on(_lc3Elem, 'AXWindowCreated', _lc3Fn);
            hs.ax.on(_lc3Elem, 'AXWindowCreated', _lc3Fn);
            hs.ax.off(_lc3Elem, 'AXWindowCreated', _lc3Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("three distinct listeners can all be added and removed for the same notification")
        func testMultipleDistinctListenersLifecycle() {
            let harness = makeHarness()
            harness.eval("""
            var _lc4App = hs.application.fromPID(testAppPID);
            var _lc4Elem = hs.ax.applicationElement(_lc4App);
            var _lc4Fn1 = function(n, e) {};
            var _lc4Fn2 = function(n, e) {};
            var _lc4Fn3 = function(n, e) {};
            hs.ax.on(_lc4Elem, 'AXWindowCreated', _lc4Fn1);
            hs.ax.on(_lc4Elem, 'AXWindowCreated', _lc4Fn2);
            hs.ax.on(_lc4Elem, 'AXWindowCreated', _lc4Fn3);
            hs.ax.off(_lc4Elem, 'AXWindowCreated', _lc4Fn1);
            hs.ax.off(_lc4Elem, 'AXWindowCreated', _lc4Fn2);
            hs.ax.off(_lc4Elem, 'AXWindowCreated', _lc4Fn3);
        """)
            #expect(!harness.hasException)
        }

        @Test("watchers for different notifications on the same application can coexist")
        func testMultipleNotificationsOnSameApp() {
            let harness = makeHarness()
            harness.eval("""
            var _lc5App = hs.application.fromPID(testAppPID);
            var _lc5Elem = hs.ax.applicationElement(_lc5App);
            var _lc5Fn1 = function(n, e) {};
            var _lc5Fn2 = function(n, e) {};
            hs.ax.on(_lc5Elem, 'AXWindowCreated', _lc5Fn1);
            hs.ax.on(_lc5Elem, 'AXWindowMiniaturized', _lc5Fn2);
            hs.ax.off(_lc5Elem, 'AXWindowCreated', _lc5Fn1);
            hs.ax.off(_lc5Elem, 'AXWindowMiniaturized', _lc5Fn2);
        """)
            #expect(!harness.hasException)
        }

        @Test("on accepts an array of notification names for a single listener")
        func testAddWatcherAcceptsArrayOfNotifications() {
            let harness = makeHarness()
            harness.eval("""
            var _lc10App = hs.application.fromPID(testAppPID);
            var _lc10Elem = hs.ax.applicationElement(_lc10App);
            var _lc10Fn = function(n, e) {};
            hs.ax.on(_lc10Elem, ['AXWindowCreated', 'AXWindowMiniaturized', 'AXWindowMoved'], _lc10Fn);
            hs.ax.off(_lc10Elem, ['AXWindowCreated', 'AXWindowMiniaturized', 'AXWindowMoved'], _lc10Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("on with an array registers the listener for each notification independently")
        func testAddWatcherArrayRegistersEachNotificationIndependently() {
            let harness = makeHarness()
            harness.eval("""
            var _lc11App = hs.application.fromPID(testAppPID);
            var _lc11Elem = hs.ax.applicationElement(_lc11App);
            var _lc11Fn = function(n, e) {};
            hs.ax.on(_lc11Elem, ['AXWindowCreated', 'AXWindowMiniaturized'], _lc11Fn);
            // Removing just one of the two notifications should leave the other registered
            hs.ax.off(_lc11Elem, 'AXWindowCreated', _lc11Fn);
            hs.ax.off(_lc11Elem, 'AXWindowMiniaturized', _lc11Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("_addWatcher returns false when native registration fails")
        func testUnderscoreAddWatcherReturnsFalseOnFailure() {
            let harness = makeHarness()
            // The system-wide element has no owning process (pid is -1), so native
            // registration against it always fails.
            #expect(harness.evalBool("hs.ax._addWatcher(hs.ax.systemWideElement(), 'AXValueChanged', function() {})") == false)
        }

        @Test("a failed on() does not permanently block later retries for the same element+notification")
        func testAddWatcherRetriesAfterFailure() {
            let harness = makeHarness()
            harness.eval("""
            var _lc13Sys = hs.ax.systemWideElement();
            var _lc13CallCount = 0;
            var _lc13Original = hs.ax._addWatcher;
            Object.defineProperty(hs.ax, '_addWatcher', {
                value: function(element, notification, callback) {
                    _lc13CallCount++;
                    return _lc13Original.call(hs.ax, element, notification, callback);
                },
                writable: true, configurable: true
            });
            var _lc13Fn1 = function() {};
            var _lc13Fn2 = function() {};
            // Both calls target the same element+notification key. If a failed
            // registration were incorrectly retained, the second call would skip
            // _addWatcher entirely and _lc13CallCount would stay at 1.
            try { hs.ax.on(_lc13Sys, 'AXValueChanged', _lc13Fn1); } catch (e) {}
            try { hs.ax.on(_lc13Sys, 'AXValueChanged', _lc13Fn2); } catch (e) {}
            Object.defineProperty(hs.ax, '_addWatcher', { value: _lc13Original, writable: true, configurable: true });
        """)
            #expect(!harness.hasException)
            #expect(harness.evalInt("_lc13CallCount") == 2)
        }

        @Test("on throws when listener is a string, not a function")
        func testAddWatcherThrowsForStringListener() {
            let harness = makeHarness()
            harness.eval("""
            var _lc6App = hs.application.fromPID(testAppPID);
            var _lc6Elem = hs.ax.applicationElement(_lc6App);
            hs.ax.on(_lc6Elem, 'AXWindowCreated', 'not a function');
        """)
            #expect(harness.hasException)
        }

        @Test("on throws when listener is a number")
        func testAddWatcherThrowsForNumberListener() {
            let harness = makeHarness()
            harness.eval("""
            var _lc7App = hs.application.fromPID(testAppPID);
            var _lc7Elem = hs.ax.applicationElement(_lc7App);
            hs.ax.on(_lc7Elem, 'AXWindowCreated', 42);
        """)
            #expect(harness.hasException)
        }

        @Test("on throws when listener is null")
        func testAddWatcherThrowsForNullListener() {
            let harness = makeHarness()
            harness.eval("""
            var _lc8App = hs.application.fromPID(testAppPID);
            var _lc8Elem = hs.ax.applicationElement(_lc8App);
            hs.ax.on(_lc8Elem, 'AXWindowCreated', null);
        """)
            #expect(harness.hasException)
        }

        @Test("on's exception from an invalid listener is catchable by the caller's own try/catch")
        func testOnInvalidListenerExceptionIsCatchable() {
            // Regression test: the tests above only check harness.hasException, which fires for
            // any exception crossing an invokeMethod call boundary regardless of whether a JS
            // try/catch around the call would see it (see callCapturingException's doc comment)
            // - so they didn't actually verify a caller's own try/catch works. on()/off()/once()
            // are native Swift methods that invokeMethod into the JS emitter; before using
            // callCapturingException there, the emitter's "listener must be a function" throw
            // never reached this try/catch at all.
            let harness = makeHarness()
            harness.eval("""
            var _catchApp = hs.application.fromPID(testAppPID);
            var _catchElem = hs.ax.applicationElement(_catchApp);
            var threw = false;
            try {
                hs.ax.on(_catchElem, 'AXWindowCreated', 'not a function');
            } catch (err) {
                threw = true;
            }
        """)
            harness.expectTrue("threw")
        }

        @Test("removing one of two listeners leaves the other in place")
        func testRemovingOneListenerLeavesOtherIntact() {
            let harness = makeHarness()
            harness.eval("""
            var _lc9App = hs.application.fromPID(testAppPID);
            var _lc9Elem = hs.ax.applicationElement(_lc9App);
            var _lc9Fn1 = function(n, e) {};
            var _lc9Fn2 = function(n, e) {};
            hs.ax.on(_lc9Elem, 'AXWindowCreated', _lc9Fn1);
            hs.ax.on(_lc9Elem, 'AXWindowCreated', _lc9Fn2);
            hs.ax.off(_lc9Elem, 'AXWindowCreated', _lc9Fn2);
            hs.ax.off(_lc9Elem, 'AXWindowCreated', _lc9Fn1);
        """)
            #expect(!harness.hasException)
        }

        @Test("a watcher can be added to a specific descendant element, not just the application element")
        func testWatcherOnDescendantElement() {
            let harness = makeHarness()
            harness.eval("""
            var _lc10App = hs.application.fromPID(testAppPID);
            var _lc10AppElem = hs.ax.applicationElement(_lc10App);
            var _lc10MenuBar = _lc10AppElem.attributeValue('AXMenuBar');
            var _lc10Fn = function(notification, elem) {};
            hs.ax.on(_lc10MenuBar, 'AXValueChanged', _lc10Fn);
            hs.ax.off(_lc10MenuBar, 'AXValueChanged', _lc10Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("watchers on two different elements for the same notification coexist independently")
        func testWatchersOnDifferentElementsCoexist() {
            let harness = makeHarness()
            harness.eval("""
            var _lc11App = hs.application.fromPID(testAppPID);
            var _lc11AppElem = hs.ax.applicationElement(_lc11App);
            var _lc11MenuBar = _lc11AppElem.attributeValue('AXMenuBar');
            var _lc11Fn1 = function(n, e) {};
            var _lc11Fn2 = function(n, e) {};
            // Same notification type, two distinct elements — this would previously
            // collide because watchers were keyed only by (pid, notification).
            hs.ax.on(_lc11AppElem, 'AXValueChanged', _lc11Fn1);
            hs.ax.on(_lc11MenuBar, 'AXValueChanged', _lc11Fn2);
            hs.ax.off(_lc11AppElem, 'AXValueChanged', _lc11Fn1);
            hs.ax.off(_lc11MenuBar, 'AXValueChanged', _lc11Fn2);
        """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 4.5: Watcher routing (requires accessibility permissions)

    /// Tests for HSAXModule.handleNotification()'s routing logic: which registered watchers
    /// a given (element, notification) pair should be delivered to. These call
    /// handleNotification() directly with a real element but a synthesized notification,
    /// rather than relying on a real AXObserver callback - this sandbox cannot receive real
    /// AX notification callbacks (confirmed separately: even a bare, known-working single
    /// registration never fires here), so a test that waited for one would be vacuous. Calling
    /// the routing function directly exercises the exact logic that used to silently drop
    /// application-scoped notifications, without depending on OS notification delivery.
    @Suite("hs.ax watcher routing tests", .serialized,
           .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"),
           .testApp)
    struct HSAXWatcherRoutingTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSAXModule.self, as: "ax")
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.eval("var testAppPID = \(TestAppControl.pid ?? -1);")
            TestAppControl.showCurrentTest()
            return harness
        }

        /// Fetches the two menu bar items of the test app, along with the app
        /// element itself and the live HSAXModule instance, for use in routing tests.
        @MainActor
        private func makeFixture(_ harness: JSTestHarness) -> (module: HSAXModule, appElement: UIElement, itemA: UIElement, itemB: UIElement)? {
            harness.eval("""
            var _rtApp = hs.application.fromPID(testAppPID);
            var _rtAppElem = hs.ax.applicationElement(_rtApp);
            var _rtMenuBar = _rtAppElem.attributeValue('AXMenuBar');
            var _rtMenuItems = _rtMenuBar.children();
            globalThis._rtAppElem = _rtAppElem;
            // The menu bar items themselves (AXMenuBarItem) reject AXObserverAddNotification
            // for AXValueChanged - their AXMenu dropdown children accept it, so those are used
            // as the two distinct, independently-watchable descendant elements here.
            globalThis._rtItemA = _rtMenuItems[0].children()[0];
            globalThis._rtItemB = _rtMenuItems[1].children()[0];
        """)
            guard !harness.hasException,
                  let module = harness.evalValue("hs.ax")?.toObjectOf(HSAXModule.self) as? HSAXModule,
                  let appElement = harness.evalValue("_rtAppElem")?.toObjectOf(HSAXElement.self) as? HSAXElement,
                  let itemA = harness.evalValue("_rtItemA")?.toObjectOf(HSAXElement.self) as? HSAXElement,
                  let itemB = harness.evalValue("_rtItemB")?.toObjectOf(HSAXElement.self) as? HSAXElement
            else {
                return nil
            }
            return (module, appElement.element, itemA.element, itemB.element)
        }

        @Test("a notification delivered for a descendant element is routed to an application-level watcher")
        @MainActor
        func testDescendantNotificationRoutesToApplicationWatcher() {
            let harness = makeHarness()
            guard let fixture = makeFixture(harness) else {
                Issue.record("Could not set up the test app AX fixture")
                return
            }

            harness.eval("""
            globalThis._rtAppEvents = [];
            var _rtAppFn = function(n, e) { _rtAppEvents.push(n); };
            globalThis._rtAppFn = _rtAppFn;
            hs.ax.on(_rtAppElem, 'AXValueChanged', _rtAppFn);
        """)
            defer { harness.eval("hs.ax.off(_rtAppElem, 'AXValueChanged', _rtAppFn);") }
            #expect(!harness.hasException)

            // Simulate AX delivering the notification for a specific descendant (itemA), the
            // way it actually does for application-scoped notifications like AXWindowCreated -
            // never with the application element itself as the delivered element.
            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXValueChanged"))

            #expect(harness.eval("_rtAppEvents.length") as? Int == 1)
        }

        @Test("a descendant-scoped watcher only fires for its own exact element, not a sibling")
        @MainActor
        func testDescendantWatcherStaysScopedToItsOwnElement() {
            let harness = makeHarness()
            guard let fixture = makeFixture(harness) else {
                Issue.record("Could not set up the test app AX fixture")
                return
            }

            harness.eval("""
            globalThis._rtItemAEvents = [];
            var _rtItemAFn = function(n, e) { _rtItemAEvents.push(n); };
            globalThis._rtItemAFn = _rtItemAFn;
            hs.ax.on(_rtItemA, 'AXValueChanged', _rtItemAFn);
        """)
            defer { harness.eval("hs.ax.off(_rtItemA, 'AXValueChanged', _rtItemAFn);") }
            #expect(!harness.hasException)

            // A notification for the SIBLING element (itemB) must not reach itemA's watcher.
            fixture.module.handleNotification(element: fixture.itemB, notification: UIElement.AXNotification(rawValue: "AXValueChanged"))
            #expect(harness.eval("_rtItemAEvents.length") as? Int == 0)

            // The exact same notification for itemA itself must reach it.
            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXValueChanged"))
            #expect(harness.eval("_rtItemAEvents.length") as? Int == 1)
        }

        @Test("application-level and descendant-level watchers for the same notification both fire, independently")
        @MainActor
        func testApplicationAndDescendantWatchersCoexistAndBothFire() {
            let harness = makeHarness()
            guard let fixture = makeFixture(harness) else {
                Issue.record("Could not set up the test app AX fixture")
                return
            }

            harness.eval("""
            globalThis._rtAppEvents2 = [];
            globalThis._rtItemAEvents2 = [];
            var _rtAppFn2 = function(n, e) { _rtAppEvents2.push(n); };
            var _rtItemAFn2 = function(n, e) { _rtItemAEvents2.push(n); };
            globalThis._rtAppFn2 = _rtAppFn2;
            globalThis._rtItemAFn2 = _rtItemAFn2;
            hs.ax.on(_rtAppElem, 'AXValueChanged', _rtAppFn2);
            hs.ax.on(_rtItemA, 'AXValueChanged', _rtItemAFn2);
        """)
            defer {
                harness.eval("""
                hs.ax.off(_rtAppElem, 'AXValueChanged', _rtAppFn2);
                hs.ax.off(_rtItemA, 'AXValueChanged', _rtItemAFn2);
            """)
            }
            #expect(!harness.hasException)

            // A notification for itemA should reach BOTH watchers: the one scoped exactly to
            // itemA, and the application-level one (matched by PID).
            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXValueChanged"))

            #expect(harness.eval("_rtAppEvents2.length") as? Int == 1)
            #expect(harness.eval("_rtItemAEvents2.length") as? Int == 1)

            // A notification for itemB (not individually watched) should reach only the
            // application-level watcher, not itemA's.
            fixture.module.handleNotification(element: fixture.itemB, notification: UIElement.AXNotification(rawValue: "AXValueChanged"))

            #expect(harness.eval("_rtAppEvents2.length") as? Int == 2)
            #expect(harness.eval("_rtItemAEvents2.length") as? Int == 1)
        }

        @Test("a destroyed element's watchers are all removed automatically, after its destroyed listener fires")
        @MainActor
        func testDestroyedElementWatchersAreRemoved() {
            let harness = makeHarness()
            guard let fixture = makeFixture(harness) else {
                Issue.record("Could not set up Finder AX fixture")
                return
            }

            harness.eval("""
            globalThis._rtDestroyEvents = [];
            var _rtDestroyFn = function(n, e) { _rtDestroyEvents.push(n); };
            var _rtSiblingFn = function(n, e) {};
            globalThis._rtDestroyFn = _rtDestroyFn;
            globalThis._rtSiblingFn = _rtSiblingFn;
            hs.ax.on(_rtItemA, ['AXValueChanged', 'AXUIElementDestroyed'], _rtDestroyFn);
            hs.ax.on(_rtItemB, 'AXValueChanged', _rtSiblingFn);
        """)
            defer {
                harness.eval("""
                hs.ax.off(_rtItemA, ['AXValueChanged', 'AXUIElementDestroyed'], _rtDestroyFn);
                hs.ax.off(_rtItemB, 'AXValueChanged', _rtSiblingFn);
            """)
            }
            #expect(!harness.hasException)
            #expect(fixture.module.watcherCount == 3)

            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXUIElementDestroyed"))

            // The destroyed listener still hears about the destruction...
            #expect(harness.eval("_rtDestroyEvents.length") as? Int == 1)
            // ...then both of itemA's watchers are gone, while its sibling's is untouched
            #expect(fixture.module.watcherCount == 1)

            // Nothing is left to fire for itemA
            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXValueChanged"))
            #expect(harness.eval("_rtDestroyEvents.length") as? Int == 1)
        }

        @Test("watching an element again after its watchers were removed on destruction registers it afresh")
        @MainActor
        func testReWatchingAfterAutomaticRemovalRegistersNatively() {
            let harness = makeHarness()
            guard let fixture = makeFixture(harness) else {
                Issue.record("Could not set up Finder AX fixture")
                return
            }

            harness.eval("""
            globalThis._rtRewatchEvents = [];
            var _rtRewatchFn = function(n, e) { _rtRewatchEvents.push(n); };
            globalThis._rtRewatchFn = _rtRewatchFn;
            hs.ax.on(_rtItemA, 'AXValueChanged', _rtRewatchFn);
        """)
            defer { harness.eval("hs.ax.off(_rtItemA, 'AXValueChanged', _rtRewatchFn);") }
            #expect(!harness.hasException)

            // itemA isn't really destroyed, so it can be watched again afterwards. The JS
            // emitter must have dropped its bucket too, or this on() would skip the native
            // registration and the listener would never fire.
            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXUIElementDestroyed"))
            #expect(fixture.module.watcherCount == 0)

            harness.eval("hs.ax.on(_rtItemA, 'AXValueChanged', _rtRewatchFn);")
            #expect(!harness.hasException)
            #expect(fixture.module.watcherCount == 1)

            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXValueChanged"))
            #expect(harness.eval("_rtRewatchEvents.length") as? Int == 1)
        }

        @Test("a destroyed listener that calls off() itself is still handled cleanly")
        @MainActor
        func testDestroyedListenerCallingOffItself() {
            let harness = makeHarness()
            guard let fixture = makeFixture(harness) else {
                Issue.record("Could not set up Finder AX fixture")
                return
            }

            harness.eval("""
            globalThis._rtSelfOffEvents = [];
            var _rtSelfOffFn = function(n, e) {
                _rtSelfOffEvents.push(n);
                hs.ax.off(_rtItemA, ['AXValueChanged', 'AXUIElementDestroyed'], _rtSelfOffFn);
            };
            hs.ax.on(_rtItemA, ['AXValueChanged', 'AXUIElementDestroyed'], _rtSelfOffFn);
        """)
            #expect(!harness.hasException)
            #expect(fixture.module.watcherCount == 2)

            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXUIElementDestroyed"))

            #expect(!harness.hasException)
            #expect(harness.eval("_rtSelfOffEvents.length") as? Int == 1)
            #expect(fixture.module.watcherCount == 0)
        }

        @Test("an application's watchers are all removed automatically when it terminates")
        @MainActor
        func testTerminatedApplicationWatchersAreRemoved() {
            let harness = makeHarness()
            guard let fixture = makeFixture(harness),
                  let pid = harness.eval("_rtAppElem.pid") as? Int else {
                Issue.record("Could not set up Finder AX fixture")
                return
            }

            harness.eval("""
            globalThis._rtTermEvents = [];
            var _rtTermFn = function(n, e) { _rtTermEvents.push(n); };
            globalThis._rtTermFn = _rtTermFn;
            hs.ax.on(_rtAppElem, 'AXValueChanged', _rtTermFn);
            hs.ax.on(_rtItemA, 'AXValueChanged', _rtTermFn);
        """)
            defer {
                harness.eval("""
                hs.ax.off(_rtAppElem, 'AXValueChanged', _rtTermFn);
                hs.ax.off(_rtItemA, 'AXValueChanged', _rtTermFn);
            """)
            }
            #expect(!harness.hasException)
            #expect(fixture.module.watcherCount == 2)

            // A different PID's termination leaves them alone
            fixture.module.handleApplicationTerminated(pid: pid_t(pid) + 100_000)
            #expect(fixture.module.watcherCount == 2)

            // Simulated, so Finder needn't actually quit
            fixture.module.handleApplicationTerminated(pid: pid_t(pid))
            #expect(fixture.module.watcherCount == 0)

            fixture.module.handleNotification(element: fixture.itemA, notification: UIElement.AXNotification(rawValue: "AXValueChanged"))
            #expect(harness.eval("_rtTermEvents.length") as? Int == 0)

            // And the emitter has forgotten them, so they can be watched again
            harness.eval("hs.ax.on(_rtItemA, 'AXValueChanged', _rtTermFn);")
            #expect(!harness.hasException)
            #expect(fixture.module.watcherCount == 1)
        }
    }

    // MARK: - Suite 5: Watcher event delivery (requires accessibility permissions)

    /// Tests that actual AX notifications are delivered to registered JavaScript callbacks.
    /// These tests launch the Hammerspoon 2 Test App (``TestAppControl``) and have it open a window to
    /// trigger AXWindowCreated.
    @Suite("hs.ax watcher event delivery tests", .serialized,
           .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"),
           .testApp)
    struct HSAXWatcherEventTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSAXModule.self, as: "ax")
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.eval("var testAppPID = \(TestAppControl.pid ?? -1);")
            TestAppControl.showCurrentTest()
            return harness
        }

        @Test("watcher receives 'windowCreated' when the test app opens a window")
        func testWatcherReceivesWindowCreated() async {
            defer { TestAppControl.closeWindows() }
            let harness = makeHarness()

            harness.eval("""
            var _ed1App = hs.application.fromPID(testAppPID);
            var _ed1Elem = hs.ax.applicationElement(_ed1App);
            var _ed1Events = [];
            var _ed1Fn = function(notification, elem) { _ed1Events.push(notification); };
            hs.ax.on(_ed1Elem, 'AXWindowCreated', _ed1Fn);
        """)
            defer { harness.eval("hs.ax.off(_ed1Elem, 'AXWindowCreated', _ed1Fn);") }

            TestAppControl.openWindow()

            let received = await harness.waitForAsync(timeout: 2.0) {
                harness.eval("_ed1Events.length > 0") as? Bool == true
            }

            #expect(received, "no windowCreated notification arrived")
            if received {
                harness.expectTrue("_ed1Events.indexOf('windowCreated') !== -1")
            }
        }

        @Test("multiple listeners all receive the same windowCreated notification")
        func testMultipleListenersAllReceiveEvent() async {
            defer { TestAppControl.closeWindows() }
            let harness = makeHarness()

            harness.eval("""
            var _ed2App = hs.application.fromPID(testAppPID);
            var _ed2Elem = hs.ax.applicationElement(_ed2App);
            var _ed2Count1 = 0, _ed2Count2 = 0;
            var _ed2Fn1 = function(n, e) { if (n === 'windowCreated') _ed2Count1++; };
            var _ed2Fn2 = function(n, e) { if (n === 'windowCreated') _ed2Count2++; };
            hs.ax.on(_ed2Elem, 'AXWindowCreated', _ed2Fn1);
            hs.ax.on(_ed2Elem, 'AXWindowCreated', _ed2Fn2);
        """)
            defer {
                harness.eval("""
                hs.ax.off(_ed2Elem, 'AXWindowCreated', _ed2Fn1);
                hs.ax.off(_ed2Elem, 'AXWindowCreated', _ed2Fn2);
            """)
            }

            TestAppControl.openWindow()

            let received = await harness.waitForAsync(timeout: 2.0) {
                harness.eval("_ed2Count1 > 0 && _ed2Count2 > 0") as? Bool == true
            }

            #expect(received, "no windowCreated notification arrived")
            if received {
                harness.expectTrue("_ed2Count1 > 0")
                harness.expectTrue("_ed2Count2 > 0")
            }
        }

        @Test("a removed listener does not receive subsequent events")
        func testRemovedListenerDoesNotReceiveEvents() async {
            defer { TestAppControl.closeWindows() }
            let harness = makeHarness()

            harness.eval("""
            var _ed3App = hs.application.fromPID(testAppPID);
            var _ed3Elem = hs.ax.applicationElement(_ed3App);
            var _ed3RemovedCount = 0, _ed3KeptCount = 0;
            var _ed3RemovedFn = function(n, e) { _ed3RemovedCount++; };
            var _ed3KeptFn = function(n, e) { if (n === 'windowCreated') _ed3KeptCount++; };
            hs.ax.on(_ed3Elem, 'AXWindowCreated', _ed3RemovedFn);
            hs.ax.on(_ed3Elem, 'AXWindowCreated', _ed3KeptFn);
            hs.ax.off(_ed3Elem, 'AXWindowCreated', _ed3RemovedFn);
        """)
            defer { harness.eval("hs.ax.off(_ed3Elem, 'AXWindowCreated', _ed3KeptFn);") }

            TestAppControl.openWindow()

            let received = await harness.waitForAsync(timeout: 2.0) {
                harness.eval("_ed3KeptCount > 0") as? Bool == true
            }

            #expect(received, "no windowCreated notification arrived")
            if received {
                harness.expectTrue("_ed3KeptCount > 0")
                harness.expectEqual("_ed3RemovedCount", 0)
            }
        }

        @Test("watcher callback receives the camelCase notification name and an element object")
        func testWatcherCallbackReceivesCorrectArguments() async {
            defer { TestAppControl.closeWindows() }
            let harness = makeHarness()

            harness.eval("""
            var _ed4App = hs.application.fromPID(testAppPID);
            var _ed4TargetElem = hs.ax.applicationElement(_ed4App);
            var _ed4Notif = null, _ed4Elem = null;
            var _ed4Fn = function(notification, element) {
                _ed4Notif = notification;
                _ed4Elem = element;
            };
            hs.ax.on(_ed4TargetElem, 'AXWindowCreated', _ed4Fn);
        """)
            defer { harness.eval("hs.ax.off(_ed4TargetElem, 'AXWindowCreated', _ed4Fn);") }

            TestAppControl.openWindow()

            let received = await harness.waitForAsync(timeout: 2.0) {
                harness.eval("_ed4Notif !== null") as? Bool == true
            }

            #expect(received, "no windowCreated notification arrived")
            if received {
                // Notification is delivered as the camelCase key (e.g. "windowCreated"), not "AXWindowCreated"
                harness.expectEqual("_ed4Notif", "windowCreated")
                harness.expectTrue("_ed4Elem !== null && typeof _ed4Elem === 'object'")
            }
        }

        @Test("watcher callback element has a valid role string")
        func testWatcherCallbackElementHasRole() async {
            defer { TestAppControl.closeWindows() }
            let harness = makeHarness()

            harness.eval("""
            var _ed5App = hs.application.fromPID(testAppPID);
            var _ed5Elem = hs.ax.applicationElement(_ed5App);
            var _ed5Role = null;
            var _ed5Fn = function(notification, element) {
                if (element) { _ed5Role = element.role; }
            };
            hs.ax.on(_ed5Elem, 'AXWindowCreated', _ed5Fn);
        """)
            defer { harness.eval("hs.ax.off(_ed5Elem, 'AXWindowCreated', _ed5Fn);") }

            TestAppControl.openWindow()

            let received = await harness.waitForAsync(timeout: 2.0) {
                harness.eval("_ed5Role !== null") as? Bool == true
            }

            #expect(received, "no windowCreated notification arrived")
            if received {
                harness.expectTrue("typeof _ed5Role === 'string' && _ed5Role.length > 0")
            }
        }

        @Test("watcher registered with an array of notifications receives events for them")
        func testWatcherWithArrayOfNotificationsReceivesEvents() async {
            defer { TestAppControl.closeWindows() }
            let harness = makeHarness()

            harness.eval("""
            var _ed6App = hs.application.fromPID(testAppPID);
            var _ed6Elem = hs.ax.applicationElement(_ed6App);
            var _ed6Events = [];
            var _ed6Fn = function(notification, elem) { _ed6Events.push(notification); };
            hs.ax.on(_ed6Elem, ['AXWindowCreated', 'AXWindowMoved'], _ed6Fn);
        """)
            defer { harness.eval("hs.ax.off(_ed6Elem, ['AXWindowCreated', 'AXWindowMoved'], _ed6Fn);") }

            TestAppControl.openWindow()

            let received = await harness.waitForAsync(timeout: 2.0) {
                harness.eval("_ed6Events.length > 0") as? Bool == true
            }

            #expect(received, "no windowCreated notification arrived")
            if received {
                harness.expectTrue("_ed6Events.indexOf('windowCreated') !== -1")
            }
        }
    }
}
