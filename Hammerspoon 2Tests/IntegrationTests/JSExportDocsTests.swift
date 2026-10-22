//
//  JSExportDocsTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
import ObjectiveC
@testable import Hammerspoon_2

/// Checks that the API documented in the bundled api.json (generated from the `///` comments by
/// `npm run docs:generate`) is the API JavaScript actually sees, in both directions: everything
/// documented exists under that name, and everything exported is documented (or marked
/// SKIP_DOCS). The docs take a method's name from its Swift declaration, while JavaScriptCore
/// takes it from the Objective-C selector, so the two can disagree (#331).
@Suite("JSExport docs tests")
struct JSExportDocsTests {

    // MARK: - api.json

    struct APIDocs: Decodable {
        let modules: [Namespace]
        let types: [Namespace]
        let skipped: Skipped

        struct Namespace: Decodable {
            let name: String
            let methods: [Member]?
            let properties: [Member]?
            let types: [Namespace]?
        }

        struct Member: Decodable {
            let name: String
            let protocolName: String?
            let isStatic: Bool?
            let source: String?

            enum CodingKeys: String, CodingKey {
                case name, isStatic, source
                case protocolName = "protocol"
            }
        }

        struct Skipped: Decodable {
            let protocols: [String]
            let members: [SkippedMember]
        }

        struct SkippedMember: Decodable {
            let name: String
            let protocolName: String

            enum CodingKeys: String, CodingKey {
                case name
                case protocolName = "protocol"
            }
        }

        /// Every documented namespace, including the types nested in modules
        var allNamespaces: [Namespace] {
            func flatten(_ namespaces: [Namespace]) -> [Namespace] {
                namespaces.flatMap { [$0] + flatten($0.types ?? []) }
            }
            return flatten(modules + types)
        }
    }

    /// A documented member of a Swift protocol
    struct DocumentedMember: Hashable {
        enum Kind { case method, property }
        let protocolName: String
        let name: String
        let kind: Kind
        let isStatic: Bool
    }

    private static func loadDocs() throws -> APIDocs {
        let url = try #require(Bundle.main.url(forResource: "api", withExtension: "json"), "api.json isn't in the app bundle")
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(APIDocs.self, from: data)
        } catch {
            Issue.record("Couldn't read api.json (a Debug build without npm bundles an empty placeholder; run `npm run docs:generate`): \(error)")
            throw error
        }
    }

    private static func swiftMembers(of docs: APIDocs) -> [DocumentedMember] {
        docs.allNamespaces.flatMap { namespace in
            let methods = (namespace.methods ?? []).compactMap { member in
                member.protocolName.map { DocumentedMember(protocolName: $0, name: member.name, kind: .method, isStatic: member.isStatic ?? false) }
            }
            let properties = (namespace.properties ?? []).compactMap { member in
                member.protocolName.map { DocumentedMember(protocolName: $0, name: member.name, kind: .property, isStatic: false) }
            }
            return methods + properties
        }
    }

    /// Protocols that every module or type inherits. Their members are the same everywhere and
    /// aren't documented per module.
    private static let baseProtocols: Set<String> = ["HSModuleAPI", "HSTypeAPI"]

    // MARK: - Tests

    @Test("Every documented Swift member exists in JS under its documented name")
    func documentedMembersExist() throws {
        let docs = try Self.loadDocs()
        let exported = Dictionary(uniqueKeysWithValues: try ExportedProtocol.all().map { ($0.name, $0) })
        let documented = Self.swiftMembers(of: docs)
        #expect(!documented.isEmpty, "api.json documents no Swift members")

        var missing: [String] = []
        for member in documented {
            guard let proto = exported[member.protocolName] else {
                missing.append("\(member.protocolName) (documented, but no class exports it)")
                continue
            }
            let exists = switch (member.kind, member.name) {
            case (.method, "init"): !proto.initializers.isEmpty
            case (.method, _): (member.isStatic ? proto.classMethodNames : proto.instanceMethodNames).contains(member.name)
            case (.property, _): proto.instanceProperties.contains(member.name) || proto.classProperties.contains(member.name)
            }
            if !exists {
                let available = (member.isStatic ? proto.classMethodNames : proto.instanceMethodNames).sorted()
                missing.append("\(member.protocolName).\(member.name) (JS has: \(available.joined(separator: ", ")))")
            }
        }
        #expect(missing.isEmpty, "Documented, but not in JS under that name: \(Array(Set(missing)).sorted().joined(separator: "; "))")
    }

    @Test("Every JSExport member is documented or marked SKIP_DOCS")
    func exportedMembersAreDocumented() throws {
        let docs = try Self.loadDocs()
        let documented = Set(Self.swiftMembers(of: docs).map { "\($0.protocolName).\($0.name)" })
        let skippedMembers = Set(docs.skipped.members.map { "\($0.protocolName).\($0.name)" })
        let skippedProtocols = Set(docs.skipped.protocols)
        let moduleNames = Set(docs.modules.map(\.name))

        var undocumented: [String] = []
        for proto in try ExportedProtocol.all() {
            guard !Self.baseProtocols.contains(proto.name), !skippedProtocols.contains(proto.name) else { continue }
            let names = proto.instanceMethods.map(NullReturnsInstaller.jsName(forSelector:))
                + proto.classMethods.map(NullReturnsInstaller.jsName(forSelector:))
                + proto.instanceProperties + proto.classProperties
                + (proto.initializers.isEmpty ? [] : ["init"])
            for name in names {
                let key = "\(proto.name).\(name)"
                guard !documented.contains(key), !skippedMembers.contains(key) else { continue }
                // ModuleRoot's module accessors are documented as the modules themselves
                if proto.name == "ModuleRootAPI", moduleNames.contains("hs.\(name)") { continue }
                undocumented.append(key)
            }
        }
        #expect(undocumented.isEmpty, "Exported to JS, but not in the docs (document them, or mark them SKIP_DOCS): \(undocumented.sorted().joined(separator: ", "))")
    }

    /// Methods a module's `hs.foo.js` adds aren't in any protocol, so they're looked for on the
    /// module object, with its enhancement script loaded.
    @Test("Every documented JavaScript method exists on its module")
    @MainActor
    func documentedJavaScriptMethodsExist() throws {
        let docs = try Self.loadDocs()
        var missing: [String] = []
        var checked = 0
        for module in docs.modules where module.name.hasPrefix("hs.") {
            let jsMethods = (module.methods ?? []).filter { $0.source == "javascript" }.map(\.name)
            guard !jsMethods.isEmpty else { continue }
            let shortName = String(module.name.dropFirst(3))
            guard let moduleType = Self.moduleType(forAccessor: shortName) else {
                missing.append("\(module.name) (no hs.\(shortName) accessor on ModuleRoot)")
                continue
            }
            let harness = JSTestHarness()
            harness.loadModule(moduleType, as: shortName)
            for method in jsMethods {
                checked += 1
                if harness.evalTypeOf("\(module.name).\(method)") != "function" {
                    missing.append("\(module.name).\(method)")
                }
            }
        }
        #expect(checked > 0, "api.json documents no JavaScript methods")
        #expect(missing.isEmpty, "Documented, but not a function in JS: \(missing.joined(separator: ", "))")
    }

    /// The test's model of what JavaScriptCore exports (`ExportedProtocol` and
    /// `NullReturnsInstaller.jsName(forSelector:)`) is checked against the prototypes and
    /// constructors JavaScriptCore really makes for every exported class.
    @Test("ExportedProtocol matches what JavaScriptCore exports")
    func runtimeModelMatchesJavaScriptCore() throws {
        let jsExport = try #require(objc_getProtocol("JSExport"))
        let exported = Dictionary(uniqueKeysWithValues: try ExportedProtocol.all().map { ($0.name, $0) })
        let context = try #require(JSContext())
        let ownKeys = try #require(context.evaluateScript("(o) => Reflect.ownKeys(o).filter(k => typeof k === 'string')"))
        // Every prototype has a constructor, and every constructor (a function) these
        let prototypeBuiltins: Set<String> = ["constructor"]
        let constructorBuiltins: Set<String> = ["prototype", "length", "name"]

        var mismatches: [String] = []
        var checked = 0
        for cls in try ExportedProtocol.appClasses() {
            let protocols = NullReturnsInstaller.exportedProtocols(of: cls, jsExport: jsExport)
                .compactMap { exported[String(String(cString: protocol_getName($0)).split(separator: ".").last ?? "")] }
            guard !protocols.isEmpty else { continue }
            checked += 1
            let expectedInstance = protocols.reduce(into: Set<String>()) { $0.formUnion($1.instanceMethodNames.union($1.instanceProperties)) }
            let expectedClass = protocols.reduce(into: Set<String>()) { $0.formUnion($1.classMethodNames.union($1.classProperties)) }

            guard let constructor = JSValue(object: cls, in: context),
                  let prototype = constructor.forProperty("prototype"), prototype.isObject else {
                mismatches.append("\(cls): no JS constructor")
                continue
            }
            let actualInstance = Set(ownKeys.call(withArguments: [prototype]).toArray()?.compactMap { $0 as? String } ?? []).subtracting(prototypeBuiltins)
            let actualClass = Set(ownKeys.call(withArguments: [constructor]).toArray()?.compactMap { $0 as? String } ?? []).subtracting(constructorBuiltins)
            if actualInstance != expectedInstance {
                mismatches.append("\(cls) prototype: missing \(expectedInstance.subtracting(actualInstance).sorted()), unexpected \(actualInstance.subtracting(expectedInstance).sorted())")
            }
            if actualClass != expectedClass {
                mismatches.append("\(cls) constructor: missing \(expectedClass.subtracting(actualClass).sorted()), unexpected \(actualClass.subtracting(expectedClass).sorted())")
            }
        }
        #expect(checked > 0, "Found no exported classes")
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "; "))")
    }

    /// The module class behind one of ModuleRoot's `hs.foo` accessors, from its property type
    private static func moduleType(forAccessor name: String) -> (any HSModuleAPI.Type)? {
        guard let property = class_getProperty(ModuleRoot.self, name),
              let attributes = property_getAttributes(property) else { return nil }
        // e.g. T@"_TtC13Hammerspoon_214HSWindowModule",R,N
        let typeAttribute = String(cString: attributes).split(separator: ",").first ?? ""
        guard typeAttribute.hasPrefix("T@\""), typeAttribute.hasSuffix("\"") else { return nil }
        let className = String(typeAttribute.dropFirst(3).dropLast())
        return NSClassFromString(className) as? any HSModuleAPI.Type
    }
}
