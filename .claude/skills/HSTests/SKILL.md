---
name: hs2tests
description: Guide for writing tests in Hammerspoon 2 — framework, structure, JSTestHarness patterns, async, environment guards, and what not to test
---

# Hammerspoon 2 Testing Guide

## Framework and imports

All tests use **Swift Testing** (not XCTest). Every test file starts with:

```swift
import Testing
import JavaScriptCore       // for JS-level module tests
@testable import Hammerspoon_2
```

Add other framework imports only as needed (e.g. `import AppKit`, `import CoreAudio`).

---

## File locations

| What you're testing | Directory | Filename pattern |
|---|---|---|
| A module's JS API | `Hammerspoon 2Tests/IntegrationTests/` | `HSFooIntegrationTests.swift` |
| A manager/engine class | `Hammerspoon 2Tests/ManagerTests/` | `FooManagerTests.swift` |
| Console/completion logic | `Hammerspoon 2Tests/ConsoleTests/` | `FooConsoleTests.swift` |
| Mock implementations | `Hammerspoon 2Tests/Mocks/` | `MockFoo.swift` |

---

## Test structure

Tests are **structs**, not classes. Each module's test file must have a **top-level wrapper suite** that encloses all of that module's inner suites:

```swift
@Suite("hs.foo tests")
struct HSFooTests {

    @Suite("hs.foo API structure tests")
    struct HSFooStructureTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFooModule.self, as: "foo")
            return harness
        }

        @Test("someMethod is a function")
        func testSomeMethodIsFunction() {
            makeHarness().expectTrue("typeof hs.foo.someMethod === 'function'")
        }
    }

    @Suite("hs.foo calculations")
    struct HSFooCalculationTests {
        // ...
    }
}
```

The top-level suite name is always `"hs.foo tests"` (matching the module name) and the struct is named `HSFooTests`. All inner suites (`HSFooStructureTests`, `HSFooCalculationTests`, etc.) are nested inside it.

The private `makeHarness()` factory avoids repeating setup in every test. Each test
should create its own harness (they share no state).

---

## JSTestHarness — the primary testing tool for modules

`JSTestHarness` spins up an isolated `JSContext` and loads modules into it,
exactly mimicking the real runtime but without a full app launch.

### Loading modules

```swift
// Load one module
harness.loadModule(HSFooModule.self, as: "foo")
// → available in JS as hs.foo

// Load multiple modules (e.g. hs.ax needs hs.application)
harness.loadModule(HSAXModule.self, as: "ax")
harness.loadModule(HSApplicationModule.self, as: "application")
```

The companion `.js` file (`hs.foo.js`) is loaded automatically if it exists in the
bundle, so JS enhancements are included in integration tests without extra setup.

### Assertions

Prefer bringing equality-style checks into Swift with a plain `#expect(...)` rather
than `expectTrue`/`expectFalse`. `expectTrue("typeof x === 'number'")` only ever
reports "expected true, got false" — Swift Testing's `#expect` macro captures both
sides of a `==` comparison and reports the actual value on failure, which is far
more useful for debugging. Use the `evalString`/`evalBool`/`evalInt`/`evalDouble`/
`evalTypeOf` helpers on `JSTestHarness` for this:

```swift
// Type checks — use evalTypeOf, not expectTrue("typeof ... === '...'")
#expect(harness.evalTypeOf("hs.foo.someMethod") == "function")
#expect(harness.evalTypeOf("hs.foo.name") == "string")

// Equality checks against a known value — use the typed eval helpers
#expect(harness.evalString("hs.foo.name") == "expected string")
#expect(harness.evalInt("hs.foo.count") == 42)
#expect(harness.evalDouble("hs.foo.ratio") == 0.5)
#expect(harness.evalBool("hs.foo.isReady") == true)

// Reserve expectTrue/expectFalse for genuine boolean checks with no natural
// "actual vs expected" pair — comparisons, predicates, compound conditions:
harness.expectTrue("Array.isArray(hs.foo.list())")
harness.expectTrue("hs.foo.count >= 0")
harness.expectFalse("hs.foo.isEmpty()")

// expectEqual still works and is fine for quick one-offs, but a direct #expect
// is preferred for the reasons above
harness.expectEqual("hs.foo.name", "expected string")

// Run JS without asserting on the result
harness.eval("hs.foo.doSomething()")
harness.eval("""
    var x = hs.foo.create({ title: 'Test' });
    x.start();
""")

// Get the raw JSValue for complex assertions
let result = harness.evalValue("hs.foo.compute()")
#expect(result?.isObject == true)
#expect(result?.isNull == true || result?.isUndefined == true)

// Get the plain Swift value
let val = harness.eval("hs.foo.compute()") as? Double
#expect(val != nil)
```

### Checking for exceptions

Check that a call does NOT throw (the most common check after any non-trivial eval):

```swift
harness.eval("hs.foo.doSomething(complexInput)")
#expect(!harness.hasException)
```

Check that a call DOES throw (for invalid input validation):

```swift
harness.eval("hs.foo.doSomething(badInput)")
harness.expectException()
```

---

## Standard test suites for a new module

Every new module should have **at minimum** two suites in its test file, both nested
inside a top-level wrapper suite (see **Test structure** above). If the module produces
JS-exported child objects (factory/constructor methods that return `HSFoo` instances),
a **memory leak test is also mandatory** — see **Memory leak tests** below.

### Suite 1: API structure (mandatory, runs everywhere)

One test per public protocol member, verifying it exists with the right JS type.
These tests never touch real OS state and run in any environment.

```swift
@Suite("hs.foo tests")
struct HSFooTests {

    @Suite("hs.foo API structure tests")
    struct HSFooStructureTests {

        private func makeHarness() -> JSTestHarness { ... }

        // Functions
        @Test("doThing is a function")
        func testDoThingIsFunction() {
            makeHarness().expectTrue("typeof hs.foo.doThing === 'function'")
        }

        // Properties (numbers, booleans, strings, objects)
        @Test("count is a number")
        func testCountIsNumber() {
            makeHarness().expectTrue("typeof hs.foo.count === 'number'")
        }

        @Test("isEnabled defaults to true")
        func testIsEnabledDefault() {
            makeHarness().expectTrue("hs.foo.isEnabled === true")
        }

        // Sub-objects
        @Test("geocoder is an object")
        func testGeocoderIsObject() {
            makeHarness().expectTrue("typeof hs.foo.geocoder === 'object'")
        }

        // Watcher emitter (if the module uses the EventEmitter watcher pattern)
        @Test("_watcherEmitter is initialized by hs.foo.js")
        func testWatcherEmitterInitialized() {
            makeHarness().expectTrue(
                "hs.foo._watcherEmitter !== null && hs.foo._watcherEmitter !== undefined"
            )
        }

        // Input validation (methods should fail gracefully, not throw)
        @Test("doThing() with null input returns null without throwing")
        func testDoThingNullInput() {
            let harness = makeHarness()
            harness.eval("var r = hs.foo.doThing(null)")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 2

    @Suite("hs.foo calculations")
    struct HSFooCalculationTests {

        private func makeHarness() -> JSTestHarness { ... }

        @Test("distance between London and Paris is ~341km")
        func testDistance() {
            let harness = makeHarness()
            harness.eval("var d = hs.foo.distance(51.5074, -0.1278, 48.8566, 2.3522)")
            harness.expectTrue("Math.abs(d - 341402) < 5000")
            #expect(!harness.hasException)
        }

        @Test("returned object has expected type and properties")
        func testReturnedObject() {
            let harness = makeHarness()
            harness.eval("var obj = hs.foo.create({ title: 'Test' })")
            harness.expectTrue("typeof obj === 'object'")
            harness.expectTrue("typeof obj.identifier === 'string'")
            harness.expectTrue("obj.identifier.length > 0")
        }

        @Test("two created objects have different identifiers")
        func testUniqueIdentifiers() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var a = hs.foo.create({ title: 'A' });
                    var b = hs.foo.create({ title: 'B' });
                    return a.identifier !== b.identifier;
                })()
            """)
        }
    }
}
```

### Suite 2: Behaviour / pure calculations (runs everywhere)

Test that methods return correct values for deterministic inputs — pure
calculations, round-trips, invariants. No OS permissions or hardware required.
(See example above.)

### Suite 3 (optional): Permission/hardware-gated tests

Tests that require real OS state (accessibility, microphone, audio hardware, etc.)
must be guarded with `.disabled(if:)` so they skip gracefully in environments
where the permission or hardware is absent. These also nest inside the top-level
`HSFooTests` wrapper.

```swift
private nonisolated func isAccessibilityEnabled() -> Bool {
    AXIsProcessTrusted()
}

@Suite("hs.foo tests")
struct HSFooTests {
    // ...

    @Suite("hs.foo real-hardware tests",
           .serialized,
           .disabled(if: !isAccessibilityEnabled(), "Accessibility not granted"))
    struct HSFooHardwareTests {
        // Tests that call real OS APIs
    }
}
```

The guard function MUST be `nonisolated` so it can be called from the `.disabled`
trait expression, which is evaluated outside any actor.

---

## Memory leak tests (mandatory for object-producing modules)

Any module whose API lets JS create instances of a Swift class (`HSTimer`,
`HSHotkey`, `HSBonjourSearch`, etc.) **must** have at least one leak test.
These tests verify that after `hs.reload()` (simulated by `shutdownForLeakTest()`)
every child object is properly freed — no strong-reference cycles, no stale
`NSNotificationCenter` observers, no `selfRetain` left set.

### Tools

**`WeakLeakTracker`** — holds weak references to tracked objects without
preventing their deallocation. Call `tracker.track(swiftObj)` while the object is
alive, then `tracker.assertNoLeaks()` after everything is torn down.

**`harness.shutdownForLeakTest()`** — calls `module.shutdown()` on every loaded
module, removes `hs` from the JS global object, then runs
`JSSynchronousGarbageCollectForDebugging` so ObjC bridge finalizers execute
before the function returns.

### Mandatory pattern

```swift
// MARK: - Memory Leak Tests

@Test("Active HSFoo is released after shutdown")
func testFooDoesNotLeakAfterReload() {
    let tracker = WeakLeakTracker()
    autoreleasepool {
        let harness = JSTestHarness()
        harness.loadModule(HSFooModule.self, as: "foo")

        // 1. CREATE the object
        harness.eval("var obj = hs.foo.create(…)")

        // 2. ACTIVELY USE IT — call start(), send(), enter(), findServices(), etc.
        //    Do not just create and immediately discard. The goal is to exercise
        //    the path where the object holds OS resources when shutdown is called.
        harness.eval("obj.start()")

        // 3. TRACK the underlying Swift object while it is still alive
        if let swift = harness.evalValue("obj")?.toObjectOf(HSFoo.self) as? HSFoo {
            tracker.track(swift)
        }

        // 4. Drop the JS reference, then shut down
        harness.eval("obj = null")
        harness.shutdownForLeakTest()
    } // autorelease pool drained here; JSValue ObjC refs released, JSContext freed
    tracker.assertNoLeaks()
}
```

### Rules

| Rule | Reason |
|---|---|
| Wrap harness in an `autoreleasepool {}` block | Drains ObjC autorelease pool (including `JSValue`s from `eval()`) so the `JSContext` is freed before the weak-ref check runs — a plain `do {}` block does **not** drain the pool and will silently miss leaks |
| Track the object **before** nulling the JS var | `evalValue()` returns nil after the var is cleared |
| Extract the Swift object with `toObjectOf(T.self)` | All child types are `@objc class` NSObject subclasses; this cast is safe |
| Call `shutdownForLeakTest()` **inside** the `autoreleasepool {}` block | Sync GC must run while the context is still alive |
| Call `assertNoLeaks()` **outside** the `autoreleasepool {}` block | The context (and any bridged objects) must be released first |
| **Start/use the object actively** — see table below | An unstarted object skips the interesting cleanup paths (pending activity, NSNotificationCenter observers, OS browser delegates, etc.) |

### What "actively using" means per object type

| Object | How to activate |
|---|---|
| `HSTimer` (repeating) | `hs.timer.doEvery(0.05, fn)` + `RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))` so it fires |
| `HSTimer` (one-shot) | `hs.timer.doAfter(0.05, fn)` + same run-loop drain |
| `HSHotkey` | `bind()` already enables it; add `hk.disable()` + `hk.enable()` to cycle state |
| `HSHotkeyModal` | `modal.bind(…)` to add hotkeys + `modal.enter()` to make it active |
| `HSEventTap` | `tap.start()` — succeeds with Accessibility, fails silently without it; `destroy()` handles both |
| `HSSpotlightQuery` | `q.setQuery("…").setCallback(fn).start()` — use an intentionally unmatchable predicate |
| `HSNotification` | `n.send()` — display may fail without permission; the object is still used |
| `HSBonjourSearch` | `search.findServices('_http._tcp.', 'local.', fn)` to start browsing |
| `HSTask` | `t.start()` with a long-running command (`/bin/sleep 10`) so the process is definitely alive when `shutdown()` is called |

### Why each object type needs specific handling

- **Timers** — a running `HSTimer` is active in its module's `HSObjectTracker` (and
  retained by Foundation's `Timer` target ref) until `stop()`. `shutdown()` → `destroy()` →
  `stop()` ends both, and `removeAllObjects()` drops any pin left behind.
- **Hotkeys** — `enabledHotkeys` is a **strong** array in `HSHotkeyModule`. Enabled
  hotkeys are not freed until `shutdown()` clears the array.
- **EventTaps** — `start()` sets `selfRetain = self` to keep the tap alive while
  capturing events. `destroy()` → `stop()` clears it.
- **SpotlightQuery / BonjourSearch** — `NSNotificationCenter` and
  `NSNetServiceBrowser` hold strong delegate/observer refs. `destroy()` removes
  them; without `destroy()` these objects can never be freed.
- **Tasks** — a running `HSTask` is active in its module's `HSObjectTracker` until it
  terminates. `shutdown()` → `destroy()` ends it (and SIGTERMs the process).
- **Anything else with pending activity** — an active object is pinned through its JS
  wrapper, which holds the `JSContext`. A module whose `shutdown()` skips
  `removeAllObjects()` shows up as a leak here.

## Pending-activity tests (mandatory for objects that can be active)

### The harness teardown check (automatic)

`JSTestHarness` fails any test that ends with an object still active that should have
finished on its own: one its module marks `finishesOnItsOwn` in `setActive` (a task, a
one-shot timer, a playing sound, a ping). It records an issue naming the objects. That's what
catches an object that never becomes inactive (a one-shot timer still pinned after it fires,
a task still pinned after it exits), which would otherwise leak until the next reload. So
tests MUST wait for such objects to finish (`await harness.waitForTasksToComplete()`, a
`waitFor` on their callback) or stop them.

Objects that run until they're stopped (watchers, hotkeys, repeating timers) may be left
active; module shutdown stops them. A test that deliberately ends with a self-finishing object
still running sets `harness.allowsActiveObjectsAtTeardown = true`.

Synchronous tests can't wait for anything delivered through a main-actor `Task`, such as an
`HSTask`'s termination: `waitFor` spins the run loop, but a main-actor job can't run while
the test itself is running on the main actor. Make those tests `async` and use
`waitForAsync`/`waitForTasksToComplete()`. Never `Thread.sleep` to wait for a task.

### The two GC tests

Any object that can be active (see "Object lifetime" in the HSModule skill) also needs two
garbage-collection tests, in addition to the leak test:

1. **Active and unreferenced → keeps working.** Start the object *without* storing it in
   a JS variable, force a collection, and check that its callback still fires.
2. **Inactive and unreferenced → collected.** Hold it in a `weak var`, stop it (or let it
   finish), drop the JS reference, force a collection, and check the `weak var` is nil.

`harness.collectGarbage()` runs the synchronous collector (twice, so anything only weakly
reachable is reclaimed).

```swift
@Test("A doAfter timer the caller didn't keep still fires after garbage collection")
func testUnreferencedDoAfterSurvivesGC() {
    let harness = JSTestHarness()
    harness.loadModule(HSTimerModule.self, as: "timer")
    var fired = false
    harness.registerCallback("onFire") { fired = true }

    // `void` + autoreleasepool: otherwise eval's result is a JSValue holding the
    // timer's wrapper, which pins it and makes the test pass even without the fix
    autoreleasepool { _ = harness.eval("void hs.timer.doAfter(0.05, function() { __test_callback('onFire'); })") }
    harness.collectGarbage()

    #expect(harness.waitFor(timeout: 0.5) { fired })
}

@Test("A stopped timer the caller didn't keep is garbage collected")
func testStoppedTimerIsCollected() {
    let harness = JSTestHarness()
    harness.loadModule(HSTimerModule.self, as: "timer")
    weak var timer: HSTimer?
    autoreleasepool {   // drains the JSValue returned by evalValue
        harness.eval("var t = hs.timer.doEvery(60, function() {})")
        timer = harness.evalValue("t")?.toObjectOf(HSTimer.self) as? HSTimer
        harness.eval("t.stop(); t = null")
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    harness.collectGarbage()
    #expect(timer == nil)
}
```

Test 1 is the one that catches `selfRetain`-style bugs: the Swift object survives but its
`JSCallback` is collected, so the callback silently never fires. Check that it fails with
the `setActive` call removed before relying on it. If it doesn't fail, something in the test
is still holding the wrapper — most often the script's completion value: a script ending in
`hs.foo.create(...).start()` *returns* the object, and `harness.eval` hands that back as an
autoreleased `JSValue` that keeps the wrapper alive. Prefix with `void` and wrap the eval in
`autoreleasepool {}`.

### One test per object type is sufficient

You do not need separate tests for "created but not started" and "active". A single
test that actively uses the object is more valuable than two tests where one skips
the interesting cleanup paths.

---

## Async tests — timing and callbacks

### Registering Swift callbacks from JS

```swift
var fired = false
harness.registerCallback("onEvent") {
    fired = true
}

// In JS, call: __test_callback('onEvent')
harness.eval("hs.timer.doAfter(0.05, () => __test_callback('onEvent'))")

let success = harness.waitFor(timeout: 0.2) { fired }
#expect(success, "callback should have fired")
#expect(fired)
```

For callbacks with typed arguments:

```swift
var exitCode: Int = -1
harness.registerCallback("onDone") { (code: Int) in
    exitCode = code
}
// In JS: taskComplete(0)  [the callback is registered as the global name]
```

### Synchronous wait (preferred for simple timer tests)

```swift
let success = harness.waitFor(timeout: 0.5) { someCondition }
#expect(success, "condition should have been met")
```

`waitFor` spins the RunLoop in 10ms steps so timers and notifications fire normally.

### Async wait (for tests that touch MainActor tasks)

```swift
@Test("task fires completion callback")
func testTaskCompletion() async {
    let harness = JSTestHarness()
    harness.loadModule(HSTaskModule.self, as: "task")
    var done = false
    harness.registerCallback("onDone") { done = true }
    harness.eval("hs.task.new('/bin/echo', ['hi'], () => __test_callback('onDone')).start()")
    let ok = await harness.waitForAsync(timeout: 2.0) { done }
    #expect(ok)
}
```

### Draining the MainActor queue between tests

For test suites that touch async Swift machinery, add an async `init` that drains
the queue so one test's work doesn't bleed into the next:

```swift
@Suite("hs.task tests", .serialized)
struct HSTaskTests {
    init() async {
        await JSTestHarness.drainMainActorQueue()
    }
}
```

### Timer interval guidelines

Keep test timers fast. Recommended values:
- Timer interval: **0.02s – 0.05s** (fast enough to fire quickly)
- `waitFor` timeout: **3–5× the timer interval** (enough headroom, short enough to fail fast)
- Never use intervals over 0.5s in tests

---

## Tests that modify shared system state

When a test must write to shared OS state (system pasteboard, files), save and
restore it in a helper:

```swift
private func withSavedPasteboard(_ body: () -> Void) {
    let saved = NSPasteboard.general.pasteboardItems?.map { ... }
    body()
    // restore...
}

@Test("writeString round-trips through readString")
func testStringRoundTrip() {
    withSavedPasteboard {
        let harness = makeHarness()
        harness.eval("hs.pasteboard.writeString('hello')")
        harness.expectEqual("hs.pasteboard.readString()", "hello")
    }
}
```

Mark suites that touch shared state with `.serialized` to prevent races:

```swift
@Suite("hs.pasteboard read/write tests", .serialized)
struct HSPasteboardReadWriteTests { ... }
```

---

## Pure Swift tests (no JSTestHarness)

For testing internal Swift logic that has no JS surface (managers, pure value
types, enum metadata, etc.), use Swift Testing directly without JSTestHarness:

```swift
import Testing
import Foundation
@testable import Hammerspoon_2

struct PermissionsTypeMetadataTests {

    @Test("All permission types have non-empty displayName")
    func testAllDisplayNamesNonEmpty() {
        for permType in PermissionsType.allCases {
            #expect(!permType.displayName.isEmpty)
        }
    }

    @Test("accessibility displayName is correct")
    func testAccessibilityDisplayName() {
        #expect(PermissionsType.accessibility.displayName == "Accessibility")
    }
}
```

---

## Mocks

When a component under test has external dependencies (JS engine, file system,
settings), inject a mock via dependency injection and place the mock in
`Hammerspoon 2Tests/Mocks/`:

```swift
// Mocks/MockFoo.swift
import Foundation
@testable import Hammerspoon_2

class MockFoo: FooProtocol {
    var callCount = 0
    var shouldFail = false
    var lastArgument: String?

    func doThing(_ arg: String) throws {
        callCount += 1
        lastArgument = arg
        if shouldFail { throw SomeError.failure }
    }

    func reset() {
        callCount = 0
        shouldFail = false
        lastArgument = nil
    }
}
```

Expose every configurable behaviour as a `Bool` flag (`shouldFail`, `shouldThrow`)
and record all call arguments so tests can assert on them.

---

## What NOT to test

- **Hardware mutations**: don't call `setMode()`, change audio routing, set display
  origin, or mirror displays — these disrupt the developer's desktop mid-run.
- **Network-dependent assertions**: geocoding, URL loading, and similar async
  network calls are too flaky for the test suite. Test that the Promise is returned
  and has a `.then` method; don't await actual network results.
- **UI display**: notifications, alerts, and windows cannot be verified visually in
  a test runner. Test API shape and non-throwing execution; document the limitation
  in the suite docstring.
- **Permissions dialogs**: never trigger permission request dialogs from a test.
  Test `check*` (which returns a bool) but not `request*` (which shows a system
  dialog). Gate hardware-dependent tests with `.disabled(if:)`.
- **Real-time sensor data**: GPS location, camera frames, and microphone audio
  are unavailable in the test environment. Test API shape and watcher object
  lifecycle only.
- **Existence of class methods/properties** There is little point testing that the source
  code still contains itself.

---

## Quick checklist

- [ ] File is in the correct `*Tests/` subdirectory
- [ ] Filename matches `HSFooIntegrationTests.swift` pattern
- [ ] Imports are `Testing`, `JavaScriptCore`, `@testable import Hammerspoon_2`
- [ ] All inner suites are nested inside a top-level `@Suite("hs.foo tests") struct HSFooTests {}`
- [ ] Tests are structs with `@Test("description")` on each function
- [ ] A `makeHarness()` factory avoids repeated boilerplate
- [ ] Suite 1 covers every public protocol member (type + existence)
- [ ] Suite 2 covers deterministic behaviour (no OS permissions needed)
- [ ] Permission/hardware-gated suites use `.disabled(if: ...)` with a `nonisolated` guard
- [ ] `#expect(!harness.hasException)` after every non-trivial `eval()`
- [ ] Async tests use `waitForAsync` or `waitFor` rather than `Thread.sleep` where possible
- [ ] Every test waits for (or stops) anything that finishes on its own, or the harness teardown check fails it
- [ ] State-mutating tests use `.serialized` and save/restore shared state
- [ ] Nothing triggers permission dialogs, hardware mutations, or live network calls
- [ ] **If the module creates child JS objects**: a `testFooDoesNotLeakAfterReload()` test exists that (a) creates AND actively starts the object, (b) tracks it with `WeakLeakTracker`, (c) wraps the harness in an `autoreleasepool {}` block, and (d) calls `tracker.assertNoLeaks()` after the block
