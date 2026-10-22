//
//  JSExportRuntime.swift
//  Hammerspoon 2Tests
//

import Foundation
import ObjectiveC
@testable import Hammerspoon_2

/// The members of one of the app's JSExport protocols, as JavaScriptCore sees them, read from the
/// Objective-C runtime. Only the protocol's own members are listed, not those of the protocols it
/// inherits from: JavaScriptCore exports each protocol's members separately.
struct ExportedProtocol {
    let name: String
    /// Selectors of the required instance methods, without property accessors or initializers
    var instanceMethods: [String] = []
    /// Selectors of the required class methods, without property accessors
    var classMethods: [String] = []
    var instanceProperties: [String] = []
    var classProperties: [String] = []
    /// Selectors of the initializers, which JavaScriptCore uses for `new` rather than exporting
    var initializers: [String] = []

    var instanceMethodNames: Set<String> { Set(instanceMethods.map(NullReturnsInstaller.jsName(forSelector:))) }
    var classMethodNames: Set<String> { Set(classMethods.map(NullReturnsInstaller.jsName(forSelector:))) }

    /// Whether a selector is in the Objective-C `init` method family: ignoring leading
    /// underscores, it starts with `init`, followed by anything other than a lowercase letter.
    static func isInitializer(_ selector: String) -> Bool {
        let name = selector.drop { $0 == "_" }
        guard name.hasPrefix("init") else { return false }
        guard let next = name.dropFirst(4).first else { return true }
        return !next.isLowercase
    }

    /// Every JSExport protocol (other than JSExport itself) declared in the app's Swift module and
    /// adopted, directly or by inheritance, by a class in the app binary. System frameworks and
    /// Swift packages (like JavaScriptCoreExtras, linked into the app binary) have JSExport
    /// protocols of their own, which aren't ours to check.
    static func all() throws -> [ExportedProtocol] {
        guard let jsExport = objc_getProtocol("JSExport") else { throw IntrospectionError.noJSExport }
        var seen = Set<String>()
        var result: [ExportedProtocol] = []
        for cls in try appClasses() {
            for proto in NullReturnsInstaller.exportedProtocols(of: cls, jsExport: jsExport) {
                let runtimeName = String(cString: protocol_getName(proto))
                guard runtimeName.hasPrefix(modulePrefix), seen.insert(runtimeName).inserted else { continue }
                result.append(ExportedProtocol(proto, name: String(runtimeName.dropFirst(modulePrefix.count))))
            }
        }
        return result
    }

    /// The Swift runtime names the app's @objc protocols `Hammerspoon_2.HSFooAPI`
    private static let modulePrefix = String(String(reflecting: ModuleRoot.self).prefix { $0 != "." }) + "."

    /// Every class in the app binary
    static func appClasses() throws -> [AnyClass] {
        guard let image = class_getImageName(ModuleRoot.self) else { throw IntrospectionError.noAppImage }
        var classCount: UInt32 = 0
        guard let classNames = objc_copyClassNamesForImage(image, &classCount) else { throw IntrospectionError.noAppImage }
        defer { free(UnsafeMutableRawPointer(classNames)) }
        return UnsafeBufferPointer(start: classNames, count: Int(classCount)).compactMap { objc_getClass($0) as? AnyClass }
    }

    enum IntrospectionError: Error {
        case noJSExport, noAppImage
    }

    private init(_ proto: Protocol, name: String) {
        self.name = name
        let (instanceProperties, instanceAccessors) = Self.properties(of: proto, isInstance: true)
        let (classProperties, classAccessors) = Self.properties(of: proto, isInstance: false)
        self.instanceProperties = instanceProperties
        self.classProperties = classProperties

        for selector in Self.methods(of: proto, isInstance: true) where !instanceAccessors.contains(selector) {
            if Self.isInitializer(selector) {
                initializers.append(selector)
            } else {
                instanceMethods.append(selector)
            }
        }
        classMethods = Self.methods(of: proto, isInstance: false).filter { !classAccessors.contains($0) }
    }

    /// The selectors of a protocol's required methods. JavaScriptCore only exports required ones.
    private static func methods(of proto: Protocol, isInstance: Bool) -> [String] {
        var count: UInt32 = 0
        guard let methods = protocol_copyMethodDescriptionList(proto, true, isInstance, &count) else { return [] }
        defer { free(methods) }
        return UnsafeBufferPointer(start: methods, count: Int(count)).compactMap { method in
            method.name.map(NSStringFromSelector)
        }
    }

    /// The names of a protocol's required properties, and the selectors of their accessors
    /// (which are in its method list too, but JavaScriptCore installs as accessors).
    private static func properties(of proto: Protocol, isInstance: Bool) -> (names: [String], accessors: Set<String>) {
        var count: UInt32 = 0
        guard let properties = protocol_copyPropertyList2(proto, &count, true, isInstance) else { return ([], []) }
        defer { free(UnsafeMutableRawPointer(properties)) }
        var names: [String] = []
        var accessors = Set<String>()
        for property in UnsafeBufferPointer(start: properties, count: Int(count)) {
            let name = String(cString: property_getName(property))
            names.append(name)
            accessors.insert(attribute("G", of: property) ?? name)
            if attribute("R", of: property) == nil {
                accessors.insert(attribute("S", of: property) ?? "set\(name.prefix(1).uppercased())\(name.dropFirst()):")
            }
        }
        return (names, accessors)
    }

    private static func attribute(_ code: String, of property: objc_property_t) -> String? {
        guard let value = property_copyAttributeValue(property, code) else { return nil }
        defer { free(value) }
        return String(cString: value)
    }
}
