//
//  NullReturnsInstaller.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import ObjectiveC

/// JavaScriptCore turns a nil object returned by an Objective-C method or property into
/// `undefined`, not `null`, so `=== null` checks in user scripts never match. This installer wraps
/// every JSExport method and property getter that returns an object, on each exported class's JS
/// prototype (and constructor, for class members), so that nil reaches JS as `null`. Members that
/// return a scalar or `Void` are left alone, so they still return `undefined` where they should,
/// as are the members in `passthroughMembers`.
///
/// Must be installed before any user code runs: the wrappers capture `Reflect.apply` and friends
/// when they're installed, so user scripts can't interfere with them by replacing those later.
struct NullReturnsInstaller: JSContextInstallable {
    /// The members of one exported class that return an object, by their JS names.
    struct ExportedClass {
        let name: String
        var instanceMethods: [String] = []
        var instanceGetters: [String] = []
        var classMethods: [String] = []
        var classGetters: [String] = []
    }

    /// Members that return a JSValue holding whatever some JS code returned, so an `undefined`
    /// from them is deliberate rather than nil, and mustn't become `null`.
    nonisolated static let passthroughMembers: [(cls: AnyClass, member: String)] = [
        (HSFSModule.self, "withFile"),  // the callback's result
        (StatementSync.self, "get"),    // undefined when there's no row, as in Node
    ]

    /// Every class in the app binary that exports a member returning an object. The ObjC runtime
    /// doesn't change after launch, so this is only worked out once.
    nonisolated static let exportedClasses: [ExportedClass] = findExportedClasses()

    func install(in context: JSContext) throws {
        let installer = context.evaluateScript("""
            (function () {
                'use strict';
                const apply = Reflect.apply;
                const getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
                const defineProperty = Object.defineProperty;

                // JavaScriptCore only weakly holds the prototypes it makes for ObjC classes, and
                // makes a fresh, unwrapped one if a prototype is collected while the class has no
                // instances, so every patched constructor is kept here for the context's lifetime.
                const pinned = [];
                defineProperty(globalThis, Symbol('hs.nullReturns'), { value: pinned });

                // JavaScriptCore's native functions have an empty name, so use the property name
                function rename(wrapper, name) {
                    defineProperty(wrapper, 'name', { value: name });
                    return wrapper;
                }

                return function (constructor, target, methods, getters) {
                    pinned[pinned.length] = constructor;
                    for (let i = 0; i < methods.length; i++) {
                        const descriptor = getOwnPropertyDescriptor(target, methods[i]);
                        if (!descriptor || typeof descriptor.value !== 'function') continue;
                        const original = descriptor.value;
                        descriptor.value = rename(function () {
                            const result = apply(original, this, arguments);
                            return result === undefined ? null : result;
                        }, methods[i]);
                        defineProperty(target, methods[i], descriptor);
                    }
                    for (let i = 0; i < getters.length; i++) {
                        const descriptor = getOwnPropertyDescriptor(target, getters[i]);
                        if (!descriptor || typeof descriptor.get !== 'function') continue;
                        const original = descriptor.get;
                        descriptor.get = rename(function () {
                            const result = apply(original, this, []);
                            return result === undefined ? null : result;
                        }, getters[i]);
                        defineProperty(target, getters[i], descriptor);
                    }
                };
            })()
            """)
        guard let installer, installer.isObject else {
            throw HammerspoonError(.vmCreation, msg: "Failed to create the null returns installer")
        }

        for exported in Self.exportedClasses {
            guard let cls = unsafe objc_getClass(exported.name) as? AnyClass,
                  let constructor = JSValue(object: cls, in: context),
                  let prototype = constructor.forProperty("prototype"), prototype.isObject else {
                AKWarning("NullReturnsInstaller: no JS prototype for \(exported.name)")
                continue
            }
            installer.call(withArguments: [constructor, prototype, exported.instanceMethods, exported.instanceGetters])
            if !exported.classMethods.isEmpty || !exported.classGetters.isEmpty {
                installer.call(withArguments: [constructor, constructor, exported.classMethods, exported.classGetters])
            }
        }
    }

    // MARK: - Runtime introspection

    /// Finds the object-returning members that JavaScriptCore exports for each class in the app
    /// binary, following the same rules it does: a class exports the members of every protocol it
    /// adopts directly that inherits from JSExport (plus that protocol's own JSExport ancestors),
    /// onto its own prototype. Superclasses export theirs onto their own prototypes.
    nonisolated static func findExportedClasses() -> [ExportedClass] {
        guard let jsExport = unsafe objc_getProtocol("JSExport"),
              let image = unsafe class_getImageName(ModuleRoot.self) else { return [] }
        var classCount: UInt32 = 0
        guard let classNames = unsafe objc_copyClassNamesForImage(image, &classCount) else { return [] }
        defer { unsafe free(UnsafeMutableRawPointer(classNames)) }

        var result: [ExportedClass] = []
        for unsafe name in unsafe UnsafeBufferPointer(start: classNames, count: Int(classCount)) {
            guard let cls = unsafe objc_getClass(name) as? AnyClass else { continue }
            var exported = unsafe ExportedClass(name: String(cString: name))
            for proto in exportedProtocols(of: cls, jsExport: jsExport) {
                exported.instanceMethods += objectReturningMethods(of: proto, isInstance: true)
                exported.instanceGetters += objectReturningGetters(of: proto, isInstance: true)
                exported.classMethods += objectReturningMethods(of: proto, isInstance: false)
                exported.classGetters += objectReturningGetters(of: proto, isInstance: false)
            }
            for passthrough in passthroughMembers where passthrough.cls === cls {
                exported.instanceMethods.removeAll { $0 == passthrough.member }
                exported.instanceGetters.removeAll { $0 == passthrough.member }
            }
            if !(exported.instanceMethods.isEmpty && exported.instanceGetters.isEmpty
                 && exported.classMethods.isEmpty && exported.classGetters.isEmpty) {
                result.append(exported)
            }
        }
        return result
    }

    /// The protocols adopted directly by `cls`, and the protocols they inherit, that inherit from
    /// JSExport.
    nonisolated static func exportedProtocols(of cls: AnyClass, jsExport: Protocol) -> [Protocol] {
        var seen = Set<String>()
        var result: [Protocol] = []
        func visit(_ proto: Protocol) {
            guard unsafe seen.insert(String(cString: protocol_getName(proto))).inserted else { return }
            if !protocol_isEqual(proto, jsExport), protocol_conformsToProtocol(proto, jsExport) {
                result.append(proto)
            }
            var count: UInt32 = 0
            guard let inherited = unsafe protocol_copyProtocolList(proto, &count) else { return }
            defer { unsafe free(UnsafeMutableRawPointer(inherited)) }
            unsafe UnsafeBufferPointer(start: inherited, count: Int(count)).forEach(visit)
        }
        var count: UInt32 = 0
        guard let adopted = unsafe class_copyProtocolList(cls, &count) else { return [] }
        defer { unsafe free(UnsafeMutableRawPointer(adopted)) }
        unsafe UnsafeBufferPointer(start: adopted, count: Int(count)).forEach(visit)
        return result
    }

    /// The JS names of a protocol's required methods that return an object. JavaScriptCore only
    /// exports required methods. Property accessors are in this list too, but they're installed
    /// as accessors rather than functions, so the JS side skips them.
    private nonisolated static func objectReturningMethods(of proto: Protocol, isInstance: Bool) -> [String] {
        var count: UInt32 = 0
        guard let methods = unsafe protocol_copyMethodDescriptionList(proto, true, isInstance, &count) else { return [] }
        defer { unsafe free(methods) }
        return unsafe UnsafeBufferPointer(start: methods, count: Int(count)).compactMap { method in
            guard let selector = unsafe method.name, unsafe returnsObject(method.types) else { return nil }
            return jsName(forSelector: NSStringFromSelector(selector))
        }
    }

    /// The names of a protocol's required properties whose type is an object.
    private nonisolated static func objectReturningGetters(of proto: Protocol, isInstance: Bool) -> [String] {
        var count: UInt32 = 0
        guard let properties = unsafe protocol_copyPropertyList2(proto, &count, true, isInstance) else { return [] }
        defer { unsafe free(UnsafeMutableRawPointer(properties)) }
        return unsafe UnsafeBufferPointer(start: properties, count: Int(count)).compactMap { property in
            guard let attributes = unsafe property_getAttributes(property),
                  unsafe String(cString: attributes).hasPrefix("T@") else { return nil }
            return unsafe String(cString: property_getName(property))
        }
    }

    /// Whether an ObjC method type encoding returns an object, skipping type qualifiers.
    nonisolated static func returnsObject(_ types: UnsafePointer<CChar>?) -> Bool {
        guard let types = unsafe types else { return false }
        return unsafe String(cString: types).drop { "rnNoORV".contains($0) }.first == "@"
    }

    /// The name JavaScriptCore gives a selector: each colon is dropped and the character after it
    /// is uppercased, so `foo:bar:` becomes `fooBar`.
    nonisolated static func jsName(forSelector selector: String) -> String {
        var name = ""
        var uppercaseNext = false
        for character in selector {
            if character == ":" {
                uppercaseNext = true
                continue
            }
            name.append(uppercaseNext ? Character(character.uppercased()) : character)
            uppercaseNext = false
        }
        return name
    }
}
