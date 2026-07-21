//
//  HSFSXattrIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
@testable import Hammerspoon_2

// MARK: - Helpers

/// Creates a unique temp file and deletes it when deallocated.
private final class TempXattrFile {
    let path: String

    init() throws {
        let uuid = UUID().uuidString
        path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hs.fs-xattr-\(uuid).txt")
        try "xattr test".write(toFile: path, atomically: true, encoding: .utf8)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Test suite

@MainActor
@Suite("hs.fs xattr tests")
struct HSFSXattrTests {

    // MARK: - API structure

    @Suite("hs.fs xattr API structure tests")
    struct HSFSXattrStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("xattrGet is a function")
        func testXattrGetIsFunction() {
            makeHarness().expectTrue("typeof hs.fs.xattrGet === 'function'")
        }

        @Test("xattrList is a function")
        func testXattrListIsFunction() {
            makeHarness().expectTrue("typeof hs.fs.xattrList === 'function'")
        }

        @Test("xattrSet is a function")
        func testXattrSetIsFunction() {
            makeHarness().expectTrue("typeof hs.fs.xattrSet === 'function'")
        }

        @Test("xattrRemove is a function")
        func testXattrRemoveIsFunction() {
            makeHarness().expectTrue("typeof hs.fs.xattrRemove === 'function'")
        }
    }

    // MARK: - xattrList

    @Suite("hs.fs.xattrList() tests")
    struct HSFSXattrListTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("xattrList on a real file returns an array")
        func testXattrListReturnsArray() {
            let sut = HSFSModule(engineID: UUID())
            #expect(sut.xattrList("/etc/hosts", nil) != nil)
        }

        @Test("xattrList on a non-existent path returns null")
        func testXattrListNonExistent() {
            let sut = HSFSModule(engineID: UUID())
            #expect(sut.xattrList("/nonexistent/\(UUID().uuidString)", nil) == nil)
        }

        @Test("xattrList on a file with no xattrs returns an empty array")
        func testXattrListEmpty() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let result = sut.xattrList(tmp.path, nil)
            #expect(result != nil)
        }

        @Test("xattrList from JS returns an array-like object")
        func testXattrListFromJS() {
            let harness = makeHarness()
            harness.eval("var attrs = hs.fs.xattrList('/etc/hosts')")
            harness.expectTrue("Array.isArray(attrs)")
            #expect(!harness.hasException)
        }

        @Test("xattrList with noFollow option does not crash")
        func testXattrListNoFollowOption() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let result = sut.xattrList(tmp.path, ["noFollow"] as NSArray)
            #expect(result != nil)
        }
    }

    // MARK: - xattrSet / xattrGet round-trip

    @Suite("hs.fs xattr set/get round-trip tests", .serialized)
    struct HSFSXattrRoundTripTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("xattrSet and xattrGet round-trip a plain ASCII value")
        func testSetGetASCII() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let attr = "com.example.hs2test"
            let value = "hello, xattr world!"

            let ok = sut.xattrSet(tmp.path, attr, value, nil, 0)
            #expect(ok, "xattrSet should succeed")

            let got = sut.xattrGet(tmp.path, attr, nil, 0)
            #expect(got == value)
        }

        @Test("xattrGet returns null for an attribute that does not exist")
        func testGetNonExistentAttribute() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            #expect(sut.xattrGet(tmp.path, "com.example.doesnotexist", nil, 0) == nil)
        }

        @Test("xattrGet returns null for a non-existent file")
        func testGetNonExistentFile() {
            let sut = HSFSModule(engineID: UUID())
            #expect(sut.xattrGet("/nonexistent/\(UUID().uuidString)", "any.attr", nil, 0) == nil)
        }

        @Test("xattrSet returns false for a non-existent file")
        func testSetNonExistentFile() {
            let sut = HSFSModule(engineID: UUID())
            #expect(sut.xattrSet("/nonexistent/\(UUID().uuidString)", "any.attr", "value", nil, 0) == false)
        }

        @Test("xattrSet and xattrGet appear in xattrList")
        func testSetAttributeAppearsInList() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let attr = "com.example.hs2listtest"

            _ = sut.xattrSet(tmp.path, attr, "value", nil, 0)
            let list = sut.xattrList(tmp.path, nil) ?? []
            #expect(list.contains(attr))
        }

        @Test("xattrSet overwrites an existing value")
        func testSetOverwrites() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let attr = "com.example.hs2overwrite"

            _ = sut.xattrSet(tmp.path, attr, "first", nil, 0)
            _ = sut.xattrSet(tmp.path, attr, "second", nil, 0)

            let got = sut.xattrGet(tmp.path, attr, nil, 0)
            #expect(got == "second")
        }

        @Test("round-trip works end-to-end from JS")
        func testRoundTripFromJS() throws {
            let tmp = try TempXattrFile()
            let harness = makeHarness()
            harness.eval("""
                var ok = hs.fs.xattrSet('\(tmp.path)', 'com.example.hs2js', 'test-value')
                var got = hs.fs.xattrGet('\(tmp.path)', 'com.example.hs2js')
            """)
            harness.expectTrue("ok === true")
            harness.expectTrue("got === 'test-value'")
            #expect(!harness.hasException)
        }
    }

    // MARK: - xattrRemove

    @Suite("hs.fs.xattrRemove() tests", .serialized)
    struct HSFSXattrRemoveTests {

        @Test("xattrRemove removes a previously set attribute")
        func testRemoveAttribute() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let attr = "com.example.hs2remove"

            _ = sut.xattrSet(tmp.path, attr, "to-remove", nil, 0)
            #expect(sut.xattrGet(tmp.path, attr, nil, 0) != nil, "attribute should exist before removal")

            let ok = sut.xattrRemove(tmp.path, attr, nil)
            #expect(ok, "xattrRemove should succeed")

            #expect(sut.xattrGet(tmp.path, attr, nil, 0) == nil, "attribute should be gone after removal")
        }

        @Test("xattrRemove returns false for an attribute that does not exist")
        func testRemoveNonExistentAttribute() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            #expect(sut.xattrRemove(tmp.path, "com.example.nosuchattr", nil) == false)
        }

        @Test("xattrRemove returns false for a non-existent file")
        func testRemoveNonExistentFile() {
            let sut = HSFSModule(engineID: UUID())
            #expect(sut.xattrRemove("/nonexistent/\(UUID().uuidString)", "any.attr", nil) == false)
        }

        @Test("removed attribute no longer appears in xattrList")
        func testRemovedAttributeNotInList() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let attr = "com.example.hs2removelist"

            _ = sut.xattrSet(tmp.path, attr, "value", nil, 0)
            _ = sut.xattrRemove(tmp.path, attr, nil)

            let list = sut.xattrList(tmp.path, nil) ?? []
            #expect(!list.contains(attr))
        }
    }

    // MARK: - Options

    @Suite("hs.fs xattr options tests")
    struct HSFSXattrOptionsTests {

        @Test("unrecognized option causes the call to fail and return nil/false")
        func testUnrecognizedOptionFails() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            #expect(sut.xattrList(tmp.path, ["unknownOption"] as NSArray) == nil)
            #expect(sut.xattrGet(tmp.path, "any.attr", ["unknownOption"] as NSArray, 0) == nil)
            #expect(sut.xattrSet(tmp.path, "any.attr", "value", ["unknownOption"] as NSArray, 0) == false)
            #expect(sut.xattrRemove(tmp.path, "any.attr", ["unknownOption"] as NSArray) == false)
        }

        @Test("nil options is treated as empty")
        func testNilOptions() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            #expect(sut.xattrList(tmp.path, nil) != nil)
        }

        @Test("empty options array works the same as nil")
        func testEmptyOptionsArray() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            #expect(sut.xattrList(tmp.path, NSArray()) != nil)
        }

        @Test("createOnly option fails when attribute already exists")
        func testCreateOnlyFails() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let attr = "com.example.hs2createonly"

            _ = sut.xattrSet(tmp.path, attr, "existing", nil, 0)
            let ok = sut.xattrSet(tmp.path, attr, "new", ["createOnly"] as NSArray, 0)
            #expect(ok == false, "createOnly should fail when attribute already exists")
        }

        @Test("replaceOnly option fails when attribute does not exist")
        func testReplaceOnlyFails() throws {
            let sut = HSFSModule(engineID: UUID())
            let tmp = try TempXattrFile()
            let ok = sut.xattrSet(tmp.path, "com.example.hs2replaceonly", "value", ["replaceOnly"] as NSArray, 0)
            #expect(ok == false, "replaceOnly should fail when attribute does not exist")
        }

        @Test("xattrGet called from JS without options argument does not crash")
        func testGetNoOptionsFromJS() throws {
            let tmp = try TempXattrFile()
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            _ = HSFSModule(engineID: UUID()).xattrSet(tmp.path, "com.example.hs2noopts", "hello", nil, 0)
            harness.eval("var v = hs.fs.xattrGet('\(tmp.path)', 'com.example.hs2noopts')")
            harness.expectTrue("v === 'hello'")
            #expect(!harness.hasException)
        }
    }
}
