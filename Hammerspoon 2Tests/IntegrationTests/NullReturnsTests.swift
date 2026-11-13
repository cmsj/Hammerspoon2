//
//  NullReturnsTests.swift
//  Hammerspoon 2Tests
//

import Testing
import AppKit
import JavaScriptCore
@testable import Hammerspoon_2
import HammerspoonSDK

/// JavaScriptCore bridges nil returned from Swift as `undefined`; `NullReturnsInstaller` makes it
/// `null` instead. These use real app types, since the installer only looks at classes in the app
/// binary.
@Suite("Null returns tests")
struct NullReturnsTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hashing")
        return harness
    }

    @Test("A method returning nil returns null")
    func testNilMethodReturnIsNull() {
        let harness = makeHarness()
        #expect(harness.evalTypeOf("hs.hashing.base64Decode('not base64!')") == "object")
        harness.expectTrue("hs.hashing.base64Decode('not base64!') === null")
        #expect(!harness.hasException)
    }

    @Test("A method returning an object still returns it")
    func testNonNilMethodReturnIsUnchanged() {
        let harness = makeHarness()
        #expect(harness.evalString("hs.hashing.base64Decode('aGVsbG8=')") == "hello")
    }

    @Test("A method returning Void still returns undefined")
    func testVoidMethodReturnIsUndefined() {
        let harness = makeHarness()
        harness.context.setObject(NSImage(size: NSSize(width: 1, height: 1)).toBridge(), forKeyedSubscript: "image" as NSString)
        #expect(harness.evalTypeOf("image.set(image)") == "undefined")
        #expect(!harness.hasException)
    }

    @Test("A property getter returning nil returns null")
    func testNilGetterIsNull() {
        let harness = makeHarness()
        let image = NSImage(size: NSSize(width: 1, height: 1)).toBridge()
        #expect(image.name == nil)
        harness.context.setObject(image, forKeyedSubscript: "image" as NSString)
        harness.expectTrue("image.name === null")
    }

    @Test("A property setter still works")
    func testSetterIsUnchanged() {
        let harness = makeHarness()
        let image = NSImage(size: NSSize(width: 1, height: 1)).toBridge()
        harness.context.setObject(image, forKeyedSubscript: "image" as NSString)
        harness.eval("image.name = 'NullReturnsTestsImage'")
        #expect(image.name == "NullReturnsTestsImage")
        #expect(harness.evalString("image.name") == "NullReturnsTestsImage")
    }

    @Test("A static method returning nil returns null")
    func testNilStaticMethodReturnIsNull() {
        let harness = makeHarness()
        harness.expectTrue("HSImage.fromPath('/nonexistent/NullReturnsTests.png') === null")
        #expect(!harness.hasException)
    }

    @Test("Wrapped methods are named after their property")
    func testWrappedMethodName() {
        let harness = makeHarness()
        #expect(harness.evalString("hs.hashing.base64Decode.name") == "base64Decode")
    }

    @Test("Wrapped methods still check their receiver")
    func testWrappedMethodChecksThis() {
        let harness = makeHarness()
        harness.eval("hs.hashing.base64Decode.call({}, 'aGVsbG8=')")
        harness.expectException()
    }

    @Test("User code replacing Reflect.apply doesn't affect wrapped methods")
    func testWrappersIgnoreReplacedGlobals() {
        let harness = makeHarness()
        harness.eval("Reflect.apply = function () { return 'hijacked'; }")
        harness.expectTrue("hs.hashing.base64Decode('not base64!') === null")
        #expect(harness.evalString("hs.hashing.base64Decode('aGVsbG8=')") == "hello")
    }

    @Test("Wrapping survives garbage collection of a class's prototype before it has any instances")
    func testWrappingSurvivesGC() {
        // The pool drains the JSValues the installer made, which would otherwise keep the
        // prototypes alive and make this pass even without pinning
        let harness = autoreleasepool { JSTestHarness() }
        harness.collectGarbage()
        harness.loadModule(HSHashModule.self, as: "hashing")
        harness.expectTrue("hs.hashing.base64Decode('not base64!') === null")
    }

    @Test("Selector names are converted the way JavaScriptCore does")
    func testJSNameForSelector() {
        #expect(NullReturnsInstaller.jsName(forSelector: "toString") == "toString")
        #expect(NullReturnsInstaller.jsName(forSelector: "base64Decode:") == "base64Decode")
        #expect(NullReturnsInstaller.jsName(forSelector: "hmacMD5::") == "hmacMD5")
        #expect(NullReturnsInstaller.jsName(forSelector: "getWindow:withTitle:") == "getWindowWithTitle")
        #expect(NullReturnsInstaller.jsName(forSelector: "_addWatcher::") == "_addWatcher")
    }

    @Test("Object return type encodings are recognised")
    func testReturnsObject() {
        #expect(NullReturnsInstaller.returnsObject("@24@0:8@16"))
        #expect(NullReturnsInstaller.returnsObject("r@16@0:8"))
        #expect(!NullReturnsInstaller.returnsObject("v24@0:8@16"))
        #expect(!NullReturnsInstaller.returnsObject("B16@0:8"))
        #expect(!NullReturnsInstaller.returnsObject(nil))
    }

    @Test("The installer finds the app's exported classes")
    func testFindsExportedClasses() {
        let hash = NullReturnsInstaller.exportedClasses.first { $0.name == NSStringFromClass(HSHashModule.self) }
        #expect(hash?.instanceMethods.contains("base64Decode") == true)
        let image = NullReturnsInstaller.exportedClasses.first { $0.name == NSStringFromClass(HSImage.self) }
        #expect(image?.instanceGetters.contains("name") == true)
        #expect(image?.classMethods.contains("fromPath") == true)
        // Scalar-returning and Void members aren't wrapped
        #expect(image?.instanceGetters.contains("template") == false)
        #expect(image?.instanceMethods.contains("set") == false)
        // Nor are passthrough members, whose undefined is deliberate
        let fs = NullReturnsInstaller.exportedClasses.first { $0.name == NSStringFromClass(HSFSModule.self) }
        #expect(fs?.instanceMethods.contains("open") == true)
        #expect(fs?.instanceMethods.contains("withFile") == false)
    }

    @Test("Every passthrough member is exported, so a rename can't silently drop it")
    func testPassthroughMembersExist() {
        for passthrough in NullReturnsInstaller.passthroughMembers {
            let harness = JSTestHarness()
            harness.context.setObject(passthrough.cls, forKeyedSubscript: "cls" as NSString)
            #expect(harness.evalBool("'\(passthrough.member)' in cls.prototype") == true, "\(passthrough.cls).\(passthrough.member)")
        }
    }

    @Test("A JSValue-returning getter returning nil returns null")
    func testNilJSValueGetterIsNull() {
        let harness = makeHarness()
        harness.loadModule(HSURLEventModule.self, as: "urlevent")
        // The getter returns Swift nil when no callback is set
        harness.expectTrue("hs.urlevent.httpCallback === null")
        harness.eval("hs.urlevent.httpCallback = () => {}")
        harness.expectTrue("typeof hs.urlevent.httpCallback === 'function'")
        harness.eval("hs.urlevent.httpCallback = null")
        harness.expectTrue("hs.urlevent.httpCallback === null")
        #expect(!harness.hasException)
    }
}
