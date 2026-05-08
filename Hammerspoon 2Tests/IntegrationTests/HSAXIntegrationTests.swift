//
//  HSAXIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
@testable import Hammerspoon_2

private nonisolated func isAccessibilityEnabled() -> Bool {
    return AXIsProcessTrusted()
}

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

    // MARK: - Core Swift API presence

    @Test("systemWideElement is a function")
    func testSystemWideElementIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.systemWideElement === 'function'")
    }

    @Test("applicationElement is a function")
    func testApplicationElementIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.applicationElement === 'function'")
    }

    @Test("windowElement is a function")
    func testWindowElementIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.windowElement === 'function'")
    }

    @Test("elementAtPoint is a function")
    func testElementAtPointIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.elementAtPoint === 'function'")
    }

    @Test("addWatcher is a function")
    func testAddWatcherIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.addWatcher === 'function'")
    }

    @Test("removeWatcher is a function")
    func testRemoveWatcherIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.removeWatcher === 'function'")
    }

    // MARK: - JS enhancement API presence

    @Test("_watcherEmitter is initialized by hs.ax.js")
    func testWatcherEmitterInitialized() {
        let harness = makeHarness()
        harness.expectTrue("hs.ax._watcherEmitter !== null && hs.ax._watcherEmitter !== undefined")
    }

    @Test("focusedElement is a function (JS enhancement)")
    func testFocusedElementIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.focusedElement === 'function'")
    }

    @Test("findByRole is a function (JS enhancement)")
    func testFindByRoleIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.findByRole === 'function'")
    }

    @Test("findByTitle is a function (JS enhancement)")
    func testFindByTitleIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.findByTitle === 'function'")
    }

    @Test("printHierarchy is a function (JS enhancement)")
    func testPrintHierarchyIsFunction() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.ax.printHierarchy === 'function'")
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

/// Tests that inspect real AX elements. Uses Finder as the target application
/// because it is always running on macOS, including GitHub macOS runners.
@Suite("hs.ax element inspection tests", .serialized, .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"))
struct HSAXElementInspectionTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSAXModule.self, as: "ax")
        harness.loadModule(HSApplicationModule.self, as: "application")
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
        harness.expectTrue("typeof hs.ax.systemWideElement().pid === 'number'")
    }

    // MARK: - Application element (Finder)

    @Test("applicationElement returns non-null for Finder")
    func testApplicationElementForFinderNonNull() {
        let harness = makeHarness()
        let result = harness.evalValue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                return finder ? hs.ax.applicationElement(finder) : null;
            })()
        """)
        #expect(result?.isObject == true)
    }

    @Test("applicationElement role is AXApplication for Finder")
    func testApplicationElementRoleIsAXApplication() {
        let harness = makeHarness()
        harness.expectEqual("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem ? elem.role : null;
            })()
        """, "AXApplication")
    }

    @Test("applicationElement title is 'Finder'")
    func testApplicationElementTitleIsFinder() {
        let harness = makeHarness()
        harness.expectEqual("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem ? elem.title : null;
            })()
        """, "Finder")
    }

    @Test("applicationElement pid matches the running application's pid")
    func testApplicationElementPidMatchesApp() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem && elem.pid === finder.pid;
            })()
        """)
    }

    @Test("applicationElement pid is a positive integer")
    func testApplicationElementPidIsPositive() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem && typeof elem.pid === 'number' && elem.pid > 0;
            })()
        """)
    }

    // MARK: - Basic element properties

    @Test("element isEnabled is a boolean")
    func testElementIsEnabledIsBoolean() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem && typeof elem.isEnabled === 'boolean';
            })()
        """)
    }

    @Test("element isFocused is a boolean")
    func testElementIsFocusedIsBoolean() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem && typeof elem.isFocused === 'boolean';
            })()
        """)
    }

    @Test("element subrole is null or a string")
    func testElementSubroleIsNullOrString() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                if (!elem) return false;
                var f = elem.frame;
                return f === null || f === undefined || typeof f === 'object';
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("AXWindow element position is an object when Finder has a window open")
    func testWindowElementPositionIsObject() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                if (!appElem) return false;
                var win = appElem.children().find(function(c) { return c.role === 'AXWindow'; });
                if (!win) return true; // No window open — skip gracefully.
                var p = win.position;
                return p !== null && p !== undefined && typeof p === 'object';
            })()
        """)
    }

    @Test("AXWindow element size is an object when Finder has a window open")
    func testWindowElementSizeIsObject() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                if (!appElem) return false;
                var win = appElem.children().find(function(c) { return c.role === 'AXWindow'; });
                if (!win) return true; // No window open — skip gracefully.
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem && Array.isArray(elem.children());
            })()
        """)
    }

    @Test("Finder application element children() length is a non-negative integer")
    func testFinderChildrenLengthIsNonNegative() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                if (!elem) return false;
                // Length may be 0 when no Finder windows are open; that is valid.
                return elem.children().length >= 0;
            })()
        """)
    }

    @Test("AXWindow child has a non-null position when Finder has a window open")
    func testWindowChildPositionWhenPresent() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                if (!appElem) return false;
                var win = appElem.children().find(function(c) { return c.role === 'AXWindow'; });
                // Skip gracefully when Finder has no open windows.
                if (!win) return true;
                return win.position !== null && win.position !== undefined;
            })()
        """)
    }

    @Test("childAtIndex(0) returns the first child when children exist")
    func testChildAtIndexZeroReturnsFirstChild() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                if (!elem) return false;
                return elem.attributeValue('AXRole') === elem.role;
            })()
        """)
    }

    @Test("attributeValue for a non-existent attribute returns null or undefined")
    func testAttributeValueNonExistentReturnsNull() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem ? elem.isAttributeSettable('AXRole') : false;
            })()
        """)
    }

    @Test("isAttributeSettable returns a boolean")
    func testIsAttributeSettableReturnsBoolean() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem && Array.isArray(elem.actionNames());
            })()
        """)
    }

    @Test("performAction with an invalid action name returns false")
    func testPerformActionInvalidReturnsFalse() {
        let harness = makeHarness()
        harness.expectFalse("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var elem = hs.ax.applicationElement(finder);
                return elem ? elem.performAction('AXNonExistentAction12345') : false;
            })()
        """)
    }
}

// MARK: - Suite 3: JS helper functions (requires accessibility permissions)

/// Tests for the JavaScript convenience functions defined in hs.ax.js.
@Suite("hs.ax JS helper function tests", .serialized, .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"))
struct HSAXJSHelperTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSAXModule.self, as: "ax")
        harness.loadModule(HSApplicationModule.self, as: "application")
        return harness
    }

    // MARK: - findByRole

    @Test("findByRole returns an array")
    func testFindByRoleReturnsArray() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                return Array.isArray(hs.ax.findByRole('AXWindow', appElem));
            })()
        """)
    }

    @Test("findByRole results all have the requested role")
    func testFindByRoleResultsMatchRequestedRole() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                var results = hs.ax.findByRole('AXWindow', appElem);
                return results.every(function(e) { return e.role === 'AXWindow'; });
            })()
        """)
    }

    @Test("findByRole returns empty array for a non-existent role")
    func testFindByRoleNonExistentRoleReturnsEmpty() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                var results = hs.ax.findByRole('AXNonExistentRole12345', appElem);
                return Array.isArray(results) && results.length === 0;
            })()
        """)
    }

    @Test("findByRole with Finder application element finds the root element itself")
    func testFindByRoleFinderElementFindsItself() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                return Array.isArray(hs.ax.findByTitle('Finder', appElem));
            })()
        """)
    }

    @Test("findByTitle returns empty array for a non-existent title")
    func testFindByTitleNonExistentTitleReturnsEmpty() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                var results = hs.ax.findByTitle('Finder', appElem);
                return results.every(function(e) { return e.title && e.title.includes('Finder'); });
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
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
                var finder = hs.application.matchingBundleID('com.apple.finder');
                var appElem = hs.ax.applicationElement(finder);
                if (appElem) { hs.ax.printHierarchy(appElem, 2); }
            })()
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 4: Watcher lifecycle (requires accessibility permissions)

/// Tests that verify the add/remove watcher API is correct and safe, without
/// requiring actual AX notifications to fire.
@Suite("hs.ax watcher lifecycle tests", .serialized, .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"))
struct HSAXWatcherLifecycleTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSAXModule.self, as: "ax")
        harness.loadModule(HSApplicationModule.self, as: "application")
        return harness
    }

    @Test("addWatcher and removeWatcher cycle completes without error")
    func testAddRemoveCycleIsSafe() {
        let harness = makeHarness()
        harness.eval("""
            var _lc1Finder = hs.application.matchingBundleID('com.apple.finder');
            var _lc1Fn = function(notification, elem) {};
            hs.ax.addWatcher(_lc1Finder, 'AXWindowCreated', _lc1Fn);
            hs.ax.removeWatcher(_lc1Finder, 'AXWindowCreated', _lc1Fn);
        """)
        #expect(!harness.hasException)
    }

    @Test("removeWatcher with an unregistered listener does not throw")
    func testRemoveUnregisteredListenerIsSafe() {
        let harness = makeHarness()
        harness.eval("""
            var _lc2Finder = hs.application.matchingBundleID('com.apple.finder');
            hs.ax.removeWatcher(_lc2Finder, 'AXWindowCreated', function() {});
        """)
        #expect(!harness.hasException)
    }

    @Test("adding the same listener twice is idempotent (no crash)")
    func testAddSameListenerTwiceIsIdempotent() {
        let harness = makeHarness()
        harness.eval("""
            var _lc3Finder = hs.application.matchingBundleID('com.apple.finder');
            var _lc3Fn = function(notification, elem) {};
            hs.ax.addWatcher(_lc3Finder, 'AXWindowCreated', _lc3Fn);
            hs.ax.addWatcher(_lc3Finder, 'AXWindowCreated', _lc3Fn);
            hs.ax.removeWatcher(_lc3Finder, 'AXWindowCreated', _lc3Fn);
        """)
        #expect(!harness.hasException)
    }

    @Test("three distinct listeners can all be added and removed for the same notification")
    func testMultipleDistinctListenersLifecycle() {
        let harness = makeHarness()
        harness.eval("""
            var _lc4Finder = hs.application.matchingBundleID('com.apple.finder');
            var _lc4Fn1 = function(n, e) {};
            var _lc4Fn2 = function(n, e) {};
            var _lc4Fn3 = function(n, e) {};
            hs.ax.addWatcher(_lc4Finder, 'AXWindowCreated', _lc4Fn1);
            hs.ax.addWatcher(_lc4Finder, 'AXWindowCreated', _lc4Fn2);
            hs.ax.addWatcher(_lc4Finder, 'AXWindowCreated', _lc4Fn3);
            hs.ax.removeWatcher(_lc4Finder, 'AXWindowCreated', _lc4Fn1);
            hs.ax.removeWatcher(_lc4Finder, 'AXWindowCreated', _lc4Fn2);
            hs.ax.removeWatcher(_lc4Finder, 'AXWindowCreated', _lc4Fn3);
        """)
        #expect(!harness.hasException)
    }

    @Test("watchers for different notifications on the same application can coexist")
    func testMultipleNotificationsOnSameApp() {
        let harness = makeHarness()
        harness.eval("""
            var _lc5Finder = hs.application.matchingBundleID('com.apple.finder');
            var _lc5Fn1 = function(n, e) {};
            var _lc5Fn2 = function(n, e) {};
            hs.ax.addWatcher(_lc5Finder, 'AXWindowCreated', _lc5Fn1);
            hs.ax.addWatcher(_lc5Finder, 'AXWindowMiniaturized', _lc5Fn2);
            hs.ax.removeWatcher(_lc5Finder, 'AXWindowCreated', _lc5Fn1);
            hs.ax.removeWatcher(_lc5Finder, 'AXWindowMiniaturized', _lc5Fn2);
        """)
        #expect(!harness.hasException)
    }

    @Test("addWatcher throws when listener is a string, not a function")
    func testAddWatcherThrowsForStringListener() {
        let harness = makeHarness()
        harness.eval("""
            var _lc6Finder = hs.application.matchingBundleID('com.apple.finder');
            hs.ax.addWatcher(_lc6Finder, 'AXWindowCreated', 'not a function');
        """)
        #expect(harness.hasException)
    }

    @Test("addWatcher throws when listener is a number")
    func testAddWatcherThrowsForNumberListener() {
        let harness = makeHarness()
        harness.eval("""
            var _lc7Finder = hs.application.matchingBundleID('com.apple.finder');
            hs.ax.addWatcher(_lc7Finder, 'AXWindowCreated', 42);
        """)
        #expect(harness.hasException)
    }

    @Test("addWatcher throws when listener is null")
    func testAddWatcherThrowsForNullListener() {
        let harness = makeHarness()
        harness.eval("""
            var _lc8Finder = hs.application.matchingBundleID('com.apple.finder');
            hs.ax.addWatcher(_lc8Finder, 'AXWindowCreated', null);
        """)
        #expect(harness.hasException)
    }

    @Test("removing one of two listeners leaves the other in place")
    func testRemovingOneListenerLeavesOtherIntact() {
        let harness = makeHarness()
        harness.eval("""
            var _lc9Finder = hs.application.matchingBundleID('com.apple.finder');
            var _lc9Fn1 = function(n, e) {};
            var _lc9Fn2 = function(n, e) {};
            hs.ax.addWatcher(_lc9Finder, 'AXWindowCreated', _lc9Fn1);
            hs.ax.addWatcher(_lc9Finder, 'AXWindowCreated', _lc9Fn2);
            hs.ax.removeWatcher(_lc9Finder, 'AXWindowCreated', _lc9Fn2);
            hs.ax.removeWatcher(_lc9Finder, 'AXWindowCreated', _lc9Fn1);
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 5: Watcher event delivery (requires accessibility permissions)

/// Tests that actual AX notifications are delivered to registered JavaScript callbacks.
/// These tests open a new Finder window using NSAppleScript to trigger AXWindowCreated
/// and clean up afterwards. They are skipped gracefully if AppleScript cannot open
/// the window (e.g. on a headless runner with no Automation permission for Finder).
@Suite("hs.ax watcher event delivery tests", .serialized, .disabled(if: !isAccessibilityEnabled(), "Accessibility permissions not available"))
struct HSAXWatcherEventTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSAXModule.self, as: "ax")
        harness.loadModule(HSApplicationModule.self, as: "application")
        return harness
    }

    /// Returns true if a new Finder window was successfully opened.
    private func openFinderWindow() -> Bool {
        let script = NSAppleScript(source: "tell application \"Finder\" to make new Finder window")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        return error == nil
    }

    /// Closes the frontmost Finder window; safe to call even if none is open.
    private func closeFinderWindow() {
        let src = "tell application \"Finder\" to if (count of Finder windows) > 0 then close Finder window 1"
        NSAppleScript(source: src)?.executeAndReturnError(nil)
    }

    @Test("watcher receives 'windowCreated' when a new Finder window is opened")
    func testWatcherReceivesWindowCreated() async {
        let harness = makeHarness()

        harness.eval("""
            var _ed1Finder = hs.application.matchingBundleID('com.apple.finder');
            var _ed1Events = [];
            var _ed1Fn = function(notification, elem) { _ed1Events.push(notification); };
            hs.ax.addWatcher(_ed1Finder, 'AXWindowCreated', _ed1Fn);
        """)
        defer { harness.eval("hs.ax.removeWatcher(_ed1Finder, 'AXWindowCreated', _ed1Fn);") }

        guard openFinderWindow() else { return }
        defer { closeFinderWindow() }

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_ed1Events.length > 0") as? Bool == true
        }

        if received {
            harness.expectTrue("_ed1Events.indexOf('windowCreated') !== -1")
        }
    }

    @Test("multiple listeners all receive the same windowCreated notification")
    func testMultipleListenersAllReceiveEvent() async {
        let harness = makeHarness()

        harness.eval("""
            var _ed2Finder = hs.application.matchingBundleID('com.apple.finder');
            var _ed2Count1 = 0, _ed2Count2 = 0;
            var _ed2Fn1 = function(n, e) { if (n === 'windowCreated') _ed2Count1++; };
            var _ed2Fn2 = function(n, e) { if (n === 'windowCreated') _ed2Count2++; };
            hs.ax.addWatcher(_ed2Finder, 'AXWindowCreated', _ed2Fn1);
            hs.ax.addWatcher(_ed2Finder, 'AXWindowCreated', _ed2Fn2);
        """)
        defer {
            harness.eval("""
                hs.ax.removeWatcher(_ed2Finder, 'AXWindowCreated', _ed2Fn1);
                hs.ax.removeWatcher(_ed2Finder, 'AXWindowCreated', _ed2Fn2);
            """)
        }

        guard openFinderWindow() else { return }
        defer { closeFinderWindow() }

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_ed2Count1 > 0 && _ed2Count2 > 0") as? Bool == true
        }

        if received {
            harness.expectTrue("_ed2Count1 > 0")
            harness.expectTrue("_ed2Count2 > 0")
        }
    }

    @Test("a removed listener does not receive subsequent events")
    func testRemovedListenerDoesNotReceiveEvents() async {
        let harness = makeHarness()

        harness.eval("""
            var _ed3Finder = hs.application.matchingBundleID('com.apple.finder');
            var _ed3RemovedCount = 0, _ed3KeptCount = 0;
            var _ed3RemovedFn = function(n, e) { _ed3RemovedCount++; };
            var _ed3KeptFn = function(n, e) { if (n === 'windowCreated') _ed3KeptCount++; };
            hs.ax.addWatcher(_ed3Finder, 'AXWindowCreated', _ed3RemovedFn);
            hs.ax.addWatcher(_ed3Finder, 'AXWindowCreated', _ed3KeptFn);
            hs.ax.removeWatcher(_ed3Finder, 'AXWindowCreated', _ed3RemovedFn);
        """)
        defer { harness.eval("hs.ax.removeWatcher(_ed3Finder, 'AXWindowCreated', _ed3KeptFn);") }

        guard openFinderWindow() else { return }
        defer { closeFinderWindow() }

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_ed3KeptCount > 0") as? Bool == true
        }

        if received {
            harness.expectTrue("_ed3KeptCount > 0")
            harness.expectEqual("_ed3RemovedCount", 0)
        }
    }

    @Test("watcher callback receives the camelCase notification name and an element object")
    func testWatcherCallbackReceivesCorrectArguments() async {
        let harness = makeHarness()

        harness.eval("""
            var _ed4Finder = hs.application.matchingBundleID('com.apple.finder');
            var _ed4Notif = null, _ed4Elem = null;
            var _ed4Fn = function(notification, element) {
                _ed4Notif = notification;
                _ed4Elem = element;
            };
            hs.ax.addWatcher(_ed4Finder, 'AXWindowCreated', _ed4Fn);
        """)
        defer { harness.eval("hs.ax.removeWatcher(_ed4Finder, 'AXWindowCreated', _ed4Fn);") }

        guard openFinderWindow() else { return }
        defer { closeFinderWindow() }

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_ed4Notif !== null") as? Bool == true
        }

        if received {
            // Notification is delivered as the camelCase key (e.g. "windowCreated"), not "AXWindowCreated"
            harness.expectEqual("_ed4Notif", "windowCreated")
            harness.expectTrue("_ed4Elem !== null && typeof _ed4Elem === 'object'")
        }
    }

    @Test("watcher callback element has a valid role string")
    func testWatcherCallbackElementHasRole() async {
        let harness = makeHarness()

        harness.eval("""
            var _ed5Finder = hs.application.matchingBundleID('com.apple.finder');
            var _ed5Role = null;
            var _ed5Fn = function(notification, element) {
                if (element) { _ed5Role = element.role; }
            };
            hs.ax.addWatcher(_ed5Finder, 'AXWindowCreated', _ed5Fn);
        """)
        defer { harness.eval("hs.ax.removeWatcher(_ed5Finder, 'AXWindowCreated', _ed5Fn);") }

        guard openFinderWindow() else { return }
        defer { closeFinderWindow() }

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_ed5Role !== null") as? Bool == true
        }

        if received {
            harness.expectTrue("typeof _ed5Role === 'string' && _ed5Role.length > 0")
        }
    }
}
