//
//  JSExportNamingTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
import ObjectiveC
@testable import Hammerspoon_2

/// Checks the names of JSExport protocol methods.
///
/// Objective-C methods whose selectors are in the alloc/new/copy/mutableCopy families return an
/// object with an extra retain that the caller must release. JavaScriptCore doesn't release it, so
/// every object such a method returns to JS leaks (#309). This checks that no JSExport protocol
/// declares one, and that each method's JS name is the one the docs give it.
@Suite("JSExport naming tests")
struct JSExportNamingTests {

    private static let retainedFamilies = ["alloc", "new", "copy", "mutableCopy"]

    /// The ObjC method family rules: ignoring leading underscores, the selector starts with the
    /// family name, followed by anything other than a lowercase letter.
    private static func retainedFamily(of selector: String) -> String? {
        let name = selector.drop { $0 == "_" }
        return retainedFamilies.first { family in
            guard name.hasPrefix(family) else { return false }
            guard let next = name.dropFirst(family.count).first else { return true }
            return !next.isLowercase
        }
    }

    /// Whether an ObjC method type encoding returns an object, skipping type qualifiers.
    private static func returnsObject(_ types: UnsafePointer<CChar>?) -> Bool {
        guard let types else { return false }
        let encoding = String(cString: types).drop { "rnNoORV".contains($0) }
        return encoding.first == "@"
    }

    /// Every protocol adopted, directly or by inheritance, by a class in the app binary. System
    /// frameworks have JSExport protocols of their own (SceneKit's declare `-copy`), which aren't ours to check.
    private static func appProtocols() throws -> [Protocol] {
        let image = try #require(class_getImageName(HSImage.self))
        var classCount: UInt32 = 0
        let classNames = try #require(objc_copyClassNamesForImage(image, &classCount))
        defer { free(UnsafeMutableRawPointer(classNames)) }

        var seen = Set<String>()
        var result: [Protocol] = []
        func visit(_ proto: Protocol) {
            guard seen.insert(String(cString: protocol_getName(proto))).inserted else { return }
            result.append(proto)
            var count: UInt32 = 0
            guard let inherited = protocol_copyProtocolList(proto, &count) else { return }
            defer { free(UnsafeMutableRawPointer(inherited)) }
            UnsafeBufferPointer(start: inherited, count: Int(count)).forEach(visit)
        }
        for name in UnsafeBufferPointer(start: classNames, count: Int(classCount)) {
            guard let cls = objc_getClass(name) as? AnyClass else { continue }
            var count: UInt32 = 0
            guard let adopted = class_copyProtocolList(cls, &count) else { continue }
            defer { free(UnsafeMutableRawPointer(adopted)) }
            UnsafeBufferPointer(start: adopted, count: Int(count)).forEach(visit)
        }
        return result
    }

    @Test("Method family detection matches the Objective-C rules")
    func familyDetection() {
        #expect(Self.retainedFamily(of: "copyImage") == "copy")
        #expect(Self.retainedFamily(of: "copy::") == "copy")
        #expect(Self.retainedFamily(of: "newWindow:") == "new")
        #expect(Self.retainedFamily(of: "mutableCopy") == "mutableCopy")
        #expect(Self.retainedFamily(of: "_allocThing") == "alloc")
        #expect(Self.retainedFamily(of: "copyright") == nil)
        #expect(Self.retainedFamily(of: "newline") == nil)
        #expect(Self.retainedFamily(of: "duplicate") == nil)
        #expect(Self.retainedFamily(of: "croppedCopy:") == nil)
    }

    @Test("No JSExport method that returns an object is in a retained-result method family")
    func noRetainedFamilyMethods() throws {
        let jsExport = try #require(objc_getProtocol("JSExport"))
        var checked = 0
        var offenders: [String] = []
        for proto in try Self.appProtocols() {
            guard !protocol_isEqual(proto, jsExport), protocol_conformsToProtocol(proto, jsExport) else { continue }
            checked += 1
            let protoName = String(cString: protocol_getName(proto))
            for (isRequired, isInstance) in [(true, true), (true, false), (false, true), (false, false)] {
                var methodCount: UInt32 = 0
                guard let methods = protocol_copyMethodDescriptionList(proto, isRequired, isInstance, &methodCount) else { continue }
                defer { free(methods) }
                for method in UnsafeBufferPointer(start: methods, count: Int(methodCount)) {
                    guard let selector = method.name else { continue }
                    let selectorName = NSStringFromSelector(selector)
                    if let family = Self.retainedFamily(of: selectorName), Self.returnsObject(method.types) {
                        offenders.append("\(protoName) \(isInstance ? "-" : "+")\(selectorName) (\(family) family)")
                    }
                }
            }
        }

        #expect(checked > 0, "Found no JSExport protocols to check")
        #expect(offenders.isEmpty, "JSExport methods in a retained-result method family leak every object they return to JS. Rename them: \(offenders.joined(separator: ", "))")
    }

    /// Whether a selector has no argument labels: a name followed only by colons, like `foo::`.
    private static func isUnlabeled(_ selector: String) -> Bool {
        selector.wholeMatch(of: #/[A-Za-z_][A-Za-z0-9_]*:*/#) != nil
    }

    @Test("Unlabeled selector detection")
    func unlabeledDetection() {
        #expect(Self.isUnlabeled("reload"))
        #expect(Self.isUnlabeled("custom::"))
        #expect(Self.isUnlabeled("_addWatcher:"))
        #expect(!Self.isUnlabeled("custom:size:"))
        #expect(!Self.isUnlabeled("doThis:withThat:"))
    }

    /// JavaScriptCore names a method after its whole selector, so `custom(_ name:, size:)` (selector
    /// `custom:size:`) is `customSize` in JS, but the docs call it `custom` (#331). With every
    /// argument unlabeled (`_ size:`), the JS name is the Swift base name. A labeled first argument
    /// (`foo(bar:)` is `fooWithBar:`) looks unlabeled here; JSExportDocsTests catches that one.
    @Test("Every JSExport method's JS name is its Swift base name")
    func everyMethodIsUnlabeled() throws {
        var offenders: [String] = []
        for proto in try ExportedProtocol.all() {
            for (selectors, kind) in [(proto.instanceMethods, "-"), (proto.classMethods, "+")] {
                for selector in selectors where !Self.isUnlabeled(selector) {
                    offenders.append("\(proto.name) \(kind)\(selector) (\(NullReturnsInstaller.jsName(forSelector: selector)) in JS)")
                }
            }
        }
        #expect(offenders.isEmpty, "These methods have argument labels, which become part of their JS name. Use `_` for every argument label: \(offenders.joined(separator: ", "))")
    }

    /// Two selectors with the same JS name, like `system:` and `system::`, clash: only one of them
    /// is reachable from JS.
    @Test("No two members of a JSExport protocol have the same JS name")
    func noJSNameCollisions() throws {
        var offenders: [String] = []
        for proto in try ExportedProtocol.all() {
            let instanceNames = proto.instanceMethods.map(NullReturnsInstaller.jsName(forSelector:)) + proto.instanceProperties
            let classNames = proto.classMethods.map(NullReturnsInstaller.jsName(forSelector:)) + proto.classProperties
            for (names, kind) in [(instanceNames, "-"), (classNames, "+")] {
                let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys
                offenders += duplicates.sorted().map { "\(proto.name) \(kind)\($0)" }
            }
        }
        #expect(offenders.isEmpty, "These JS names are declared more than once, so all but one are unreachable: \(offenders.joined(separator: ", "))")
    }
}
