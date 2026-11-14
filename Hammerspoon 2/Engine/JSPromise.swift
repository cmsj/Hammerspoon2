//
//  JSPromise.swift
//  Hammerspoon 2
//

import HammerspoonSDK

/// JavaScriptCoreExtras declares a `JSPromise` of its own. In the app, the name means the SDK's,
/// which is what modules return to JS and what the docs pipeline recognises as a Promise. A
/// declaration in this module takes precedence over both imports.
typealias JSPromise = HammerspoonSDK.JSPromise
