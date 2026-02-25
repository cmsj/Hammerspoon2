//
//  InjectTypes.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 04/11/2025.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

// This is called by the engine to inject types that we want to be available to JavaScript for users to directly instantiate.
// For many types this is not the case, so you should not expect this list to be exhaustive, nor should you add a new HS type here
// without thinking about whether it makes any sense for a user to be able to directly instantiate it.
// e.g. HSWindow does not belong here - for that to happen we would have to create a large number of static methods on the class
// that can do things like search for windows by name, and we would have to be able to fail the creation of a type.
// Better to keep those things in the module API, and keep HSWindow a narrowly-focused type that does not need to concern itself
// with such things.
struct TypeBridgesInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        let typeBridges = [
            "HSPoint": HSPoint.self,
            "HSSize":  HSSize.self,
            "HSRect":  HSRect.self,

            "HSFont":  HSFont.self,
        ]

        typeBridges.forEach { key, value in
            context.setObject(value, forKeyedSubscript: key as NSString)
        }
    }
}
