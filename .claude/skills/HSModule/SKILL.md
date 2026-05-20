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
            AKTrace("Init of \(name): \(engineID)")
        }
        ```
      * A `shutdown()` method called by the core engine when tearing down the JS environment
 * The HSFooModule class should be annotated with: `@_documentation(visibility: private)`
 * HSFooModule should always have an `isolated deinit` that calls `AKTrace("Deinit of \(name): \(engineID)")`.
 * If the module allocates/retains any data (e.g. watchers, instance children, etc) then it should store weak references to them and be sure to clean them up in its shutdown() method.
 * Any instance child classes should always have an "isolated deinit" method that uses AKTrace() to announce their deinitialisation.

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
        child.stop()   // or disable(), cancel(), etc.
    }
    children.removeAllObjects()
}
```

**Why `HSWeakObjectSet` and not `NSHashTable.weakObjects()`?**
- `NSHashTable.weakObjects()` has documented autoreleasepool interactions where entries can persist or zero out unpredictably (see https://github.com/GitHawkApp/FlatCache/issues/3 and http://cocoamine.net/blog/2013/12/13/nsmaptable-and-zeroing-weak-references/). `HSWeakObjectSet` uses plain Swift `weak var` references which zero correctly per ARC semantics.
- `HSWeakObjectSet` stores entries in a `[ObjectIdentifier: WeakBox]` dictionary, giving O(1) `add`/`remove`. Dead entries are compacted lazily on `allObjects` access.
- Centralising the implementation means we can change the backing storage in one place without touching every module.
- Weak refs allow the JS garbage collector to reclaim objects the user has dropped, without requiring an explicit `removeXxx()` call.
- The underlying OS keeps active objects alive independently (e.g. the Carbon event handler keeps `HSHotkey` alive while enabled; the run loop `Timer` keeps `HSTimer` alive while running; `CLLocationManager` holds `HSLocationWatcher` alive via its delegate). Module tracking is only needed for `shutdown()`.

**Exception — strong refs for visible UI objects:**
`hs.ui` intentionally uses `[UUID: HSUIWindow]` (strong) for windows, alerts, and dialogs. These must stay alive on screen even if JS drops the reference. This is the only legitimate reason to use strong tracking. UI objects call back to the module to `register`/`unregister` themselves when shown/closed.
 * If HSFooModule includes an hs.foo.js file, and that file needs to store any properties/methods/objects/etc in the hs.foo namespace, there must be a declaration in HSFooModuleAPI to hold it. JavaScriptCore cannot modify HSFooModule instances at runtime to add additional properties/methods and they will go silently out of scope in unpredictable ways.
 * In general we should avoid creating an hs.foo.js file unless absolutely necessary - it is strongly preferred to keep all code together in Swift. Legitimate uses of a .js file would include the watcher patterns mentioned below

## JavaScript API considerations

The HSFooModuleAPI protocol should observe the following rules:

 * Method parameters need to have their labels omitted, ie "@objc func doFoo(_ someParameter: String)" - the underscore before the label means it will not be required to call the method with the label. If this rule is ignored, the name of the method exposed to JavaScript will be a complex mixture of the name of the method and the labels of its parameters.
 * If for some reason we must have parameter labels, the name of the method exposed to JavaScript can be overridden thusly: "@objc(doFoo:) func doFoo(someParameter: String)"
 * If we are allowing users to create "watcher" objects that respond to macOS events and call user-supplied JS callbacks, they should be created/destroyed with methods called "addWatcher" and "removeWatcher"

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
      private var callback: JSValue?

      override init() {
          super.init()
          // set self as OS delegate if needed
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
          callback = fn.isObject ? fn : nil
          return self
      }

      // OS delegate callbacks use MainActor.assumeIsolated { } and
      // `_ = callback?.call(withArguments: [...])` to discard the unused JSValue? result.
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

  private var watchers: [HSXxxWatcher] = []

  func addWatcher() -> HSXxxWatcher {
      let w = HSXxxWatcher()
      watchers.append(w)
      return w
  }

  func shutdown() {
      watchers.forEach { $0.stop() }
      watchers.removeAll()
      // stop any module-level OS state too
  }

  Key rules:
  - The module MUST track all created watcher objects in private var watchers: [HSXxxWatcher] = [].
  - shutdown() MUST stop all tracked watchers and clear the array.
  - start()/stop() and setCallback() MUST return self for chaining.
  - typeName MUST be set to match the Swift class name for JS introspection.
  - identifier MUST be a UUID().uuidString assigned at init time.
  }

  Key rules:
  - The module MUST track all created watcher objects in private var watchers: [HSXxxWatcher] = [].
  - shutdown() MUST stop all tracked watchers and clear the array.
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

## Docstrings convensions

  - Every method/property in the HSFooModuleAPI protocol needs a /// docstring that describes the item, and in the case of methods, also documents each parameter and any return value
  - Every docstring should have a - Example: section with a fenced ```js block
  - Private/internal protocol members (the _addWatcher, _watcherEmitter underbelly) use /// SKIP_DOCS to be omitted from generated HTML
  - Async methods annotate their return: /// - Returns: {Promise<boolean>} A Promise resolving to...

## Logging

Hammerspoon 2 provides several convenience functions that handle logging per the user's configuration:
 * AKInfo - useful information for the user
 * AKTrace — debug events (module loaded, timer fired, etc.)
 * AKWarning — recoverable bad states (invalid input, refused duplicate)
 * AKError — unrecoverable failures (OS call failed, nil context)

These all log into the app's Console window

If we ever emit a console.log() call, even in example code, please note that Hammerspoon 2's implementation of console.log does not support the form console.log("foo: ", bar); - either concatenate strings with + or use interpolated strings.

Avoid using print() if possible.
