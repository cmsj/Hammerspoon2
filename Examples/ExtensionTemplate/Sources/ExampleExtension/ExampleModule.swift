//
//  ExampleModule.swift
//  ExampleExtension
//
//  A minimal Hammerspoon 2 extension. Load it with:
//
//      const example = require('ext:com.example.hello')
//      example.add(2, 3)          // 5
//      example.greet('world')     // "Hello, world!", from Bundle/com.example.hello.js
//

import Foundation
import JavaScriptCore
import HammerspoonSDK

/// What JavaScript can see of the extension. Everything a JS enhancement script sets on the
/// module (here, `greet`) must be declared, or it's lost when JavaScriptCore collects the module's
/// wrapper.
@objc protocol ExampleModuleAPI: JSExport {
    /// Adds two numbers
    @objc func add(_ a: Double, _ b: Double) -> Double

    /// A colour, using one of the SDK's shared types
    @objc func accentColor() -> HSColor

    /// Set by Bundle/com.example.hello.js
    @objc var greet: JSValue? { get set }
}

/// The extension's module, named in Bundle/Info.plist's NSPrincipalClass. Its Objective-C name has
/// a prefix because every class shares one namespace with Hammerspoon 2 and other extensions.
@objc(ComExampleHelloModule)
final class ExampleModule: NSObject, HSModuleAPI, ExampleModuleAPI {
    let moduleName = "com.example.hello"
    let engineID: UUID
    @objc var greet: JSValue?

    init(engineID: UUID) {
        self.engineID = engineID
        super.init()
    }

    /// Called before the config reloads: release everything held from JavaScript
    func shutdown() {
        greet = nil
    }

    func toString() -> String {
        "<\(moduleName)>"
    }

    func add(_ a: Double, _ b: Double) -> Double {
        a + b
    }

    func accentColor() -> HSColor {
        HSColor.rgb(0.2, 0.4, 0.9, 1)
    }
}
