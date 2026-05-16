---
name: hs2type
description: Guide for creating custom types in Hammerspoon 2 — both shared engine types and module-specific types
---

# Hammerspoon 2 Type System

Types are Swift objects exposed to JavaScript via JSExport. There are two distinct
categories with different rules. Choose the right one before writing any code.

---

## Category 1 — Engine types (`Engine/Types/`)

Engine types are **directly usable from JavaScript** — users can call their static
factory methods or constructors at any time, without going through a module.
They are global JS objects registered at engine startup.

**When to create one:** the type represents a fundamental, module-agnostic value
(geometry, colour, font, image, string) that multiple modules will share.

**When NOT to create one:** the type wraps a module-specific OS resource
(a running application, a display, a timer). Use a module type instead.

### File location

`Hammerspoon 2/Engine/Types/HSFoo.swift`

### Structural template

```swift
import Foundation
import JavaScriptCore
// import whatever the wrapped native type needs

/// User-facing docstring for the type. The protocol docstring is what the
/// docs generator reads — the class is hidden so its docstring is irrelevant.
@objc protocol HSFooAPI: HSTypeAPI, JSExport {
    // Declare every property and method the user can call from JavaScript.
    // All same @objc bridging rules as module API protocols apply.

    /// Create a new HSFoo
    /// - Parameters:
    ///   - x: description
    @objc init(x: Double)           // use static factory methods if init can fail

    @objc var x: Double { get set }
    @objc func doSomething() -> String
}

// No @_documentation here — engine types are intentionally public
@objc class HSFoo: NSObject, HSFooAPI {
    @objc var typeName = "HSFoo"    // REQUIRED — satisfies HSTypeAPI

    // Internal storage (the wrapped native type)
    var nativeThing: NativeFoo

    required init(x: Double) {
        nativeThing = NativeFoo(x: x)
        super.init()
    }

    var x: Double {
        get { nativeThing.x }
        set { nativeThing.x = newValue }
    }

    @objc func doSomething() -> String { ... }
}
```

### `JSConvertible` — bridging to/from native Swift types

When the engine type wraps a standard Swift/CoreGraphics value type (CGPoint, CGSize,
CGRect, SwiftUI.Color, etc.), implement `JSConvertible` on the **native** type:

```swift
extension CGPoint: JSConvertible {
    typealias BridgeType = HSPoint

    init(from bridge: HSPoint) {
        self.init(x: bridge.x, y: bridge.y)
    }

    func toBridge() -> HSPoint {
        HSPoint(x: Double(x), y: Double(y))
    }
}
```

This lets any Swift code that receives a `CGPoint` call `.toBridge()` to get a
JS-passable `HSPoint`, and vice versa.

Also add a `JSValue` extension for ergonomic unboxing in module code:

```swift
extension JSValue {
    func toCGPoint() -> CGPoint? {
        guard let bridge = toObjectOf(HSPoint.self) as? HSPoint else { return nil }
        return CGPoint(from: bridge)
    }
}
```

### Registering with the JS context

Every engine type that should be accessible as a global JS constructor or namespace
must be registered in `Engine/InjectTypes.swift`:

```swift
struct TypeBridgesInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        let typeBridges: [String: AnyClass] = [
            "HSFoo": HSFoo.self,
            // ...
        ]
        typeBridges.forEach { key, value in
            context.setObject(value, forKeyedSubscript: key as NSString)
        }
    }
}
```

Only add types here that make sense for users to construct or reference directly.
Types that are only ever returned from module methods do NOT belong here.

### Reactive engine types (`@Observable`)

If the type's value needs to drive SwiftUI re-renders (e.g. `HSColor`, `HSString`,
`HSImage`), use `@Observable` instead of `ObservableObject`.

Key constraint: `@Observable` cannot track `@objc` stored properties. Work around
this with a private backing store:

```swift
import Observation   // required in files that don't import SwiftUI

@Observable
@objc class HSFoo: NSObject, HSFooAPI {
    @objc var typeName = "HSFoo"

    // @Observable tracks _value (not @objc).
    // The computed @objc var forwards to it; SwiftUI sees: value → _value.
    private var _value: String

    @objc var value: String { _value }   // read-only from JS is fine; set() mutates

    init(value: String) {
        self._value = value
        super.init()
    }

    @objc func set(_ newValue: String) {
        _value = newValue                // triggers @Observable tracking
    }
}
```

Non-reactive properties (e.g. `HSColor.color: Color`) that are not `@objc` are
tracked normally by `@Observable` with no workaround needed.

### Static factory methods

Prefer factory methods over failable inits when construction can fail or requires
complex resolution (loading a file, parsing a hex string, etc.):

```swift
@objc protocol HSFooAPI: HSTypeAPI, JSExport {
    @objc static func fromPath(_ path: String) -> HSFoo?
    @objc static func named(_ name: String) -> HSFoo
}
```

Return `nil` for failure rather than throwing; errors are logged with `AKError`.

---

## Category 2 — Module types (`Modules/hs.xxx/HSFoo.swift`)

Module types are objects **returned by module methods** — users never construct
them directly. They wrap module-specific OS resources (a running application,
a display, a hotkey handle, a timer object, etc.).

**When to create one:** a module method needs to return something the user can
hold a reference to and call further methods on. If the result is a plain dictionary
or primitive, don't create a type — just return the value directly.

### File location

Same directory as the module that owns them:
`Hammerspoon 2/Modules/hs.xxx/HSFoo.swift`

### Structural template

```swift
import Foundation
import JavaScriptCore
// import whatever OS framework the type wraps

/// User-facing docstring. The protocol is the documented public surface.
/// Mention that users should not instantiate these directly.
@objc protocol HSFooAPI: HSTypeAPI, JSExport {
    /// The unique identifier assigned to this object (UUID string).
    @objc var identifier: String { get }

    // Declare all user-callable properties and methods.
    // Apply the same @objc bridging rules as module API protocols.
    @objc var someProperty: String { get }
    @objc func doSomething()
}

// REQUIRED: hide the implementation class from generated docs
@_documentation(visibility: private)
// Add @MainActor only if the type accesses actor-isolated state (timers, UI, etc.)
@objc class HSFoo: NSObject, HSFooAPI {
    @objc var typeName = "HSFoo"        // REQUIRED — satisfies HSTypeAPI
    @objc let identifier = UUID().uuidString   // if applicable

    // Internal state — not exposed to JS
    private let wrapped: NativeFooObject

    init(wrapped: NativeFooObject) {
        self.wrapped = wrapped
        super.init()
    }

    // For @MainActor types, use isolated deinit:
    isolated deinit {
        print("deinit of HSFoo")
    }

    // For non-@MainActor types, use plain deinit:
    // deinit { print("deinit of HSFoo") }

    @objc var someProperty: String { wrapped.name }
    @objc func doSomething() { wrapped.doThing() }
}
```

### `@_documentation(visibility: private)` is mandatory

The class is always hidden. The protocol is the public-facing API that the docs
generator reads. Never put documentation on the class — put it on the protocol.

### `@MainActor` usage

Add `@MainActor` to the class when it:
- Schedules or invalidates timers
- Calls UIKit/AppKit/SwiftUI APIs
- Holds or calls `JSValue` callbacks from OS delegate methods
- Is a CLLocationManagerDelegate, AVAudioSession delegate, etc.

Non-`@MainActor` examples: `HSApplication` (reads NSRunningApplication properties
synchronously), `HSScreen`, `HSAudioDevice`.

`@MainActor` examples: `HSTimer`, `HSTask`, `HSHotkey`, `HSLocationWatcher`.

### `isolated deinit` vs `deinit`

- `@MainActor` class → `isolated deinit` (lets deinit safely access actor state)
- Non-`@MainActor` class → plain `deinit`

Always log in deinit (`AKTrace` or `print`). Clean up OS resources (invalidate
timers, stop observers, close file handles) in deinit if the module hasn't already.

### `identifier` property

Any type the user might hold multiple instances of should have:
```swift
@objc let identifier = UUID().uuidString
```

This satisfies `HSTypeAPI`'s `typeName` requirement implicitly through the pattern
and gives users a stable handle to correlate objects.

### Factory/conversion extensions on OS types

When a module type wraps a specific OS class, put the conversion in an extension
on the OS class in `Hammerspoon 2/Extensions/`:

```swift
// Extensions/NSRunningApplication.swift
extension NSRunningApplication {
    func asHSApplication() -> HSApplication? {
        return HSApplication(runningApplication: self)
    }
}
```

This keeps construction logic out of the module and lets it be reused across files.
Only create an Extensions file if the extension is genuinely shared; single-use
conversions can live in the module file.

---

## Checklist for any new type

### Both categories
- [ ] `@objc protocol HSFooAPI: HSTypeAPI, JSExport` — protocol inherits both
- [ ] `@objc var typeName = "HSFoo"` on the class — satisfies `HSTypeAPI`
- [ ] Protocol has docstrings with `- Example:` on every member
- [ ] `super.init()` called at the end of every `init`
- [ ] `@objc` on every property and method in the protocol

### Engine types only
- [ ] No `@_documentation(visibility: private)` on the class (engine types are public)
- [ ] Added to `TypeBridgesInstaller` in `InjectTypes.swift` (if user-constructable)
- [ ] `JSConvertible` extension on the native type (if wrapping a value type)
- [ ] `JSValue` extension for ergonomic unboxing (e.g. `toCGPoint()`)
- [ ] If reactive: `@Observable`, private `_value` backing store, `import Observation`

### Module types only
- [ ] `@_documentation(visibility: private)` on the class — mandatory
- [ ] Lives in `Modules/hs.xxx/HSFoo.swift` alongside its owning module
- [ ] `@MainActor` if the type schedules timers, calls JS callbacks, or touches UI
- [ ] `isolated deinit` if `@MainActor`; plain `deinit` otherwise
- [ ] NOT added to `TypeBridgesInstaller` (module types are never directly constructable)
- [ ] If the module tracks instances (for shutdown cleanup), add to `private var foos: [HSFoo] = []`
