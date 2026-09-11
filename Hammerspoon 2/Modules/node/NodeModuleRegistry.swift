//
//  NodeModuleRegistry.swift
//  Hammerspoon 2
//

import JavaScriptCore
import JavaScriptCoreExtras

/// Installs the native backing objects for Node's built-in modules, keyed by the name JS code
/// passes to `require(...)`.
///
/// `require.js` has no npm/node_modules-style package resolution; bare specifiers (eg.
/// `require('util')`) are looked up in this hard-coded registry instead. Adding a new built-in
/// module means adding its native object here — no changes to `require.js` are needed.
struct NodeBuiltinModulesInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        let builtins = JSValue(newObjectIn: context)!
        builtins.setObject(NodeUtilModule(), forKeyedSubscript: "util" as NSString)
        context.setObject(builtins, forKeyedSubscript: "_hs_node_builtins" as NSString)
    }
}
