---
name: hs2module
description: Ensure all Hammerspoon v2 modules follow established patterns
---

# Hammerspoon 2 Module Requirements

Hammerspoon 2 consists of two main components:
 * a core engine that bridges native Swift code into JavaScript for the user to write their configuration file
 * Various "modules" that add expose macOS APIs into the JavaScript engine.

## Where do Hammerspoon 2 modules live?

In the directory "Hammerspoon 2/Modules", each within a further directory that shares the name they will be exposed to JS with, e.g. "hs.location"

## Module registration

A new module needs to be registered with the core JS engine so it can be loaded, these are both in Engine/ModuleRoot.swift:
 * In the ModuleRootAPI protocol: @objc var foo: HSFooModule { get }
 * In the ModuleRoot class body: @objc var foo: HSFooModule { getOrCreate(name: "foo", type: HSFooModule.self) }

This will automatically load hs.foo.js if it exists in the Hammerspoon 2 app bundle, as well as exposing the HSFooModule class to JavaScript

Additionally, the module should be exposed to "Hammerspoon 2Tests/Helpers/JStestHarness.swift" in the loadModules switch:
  case "foo":
    loadModule(HSFooModule.self, as: name)

## Basic structure of a module

For the case of a module that we intend to be accessible in JS as "hs.foo", the following structural rules must be observed:

 * All of the code for hs.foo should live in "Hammerspoon 2/Modules/hs.foo"
 * The code to be loaded when JavaScript accesses "hs.foo" should live in a file called "HSFooModule.swift"
 * HSFooModule.swift should always import the "Foundation" and "JavaScriptCore" frameworks
 * HSFooModule.swift should always contain at least the following:
   * A protocol definition of the form "@objc protocol HSFooModuleAPI: JSExport" - this is where we define the API that will be exported to JavaScript
   * A class implementation of "HSFooModuleAPI" of the form: "@objc class HSFooModule: NSObject, HSModuleAPI, HSFooModuleAPI"
   * The class must be annotated with `@MainActor` (all JS-facing code runs on the main thread)
   * Conformance to HSModuleAPI requires four things:
      * `var name: String` set to `"hs.foo"`
      * `let engineID: UUID` — stored property identifying which engine instance owns this module
      * An init in the form:
        ```swift
        required init(engineID: UUID) {
            self.engineID = engineID
            // ... any pre-super initialisation ...
            super.init()
            AKDebug("Init of \(name): \(engineID)")
        }
        ```
      * A `shutdown()` method called by the core engine when tearing down the JS environment
 * The HSFooModule class should be annotated with: `@_documentation(visibility: private)`
 * HSFooModule should always have an `isolated deinit` that calls `AKDebug("Deinit of \(name): \(engineID)")`.
 * If the module allocates/retains any data (e.g. watchers, instance children, etc) then it should store weak references to them and be sure to clean them up in its shutdown() method.
 * Any instance child classes should always have an "isolated deinit" method that uses `AKDebug()` to announce their deinitialisation.
 * NEVER choose method names that start with "new", "alloc" or "copy" since these can fall foul of ObjC's implicit ARC rules and the objects those methods create will have one un-balanced retains.
 * NEVER name a method "delete" since this is a reserved keyword in JavaScript and cannot be called as a method (e.g. `obj.delete()` is a syntax error). Use a descriptive alternative such as `deletePath()`, `destroy()`, or `remove()` instead.

## Child object tracking

When a module creates child objects that are returned to JavaScript (e.g. `HSTimer`, `HSHotkey`, `HSBonjourSearch`), it must track them so `shutdown()` can clean them all up.

**The canonical pattern is `HSWeakObjectSet<T>` (`Engine/HSWeakObjectSet.swift`):**

```swift
// Declaration (in the module class body)
private var children = HSWeakObjectSet<HSChild>()

// Adding a new child
children.add(child)

// Removing an explicit child (e.g. in removeSearch/removeWatcher)
children.remove(child)

// Shutdown — allObjects returns only live entries (dead ones are compacted on access)
func shutdown() {
    for child in children.allObjects {
        child.destroy()
    }
    children.removeAllObjects()
}
```

**Every child object returned to JS must have a `destroy()` method** that:
1. Deactivates the object (stops timers, disables hotkeys, stops OS updates, etc.)
2. Detaches all JS callbacks (see JS callback memory management below)
3. Clears all references

Both `isolated deinit` and the hosting module's `shutdown()` must call `destroy()`. This ensures cleanup happens whether the object is collected by the JS GC or torn down explicitly by the module.

```swift
@objc class HSChild: NSObject, HSChildAPI {
    private var callback: JSCallback?

    func destroy() {
        stop()                         // deactivate
        callback?.detach(from: self)   // detach JS callback
        callback = nil
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSChild")
    }
}
```

**Why `HSWeakObjectSet` and not `NSHashTable.weakObjects()`?**
- `NSHashTable.weakObjects()` has documented autoreleasepool interactions where entries can persist or zero out unpredictably (see https://github.com/GitHawkApp/FlatCache/issues/3 and http://cocoamine.net/blog/2013/12/13/nsmaptable-and-zeroing-weak-references/). `HSWeakObjectSet` uses plain Swift `weak var` references which zero correctly per ARC semantics.
- `HSWeakObjectSet` stores entries in a `[ObjectIdentifier: WeakBox]` dictionary, giving O(1) `add`/`remove`. Dead entries are compacted lazily on `allObjects` access.
- Centralising the implementation means we can change the backing storage in one place without touching every module.
- Weak refs allow the JS garbage collector to reclaim objects the user has dropped, without requiring an explicit `removeXxx()` call.
- The underlying OS keeps active objects alive independently (e.g. the Carbon event handler keeps `HSHotkey` alive while enabled; the run loop `Timer` keeps `HSTimer` alive while running; `CLLocationManager` holds `HSLocationWatcher` alive via its delegate). Module tracking is only needed for `shutdown()`.

## JS callback memory management

When a JS-exported Swift object stores a JavaScript callback function, **always use `JSCallback` (`Engine/JSCallback.swift`), never a raw `JSValue`**.

**Why:** Storing a raw `JSValue` in a JS-exported Swift object creates a retain cycle that prevents the JS GC from ever collecting the object:
> Swift object → JSValue → JSContext → JS wrapper → Swift object

**`JSCallback` breaks the cycle** using `JSManagedValue`. The VM tracks the callback as a conditional reference: alive only while the owner is reachable from JS. When JS GC collects the wrapper, the managed value clears and the Swift object can be freed.

**Critical design detail:** The `JSVirtualMachine` is captured at init time (when `JSContext.current()` is valid — JS is calling into Swift). This allows `detach(from:)` to work correctly even when called outside JS execution (e.g., from `shutdown()`). A naive implementation using `JSContext.current()` at detach time silently fails because that call returns `nil` when called from Swift outside a JS callback.

**Usage — callback set once at init:**
```swift
private var callback: JSCallback?

init(..., callback: JSValue, ...) {
    // ... stored properties ...
    super.init()
    // Phase 2 — JSContext.current() is non-nil here (called from JS bridge)
    self.callback = JSCallback(value: callback, owner: self)
}

func destroy() {
    callback?.detach(from: self)   // owner passed explicitly — weak var would be zeroed in deinit
    callback = nil
}

func fireCallback() {
    callback?.value?.call(withArguments: [...])
}
```

**Usage — callback exposed as a settable JS property** (e.g. `HSHotkey.callbackPressed`):

When the protocol declares `@objc var callbackPressed: JSValue? { get set }`, the implementation uses a computed property with `JSCallback?` backing — the JS-visible type is unchanged:

```swift
private var _callbackPressed: JSCallback?

@objc var callbackPressed: JSValue? {
    get { _callbackPressed?.value }
    set {
        _callbackPressed?.detach(from: self)
        _callbackPressed = newValue.flatMap { JSCallback(value: $0, owner: self) }
    }
}
```

**Do not use `JSCallback` for:**
- Objects that intentionally self-retain while active (e.g. `HSCamera`, `HSAudioDevice` use `selfRetain = self` while a watcher is registered). The retain cycle is intentional there; breaking it would cause premature deallocation.
- Internal helper objects not exported to JS (e.g. `HSAXWatcherObject`).

**Exception — strong refs for visible UI objects:**
`hs.ui` intentionally uses `[UUID: HSUIWindow]` (strong) for windows, alerts, and dialogs. These must stay alive on screen even if JS drops the reference. This is the only legitimate reason to use strong tracking. UI objects call back to the module to `register`/`unregister` themselves when shown/closed.

## JSValue retention and JSContext leaks

Every `JSValue` stored anywhere in Swift holds the **entire old `JSContext` alive** until that `JSValue` is released. If `hs.reload()` is called and any Swift object is still holding a `JSValue` from the old context, that context — and its entire JS heap, including all JS proxies for Swift objects — will remain in memory indefinitely.

This section documents the patterns that cause these leaks and how to prevent them.

### Closures that capture JSValue are the same as raw JSValue

A closure that closes over a `JSValue` parameter is functionally identical to storing that `JSValue` directly. Both hold a strong reference to the old `JSContext`.

```swift
// WRONG — the closure captures `callback` by value; JSValue is retained
interactive.clickCallback = { callback.call(withArguments: []) }

// WRONG — equivalent problem; isHovered is Bool but callback is captured
interactive.hoverCallback = { isHovered in callback.call(withArguments: [isHovered]) }
```

Any closure stored in a property (even a non-`JSValue` typed property like `(() -> Void)?`) that was created by capturing a `JSValue` must be cleared during shutdown with the same urgency as a raw `JSValue`.

**If JSValue-capturing closures are stored in sub-objects** (e.g. an element tree), the parent object must explicitly nil those sub-objects during `close()`/`shutdown()` — it is not sufficient to just release the parent via ARC, because ARC only runs when the retain count reaches zero, which may not happen until the JS proxy for the parent is GC'd (which requires the context to be freed first — a chicken-and-egg deadlock).

The correct pattern is to break the chain eagerly in `close()`:

```swift
@objc func close() {
    guard isOpen else { return }
    // Eagerly release the element tree so closures that captured JSValue callbacks
    // are freed NOW, before this object's own retain count reaches zero.
    rootElement = nil
    currentElement = nil
    containerStack.removeAll()
    // ... close the window etc. ...
}
```

### `_watcherEmitter` must be nilled in `shutdown()`

Every module that uses the Pattern A watcher stores a JS EventEmitter instance in `_watcherEmitter: JSValue?`. This `JSValue` holds the old `JSContext` alive. It MUST be nilled in `shutdown()` — calling `_removeWatcher()` alone is not sufficient, because `_removeWatcher()` only removes the underlying OS listener, not the emitter value itself.

```swift
func shutdown() {
    _removeWatcher()
    _watcherEmitter = nil   // REQUIRED — releases the JSValue holding the old context
}
```

The same applies to any other `JSValue?` stored directly on a module (e.g. `doUntil`, `doWhile`, `waitUntil`, `waitWhile` on `HSTimerModule`): they must all be nilled in `shutdown()`.

### `close()` is the single cleanup point — not `deinit`

For objects that have a `close()` or `destroy()` lifecycle method, **all JSValue cleanup must happen in `close()`/`destroy()`**, not only in `deinit`. This is because:

- `shutdown()` calls `close()`/`destroy()` explicitly — this is the primary cleanup path.
- `deinit` runs only after the object's ARC count drops to zero.
- If a JS proxy still references the Swift object (because the old context hasn't been freed yet), `deinit` never runs — but `close()` already ran, so that's fine. If `close()` didn't release the JSValues, the proxy prevents the context from being freed, which prevents `deinit` from running — a deadlock.

The dependency is:
> `close()` releases JSValues → JSContext freed → JS proxy collected → ARC drops → `deinit` runs

Reversing this by relying on `deinit` to release JSValues breaks the chain.

### One-shot callbacks: nil after invocation

For objects that show a modal UI and invoke a callback exactly once (e.g. `HSUITextPrompt`, `HSUIFilePicker`), nil the callback immediately after calling it. There is no `close()` to clear it, and the object may remain alive for a long time if not GC'd:

```swift
@objc func show() {
    // ... run the modal ...
    if let callback = buttonCallback {
        buttonCallback = nil          // release BEFORE calling, so it's freed even if callback throws
        callback.call(withArguments: [buttonIndex, inputText])
    }
}
```

Nilling before calling (rather than after) is slightly safer: if the callback throws a JS exception, the `JSValue` is still released.

### Shutdown checklist

When writing or reviewing a module's `shutdown()`, verify:

- [ ] `_removeWatcher()` called if the module uses Pattern A watchers
- [ ] `_watcherEmitter = nil` set after `_removeWatcher()`
- [ ] Every other `JSValue?` property stored on the module is nilled
- [ ] Every `JSValue?`-capturing closure stored on the module or its sub-objects is cleared
- [ ] `destroy()` called on all tracked child objects (which detach their own `JSCallback`s)
- [ ] `close()` on long-lived UI objects clears element trees and callback properties eagerly
 * If HSFooModule includes an hs.foo.js file, and that file needs to store any properties/methods/objects/etc in the hs.foo namespace, there must be a declaration in HSFooModuleAPI to hold it. JavaScriptCore cannot modify HSFooModule instances at runtime to add additional properties/methods and they will go silently out of scope in unpredictable ways.
 * In general we should avoid creating an hs.foo.js file unless absolutely necessary - it is strongly preferred to keep all code together in Swift. Legitimate uses of a .js file would include the watcher patterns mentioned below

## JavaScript API considerations

The HSFooModuleAPI protocol should observe the following rules:

 * Method parameters need to have their labels omitted, ie "@objc func doFoo(_ someParameter: String)" - the underscore before the label means it will not be required to call the method with the label. If this rule is ignored, the name of the method exposed to JavaScript will be a complex mixture of the name of the method and the labels of its parameters.
 * If for some reason we must have parameter labels, the name of the method exposed to JavaScript can be overridden thusly: "@objc(doFoo:) func doFoo(someParameter: String)"
 * If we are allowing users to create "watcher" objects that respond to macOS events and call user-supplied JS callbacks, they should be created/destroyed with methods called "addWatcher" and "removeWatcher"

### Never use JSValue for typed parameters or return values

`JSValue` must NOT appear in `@objc protocol ... JSExport` declarations as a parameter type or return type for any value that has a concrete Swift type. Use the appropriate Swift type instead:

| Instead of          | Use                     |
|---------------------|-------------------------|
| `JSValue` (string)  | `String` or `String?`   |
| `JSValue` (number)  | `Int`, `Double`, etc.   |
| `JSValue` (boolean) | `Bool`                  |
| `JSValue` (array)   | `[String]`, `[Any]`, etc. |
| `JSValue` (object)  | `[String: Any]`         |

`JSValue` is only acceptable for JavaScript **function callbacks** (there is no concrete Swift type for a JS function). Examples where `JSValue` is correct:

```swift
@objc func addWatcher(_ listener: JSValue)          // listener is a JS function
@objc func setCallback(_ fn: JSValue) -> HSXxxWatcher // fn is a JS function
@objc var callbackPressed: JSValue? { get set }      // property holding a JS function
```

If a parameter needs to accept two different concrete types (e.g. a string OR an array), do not reach for `JSValue` — instead split into two separate methods with descriptive names:

```swift
// BAD — hides the type contract, breaks TypeScript, forces runtime JSValue inspection
@objc func findMenuItem(_ item: JSValue) -> [String: Any]?

// GOOD — clear types, two separate entry points
@objc func findMenuItemByName(_ name: String) -> [String: Any]?
@objc func findMenuItemByPath(_ path: [String]) -> [String: Any]?
```

### Bool parameters default to false when omitted

When a `@objc` method has a `Bool` parameter, JavaScript callers that omit the argument receive `false` at the Swift layer (ObjC bridges `undefined`/missing to `NO`/`false`). This has an important consequence for API design:

**Design Bool-parameter APIs so that `false` represents the safe, common, or "do nothing extra" behaviour.** The user gets `false` for free when they call the method with no argument.

```swift
// GOOD — false means "don't raise all windows", which is the common case
@objc func activate(_ allWindows: Bool)   // app.activate() works naturally

// GOOD — false means "not hidden", so create() makes a visible item by default
@objc func create(_ hidden: Bool) -> HSMenuBarItem   // hs.menubar.create() → visible

// BAD — false means "not visible", so create() would create a hidden item
//        and callers would need create(true) for the common case
@objc func create(_ visible: Bool) -> HSMenuBarItem
```

If the natural default behaviour maps to `true`, invert the parameter name so `false` is the default (e.g. rename `visible` → `hidden`, `enabled` → `disabled`, `synchronous` → `async`).

## Promise-returning methods

  Several modules return Promises for async operations. The return type is JSPromise? (a
  typealias for JSValue), and the docstring - Returns: line should include {Promise<T>} to
  signal this to the docs generator.

  ### Critical: always use JSContext.current()

  Promises MUST be created in the JSContext that made the call, not in JSEngine.shared's
  context. JSEngine.shared has its own JSContext; if you create a Promise there and return
  it to JS running in a different context (e.g. the test harness), JavaScriptCore delivers
  it as an opaque ObjC object with no `then` method — the JS caller cannot use it as a
  Promise at all.

  The correct pattern is:

  ```swift
  // In the protocol:
  /// - Returns: {Promise<boolean>} A Promise that resolves to true if successful
  @objc func doSomethingAsync() -> JSPromise?

  // In the implementation:
  @objc func doSomethingAsync() -> JSPromise? {
      guard let context = JSContext.current() else { return nil }
      return wrapAsyncInJSPromise(in: context) { holder in
          Task { @MainActor in
              // ... do async work ...
              holder.resolveWith(result)       // or:
              holder.rejectWithMessage("reason")
          }
      }
  }
  ```

  `JSContext.current()` returns the JSContext that invoked the current `@objc` method via
  JSExport. It is always non-nil when called from a JS→Swift bridge method, so the guard is
  just a safety net.

  **Never use `JSEngine.shared.createPromise`** in an `@objc` JSExport method — that creates
  the Promise in the wrong context.

  For immediately-known results, use the JSContext extensions instead of JSEngine.shared:
  ```swift
  guard let context = JSContext.current() else { return nil }
  return context.createResolvedPromise(with: value)
  return context.createRejectedPromise(with: "error message")
  ```

## Watchers

  Hammerspoon 2 has two established watcher patterns. Choose the right one based on whether
  the underlying OS API is singleton/global or per-object.

  ### Pattern A — Module-level watcher (hs.application, hs.audiodevice, hs.pasteboard)

  Use this when there is a single global OS subscription (NSWorkspace notification, CoreAudio
  listener, a polling timer, etc.) that serves all JS callers.

  The architecture is always two layers: a private Swift subscription that feeds a single

  #### Swift protocol (in the `@objc protocol HSXxxModuleAPI: JSExport` block)

  ```swift
  /// Register a listener for Xxx events.
  /// - Parameter listener: A JavaScript function receiving (eventName, ...)
  /// - Example:
  /// ```js
  /// hs.xxx.addWatcher((event, data) => console.log(event, data))
  /// ```
  @objc func addWatcher(_ listener: JSValue)

  /// Remove a previously registered listener.
  /// - Parameter listener: The function originally passed to `addWatcher`
  /// - Example:
  /// ```js
  /// hs.xxx.removeWatcher(myHandler)
  /// ```
  @objc func removeWatcher(_ listener: JSValue)

  // Private API consumed only by the companion JS file — not exposed in docs
  /// SKIP_DOCS
  @objc(_addWatcher:) func _addWatcher(_ callback: JSValue)
  /// SKIP_DOCS
  @objc func _removeWatcher()
  /// SKIP_DOCS
  @objc var _watcherEmitter: JSValue? { get set }

  Swift implementation (in the @objc class HSXxxModule body)

  @objc var _watcherEmitter: JSValue? = nil
  private var watcherCallback: JSValue? = nil   // or whatever state the OS listener needs

  @objc func addWatcher(_ listener: JSValue) {
      _watcherEmitter?.invokeMethod("on", withArguments: [listener])
  }

  @objc func removeWatcher(_ listener: JSValue) {
      _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
  }

  @objc(_addWatcher:) func _addWatcher(_ callback: JSValue) {
      guard watcherCallback == nil else {
          AKWarning("hs.xxx._addWatcher(): Already watching. Refusing to create a second.")
          return
      }
      watcherCallback = callback
      // ... register with the OS API here; call callback(...) when an event fires ...
      AKTrace("hs.xxx._addWatcher(): Started")
  }

  @objc func _removeWatcher() {
      guard watcherCallback != nil else { return }
      // ... unregister from the OS API ...
      watcherCallback = nil
      AKTrace("hs.xxx._removeWatcher(): Stopped")
  }

  func shutdown() {
      _removeWatcher()
  }

  Key rules:
  - _addWatcher MUST guard against double-registration and warn with AKWarning.
  - Always use [weak self] in any closure passed to the OS listener to avoid retain cycles.
  - When the OS callback arrives off-@MainActor, use MainActor.assumeIsolated { } to enter
  actor isolation (CoreLocation, CoreAudio, etc. guarantee main-thread delivery).
  - shutdown() MUST call _removeWatcher().

  Companion JS file (hs.xxx.js)

  "use strict";

  class XxxModuleWatcherEmitter {
      #listeners = []

      #handleEvent(/* ...event args... */) {
          var listeners = this.#listeners.slice();
          const length = listeners.length;
          for (var i = 0; i < length; i++) {
              listeners[i].apply(null, [/* ...event args... */]);
          }
      }

      on(listener) {
          if (typeof listener !== 'function') {
              throw new Error("hs.xxx.addWatcher(): The provided handler must be a function");
          }
          if (this.#listeners.includes(listener)) {
              console.error("hs.xxx.addWatcher(): The provided handler is already registered.");
              return;
          }
          if (this.#listeners.length === 0) {
              hs.xxx._addWatcher((/* ...event args... */) => {
                  this.#handleEvent(/* ...event args... */);
              });
          }
          this.#listeners.push(listener);
      }

      removeListener(listener) {
          const idx = this.#listeners.indexOf(listener);
          if (idx > -1) {
              this.#listeners.splice(idx, 1);
          }
          if (this.#listeners.length === 0) {
              hs.xxx._removeWatcher();
          }
      }
  }

  // Store in a Swift-retained property so the emitter is not garbage collected.
  hs.xxx._watcherEmitter = new XxxModuleWatcherEmitter();

  Key rules:
  - The emitter class MUST be stored in hs.xxx._watcherEmitter — this is what keeps it alive.
  - The underlying _addWatcher call MUST be lazy (only on first on() call).
  - _removeWatcher MUST be called automatically when the last listener is removed.
  - Duplicate listener registration is silently rejected with console.error (not thrown).
  - The module's shutdown() method MUST remove all watchers and set properties like _watcherEmitter to nil

  ---
  Pattern B — Object-level watcher (hs.ax, hs.location)

  Use this when each watcher is a discrete, independently-configured object with its own
  OS subscription and callback — for example, per-app AX observers or per-session location
  updates.

  The watcher class

  // Separate file: HSXxxWatcher.swift

  @objc protocol HSXxxWatcherAPI: HSTypeAPI, JSExport {
      @objc var identifier: String { get }     // UUID string, set in init
      @objc @discardableResult func start() -> HSXxxWatcher
      @objc @discardableResult func stop() -> HSXxxWatcher
      @objc func setCallback(_ fn: JSValue) -> HSXxxWatcher
      // ... any additional config properties (e.g. distanceFilter) ...
  }

  @_documentation(visibility: private)
  @MainActor
  @objc class HSXxxWatcher: NSObject, HSXxxWatcherAPI /*, OS delegate if needed */ {
      @objc var typeName = "HSXxxWatcher"
      @objc let identifier = UUID().uuidString
      private var callback: JSCallback?

      override init() {
          super.init()
          // set self as OS delegate if needed
      }

      isolated deinit {
          destroy()
          AKDebug("deinit of HSXxxWatcher(\(identifier))")
      }

      func destroy() {
          _ = stop()
          callback?.detach(from: self)
          callback = nil
      }

      @objc @discardableResult func start() -> HSXxxWatcher {
          // begin OS updates
          return self
      }

      @objc @discardableResult func stop() -> HSXxxWatcher {
          // end OS updates
          return self
      }

      @objc func setCallback(_ fn: JSValue) -> HSXxxWatcher {
          callback?.detach(from: self)
          callback = JSCallback(value: fn, owner: self)
          return self
      }

      // OS delegate callbacks use MainActor.assumeIsolated { } and
      // `_ = callback?.value?.call(withArguments: [...])` to invoke.
  }

  Module additions

  In the module's Swift protocol add:

  /// Creates a new Xxx watcher. Call `.start()` and `.setCallback()` to activate it.
  /// The watcher is stopped automatically when the module shuts down.
  /// - Returns: an HSXxxWatcher
  /// - Example:
  /// ```js
  /// const w = hs.xxx.addWatcher()
  /// w.setCallback((event, data) => console.log(event, data)).start()
  /// ```
  @objc func addWatcher() -> HSXxxWatcher

  In the module's Swift implementation:

  private var watchers = HSWeakObjectSet<HSXxxWatcher>()

  func addWatcher() -> HSXxxWatcher {
      let w = HSXxxWatcher()
      watchers.add(w)
      return w
  }

  func removeWatcher(_ watcher: HSXxxWatcher) {
      watcher.destroy()
      watchers.remove(watcher)
  }

  func shutdown() {
      for watcher in watchers.allObjects { watcher.destroy() }
      watchers.removeAllObjects()
      // stop any module-level OS state too
  }

  Key rules:
  - The module MUST track all created watcher objects in `private var watchers = HSWeakObjectSet<HSXxxWatcher>()`.
  - Every watcher MUST have a `destroy()` method (see Child object tracking section).
  - shutdown() MUST call `destroy()` on all tracked watchers, not just `stop()`.
  - start()/stop() and setCallback() MUST return self for chaining.
  - typeName MUST be set to match the Swift class name for JS introspection.
  - identifier MUST be a UUID().uuidString assigned at init time.
  }

  Key rules:
  - The module MUST track all created watcher objects in `private var watchers = HSWeakObjectSet<HSXxxWatcher>()`.
  - Every watcher MUST have a `destroy()` method (see Child object tracking section).
  - shutdown() MUST call `destroy()` on all tracked watchers, not just `stop()`.
  - start()/stop() and setCallback() MUST return self for chaining.
  - typeName MUST be set to match the Swift class name for JS introspection.
  - identifier MUST be a UUID().uuidString assigned at init time.
  - OS delegate callbacks arriving off-@MainActor MUST use MainActor.assumeIsolated { }.
  - Discard the unused JSValue? result from callback?.call() with _ = callback?.call(...).

  ---
  Pattern B with multiplexing (hs.ax)

  When Pattern B watcher objects are keyed by a composite identity (e.g. pid:notification),
  keep an additional dictionary of the underlying OS observers:

  private var observers: [KeyType: OSObserver] = [:]
  private var watchers: [String: HSXxxWatcher] = [:]   // keyed by "component1:component2"

  And in _removeWatcher, only tear down the OS observer when the last watcher for that
  key prefix is removed (see HSAXModule._removeWatcher for the reference implementation).

  ---
  Logging conventions for watchers

  - AKTrace(...) when successfully starting or stopping a watcher
  - AKWarning(...) when refusing a duplicate registration
  - AKError(...) when an OS call fails during setup or teardown

  ---

  The section covers both patterns (module-level EventEmitter and object-level watcher), the JS emitter template, the composite-key variant from hs.ax, and all the subtle rules around lazy start, `[weak self]`,
  `assumeIsolated`, discarding `JSValue?`, and the `_watcherEmitter` GC anchor.

## Docstrings conventions

  - Every method/property in the HSFooModuleAPI protocol needs a /// docstring that describes the item, and in the case of methods, also documents each parameter and any return value
  - Every docstring should have a - Example: section with a fenced ```js block
  - Private/internal protocol members (the _addWatcher, _watcherEmitter underbelly) use /// SKIP_DOCS to be omitted from generated HTML
  - Async methods annotate their return: /// - Returns: {Promise<boolean>} A Promise resolving to...
  - Optional parameters (Swift type `Foo?`) must have `?` appended to the parameter name in the docstring to signal optionality to the docs pipeline: `/// - Parameter headers?: Optional dictionary of request headers.`

## Logging

Hammerspoon 2 provides several convenience functions that handle logging per the user's configuration:
 * AKInfo - useful information for the user
 * AKDebug — Messages that are only useful during development, in DEBUG builds, such as object lifecycle events. These messages are ignored in Release builds.
 * AKTrace — debug events (watcher started/stopped, timer fired, etc.)
 * AKWarning — recoverable bad states (invalid input, refused duplicate)
 * AKError — unrecoverable failures (OS call failed, nil context)

These all log into the app's Console window

If we ever emit a console.log() call, even in example code, please note that Hammerspoon 2's implementation of console.log does not support the form console.log("foo: ", bar); - either concatenate strings with + or use interpolated strings.

Avoid using print() if possible.
