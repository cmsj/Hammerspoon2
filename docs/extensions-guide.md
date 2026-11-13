Extensions add native code to Hammerspoon 2: compiled Swift, built against the HammerspoonSDK
framework, plus optional JavaScript. Use one when something can't be done from JavaScript alone,
such as wrapping a macOS framework Hammerspoon 2 doesn't cover. For anything that can be written
in JavaScript, write a [Spoon](spoons-guide.html) instead: Spoons are easier to write, can't
crash the app, and don't need to be trusted with its permissions.

## Using extensions

Extensions are off by default. To use them, turn on **Allow extensions** in the Advanced tab of
Settings.

An extension is a bundle named after the extension, such as `com.example.foo.hsmodule`. Put it
in the `Extensions` folder next to your config file (by default,
`~/.config/Hammerspoon2/Extensions`), then load it with `require()` and an `ext:` prefix:

```js
const foo = require('ext:com.example.foo')
foo.doSomething()
```

The first time a config loads an extension, Hammerspoon 2 asks whether to allow it, and shows
who signed it. An extension runs its own code inside Hammerspoon 2, with all of the permissions
you've given Hammerspoon 2, such as Accessibility and Input Monitoring, so only allow extensions
from developers you trust. You're asked again whenever the extension changes. The extensions
you've allowed are listed under **Approved extensions** in the Advanced tab of Settings, where
you can remove them; you're then asked again the next time your config loads one.

An extension's code stays loaded until Hammerspoon 2 quits: macOS can't unload it. If you update
an extension, restart Hammerspoon 2 to use the new version. Reloading your config isn't enough,
and Hammerspoon 2 logs a warning to say so.

If an extension can't be loaded, `require()` throws an `Error` whose `code` says why:

| `code` | Meaning |
| --- | --- |
| `ERR_EXTENSIONS_DISABLED` | Extensions are turned off in Settings |
| `ERR_EXTENSION_INVALID_NAME` | The name isn't a valid extension name |
| `ERR_EXTENSION_NOT_FOUND` | There's no bundle for it in the Extensions folder |
| `ERR_EXTENSION_INVALID_BUNDLE` | The bundle's Info.plist is incomplete or doesn't match its name |
| `ERR_EXTENSION_INCOMPATIBLE_SDK` | It was built for an SDK version this copy of Hammerspoon 2 doesn't provide |
| `ERR_EXTENSION_INVALID_SIGNATURE` | It isn't signed, or it changed after it was signed |
| `ERR_EXTENSION_UNSUPPORTED_BINARY` | Its code isn't built for this Mac's processor |
| `ERR_EXTENSION_OUTDATED_TOOLCHAIN` | It was built with an Xcode older than Hammerspoon 2 supports |
| `ERR_EXTENSION_REQUIRES_NEWER_MACOS` | It needs a later version of macOS |
| `ERR_EXTENSION_BUNDLES_SDK` | It contains its own copy of HammerspoonSDK.framework |
| `ERR_EXTENSION_NOT_APPROVED` | You didn't allow it to load |
| `ERR_EXTENSION_LOAD_FAILED` | Its code couldn't be loaded |
| `ERR_EXTENSION_INVALID_PRINCIPAL_CLASS` | Its principal class isn't an extension module |
| `ERR_EXTENSION_CLASS_COLLISION` | It defines Objective-C classes that already exist |
| `ERR_EXTENSION_RETAINED_RESULT_METHODS` | Its API has methods that would leak memory |

```js
try {
    const foo = require('ext:com.example.foo')
} catch (err) {
    console.error(err.code + ": " + err.message)
}
```

## Writing an extension

An extension is a loadable bundle with this layout:

```
com.example.foo.hsmodule/
  Contents/
    Info.plist
    MacOS/ComExampleFoo            the compiled code
    Resources/com.example.foo.js   optional: JavaScript run when the extension loads
    _CodeSignature/
```

Its Info.plist needs these keys, as well as the usual bundle keys (`CFBundleExecutable`,
`CFBundleIdentifier`, `CFBundlePackageType` = `BNDL`):

| Key | Value |
| --- | --- |
| `HSModuleName` | The extension's name, which must match the bundle's file name, e.g. `com.example.foo`. Use letters, digits, dots, hyphens and underscores, and start with a letter or digit. A reverse-DNS name avoids clashing with anyone else's. |
| `HSSDKVersion` | The HammerspoonSDK version it was built against, e.g. `1.0` |
| `NSPrincipalClass` | The Objective-C name of its module class |

### The module

The principal class is a module, just like Hammerspoon 2's own `hs.*` modules: an `NSObject`
subclass conforming to `HSModuleAPI`, and to a JSExport protocol that declares what JavaScript
can see. Hammerspoon 2 creates one instance per config load and calls `shutdown()` before the
config is reloaded.

```swift
import Foundation
import JavaScriptCore
import HammerspoonSDK

@MainActor
@objc protocol ExampleFooAPI: JSExport {
    /// Adds two numbers
    @objc func add(_ a: Double, _ b: Double) -> Double

    /// A colour, using one of the SDK's shared types
    @objc func red() -> HSColor

    /// Calls `callback` every `interval` seconds once it's started
    @objc func makeTicker(_ interval: Double, _ callback: JSValue) -> ExampleTicker
}

@MainActor
@objc(ExampleFooModule)
final class ExampleFooModule: NSObject, HSModuleAPI, ExampleFooAPI {
    let moduleName = "com.example.foo"
    let engineID: UUID
    private let tickers = HSObjectTracker<ExampleTicker>()

    init(engineID: UUID) {
        self.engineID = engineID
        super.init()
    }

    func shutdown() {
        tickers.shutdown()
    }

    func toString() -> String { "<com.example.foo>" }

    func add(_ a: Double, _ b: Double) -> Double { a + b }

    func red() -> HSColor { HSColor.rgb(1, 0, 0, 1) }

    func makeTicker(_ interval: Double, _ callback: JSValue) -> ExampleTicker {
        let ticker = ExampleTicker(interval: interval, callback: callback, tracker: tickers)
        tickers.add(ticker)
        return ticker
    }
}
```

The test extension in Hammerspoon 2's repository, `Hammerspoon 2Tests/Helpers/TestExtension`, is
a complete working example, including the ticker.

### Rules

These are the same rules Hammerspoon 2's own modules follow. The first five are checked when
the extension loads, and an extension that breaks them is refused.

- **Build with Xcode 27 or later.** Older Swift compilers generate code that can crash
  Hammerspoon 2 when JavaScript's garbage collector frees your objects. Swift binaries don't say
  which compiler built them, so Hammerspoon 2 checks the macOS SDK the extension was built
  with, which comes with the compiler: it must be the macOS 27 SDK or later.
- **Link HammerspoonSDK.framework, but don't embed it.** A second copy would define every SDK
  class twice.

- **Give every Objective-C class a unique name.** All classes share one namespace with
  Hammerspoon 2 and every other extension, so give each `@objc` class an explicit, prefixed
  name: `@objc(ExampleFooModule)`. An extension whose classes clash with loaded ones can't be
  used until Hammerspoon 2 restarts.
- **Never start a method's name with `new`, `alloc`, `copy` or `mutableCopy`** if it returns an
  object. Objective-C returns those with an extra retain that JavaScriptCore never releases, so
  every object they return leaks.
- **Sign the bundle.** An ad-hoc signature (`codesign --sign - Foo.hsmodule`) is enough to load
  it, but a Developer ID signature lets users see who you are when they're asked to allow it.
- **Mark your JSExport protocols `@MainActor`.** JavaScript runs on the main thread, and the
  SDK's protocols are main-actor isolated. Alternatively, build with
  `-default-isolation MainActor`, as Hammerspoon 2 does.
- **Store JavaScript callbacks in a `JSCallback`**, never a `JSValue`, which would keep the
  whole JavaScript context alive.
- **Track the objects you hand to JavaScript with an `HSObjectTracker`**, and keep an object
  active while it has work pending (a running timer, a started watcher), by calling `setActive`
  from the `didSet` of the property that says whether it's running. An active object keeps
  working even if the script drops it; an inactive one is collected normally. Each tracked
  object conforms to `HSTrackedObject`, and the module calls `shutdown()` on each tracker.
- **Release everything in `shutdown()`.** Anything that still references JavaScript after
  `shutdown()` keeps the old config's JavaScript context alive after a reload.
- **Report memory the JavaScript heap can't see**, with `JSExtraMemory.report(_:)`, for objects
  that hold a lot of native memory, such as images.
- **Create Promises in the calling context**, with
  `wrapAsyncInJSPromise(in: JSContext.current()!) { holder in ... }`.

Return `nil` from an optional method and JavaScript gets `null`. Log with `AKDebug`, `AKInfo`,
`AKWarning` and `AKError`, which write to the Hammerspoon 2 Console.

### The JavaScript part

If the bundle has `Resources/<name>.js`, it's run once per config load, when the extension is
first required, as the body of a function whose argument, `ext`, is the module. Use it for
anything that's easier to write in JavaScript:

```js
"use strict";
ext.greet = function (name) {
    return "Hello, " + name;
};
```

Anything the script sets on `ext` must be declared as a property in the module's JSExport
protocol (`@objc var greet: JSValue? { get set }`), and set to nil in `shutdown()`. Otherwise
it's lost when JavaScriptCore collects the module's wrapper.

### Building

Build against the SDK in Hammerspoon 2 itself, at
`/Applications/Hammerspoon 2.app/Contents/Frameworks/HammerspoonSDK.framework`. It contains the
SDK's public Swift interface, which the Swift compiler builds the module from. That works with
the Swift compiler Hammerspoon 2 was built with, or any later one, so if you get an error about
the interface, update Xcode.

In Xcode, use a macOS Bundle target, with its wrapper extension set to `hsmodule`, and add
`/Applications/Hammerspoon 2.app/Contents/Frameworks` to its Framework Search Paths. Link
HammerspoonSDK.framework, but don't embed it: Hammerspoon 2 provides it at runtime. Or with
`swiftc`:

```bash
swiftc -parse-as-library -emit-library -swift-version 6 \
    -module-name ComExampleFoo -target arm64-apple-macos27.0 \
    -F "/Applications/Hammerspoon 2.app/Contents/Frameworks" -framework HammerspoonSDK \
    Sources/*.swift -o com.example.foo.hsmodule/Contents/MacOS/ComExampleFoo
codesign --force --sign - com.example.foo.hsmodule
```

Build against the oldest version of Hammerspoon 2 you want the extension to work with: it can
only use the API that version's SDK has.

### SDK versions

`HSSDKVersion` has a major and a minor version. Hammerspoon 2 loads an extension built for the
same major version and the same or an earlier minor version than it provides: the minor version
grows when the SDK gains API, and the major version changes when the SDK changes in a way that
breaks existing extensions. `HSSDK.version` is the version a running copy of Hammerspoon 2
provides.
