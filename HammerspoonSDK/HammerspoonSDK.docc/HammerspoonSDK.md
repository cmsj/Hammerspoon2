# ``HammerspoonSDK``

Build extensions that add native code to Hammerspoon 2.

## Overview

HammerspoonSDK is the framework Hammerspoon 2's own modules are built on. Extensions link
against it to give JavaScript access to Swift code: an extension's module conforms to
``HSModuleAPI``, and scripts load it with `require('ext:<name>')`.

```swift
import JavaScriptCore
import HammerspoonSDK

@MainActor @objc protocol ExampleModuleAPI: JSExport {
    /// Adds two numbers
    @objc func add(_ a: Double, _ b: Double) -> Double
}

@objc(ComExampleHelloModule)
final class ExampleModule: NSObject, HSModuleAPI, ExampleModuleAPI {
    let moduleName = "com.example.hello"
    let engineID: UUID

    init(engineID: UUID) {
        self.engineID = engineID
        super.init()
    }

    func shutdown() {}

    func toString() -> String { "<\(moduleName)>" }

    func add(_ a: Double, _ b: Double) -> Double { a + b }
}
```

The [Extensions guide](https://cmsj.github.io/Hammerspoon2/main/js/extensions-guide.html)
explains how to build, sign and install an extension, and the rules it must follow.

The framework is built with library evolution, so an extension built against one version of
the SDK keeps working with later versions that have the same major version. See ``HSSDKVersion``.

## Topics

### Modules

- ``HSModuleAPI``
- ``HSEventName``

### SDK versions

- ``HSSDK``
- ``HSSDKVersion``

### Callbacks and object lifetimes

- ``JSCallback``
- ``HSObjectTracker``
- ``HSTrackedObject``
- ``HSActiveObjects``
- ``JSExtraMemory``

### Promises

- ``wrapAsyncInJSPromise(in:body:)``
- ``JSPromiseHolder``
- ``JSPromise``
- ``JSFunction``

### Shared types

- ``HSTypeAPI``
- ``JSConvertible``
- ``HSColor``
- ``HSColorAPI``
- ``HSFont``
- ``HSFontAPI``
- ``HSImage``
- ``HSImageAPI``
- ``HSPoint``
- ``HSPointAPI``
- ``HSRect``
- ``HSRectAPI``
- ``HSSize``
- ``HSSizeAPI``
- ``HSString``
- ``HSStringAPI``
- ``HSVideo``
- ``HSVideoAPI``

### Logging

- ``AKInfo(_:)``
- ``AKWarning(_:)``
- ``AKError(_:)``
- ``AKDebug(_:)``
- ``AKGarbage(_:)``
- ``HammerspoonLogType``
