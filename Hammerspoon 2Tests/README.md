# Hammerspoon 2 Testing Guide

## Overview

Hammerspoon 2 uses **JavaScript Integration Testing** to ensure modules work correctly when called from JavaScript, exactly as users will consume them. This approach tests the complete stack: Swift implementation → JSExport bridging → JavaScript enhancements.

## Test Architecture

### 🏗️ Test Infrastructure

#### `JSTestHarness` (Helpers/JSTestHarness.swift)

The core testing utility that provides:

- **Clean JSContext** for each test
- **Module loading** with automatic JavaScript enhancement injection
- **Async/callback testing** with timeout support
- **Assertion helpers** for common JavaScript checks
- **Exception handling** and error reporting

**Example Usage:**
```swift
let harness = JSTestHarness()
harness.loadModule(HSHashModule.self, as: "hash")

let result = harness.eval("hash.md5('hello')")
#expect(result as? String == "5d41402abc4b2a76b9719d911017c592")
```

### 📁 Test Organization

```
Hammerspoon 2Tests/
├── Helpers/
│   └── JSTestHarness.swift          # Core test infrastructure
├── IntegrationTests/
│   ├── HSHashIntegrationTests.swift       # Pure function testing
│   ├── HSTimerIntegrationTests.swift      # Async & callback testing
│   ├── HSApplicationIntegrationTests.swift # Object bridging testing
│   └── JSEnhancementTests.swift           # JavaScript enhancement testing
├── ManagerTests/
│   └── ManagerManagerTests.swift     # Existing unit tests
└── Mocks/
    ├── MockJSEngine.swift
    ├── MockFileSystem.swift
    └── MockSettingsManager.swift
```

## Test Suites

### 1️⃣ Hash Module Tests (`HSHashIntegrationTests.swift`)

**What it tests:**
- Base64 encoding/decoding with Unicode support
- MD5, SHA1, SHA256, SHA512 hashing
- HMAC authentication codes
- Round-trip encoding/decoding
- Real-world patterns (password verification, API signatures, data integrity)

**Key tests:**
- `testBase64RoundTrip()` - Validates encoding works with complex Unicode
- `testPasswordVerificationPattern()` - Real-world password hashing pattern
- `testDataIntegrityPattern()` - Checksum verification pattern

**Example:**
```swift
@Test("Base64 encode/decode round-trip with complex data")
func testBase64RoundTrip() {
    let harness = JSTestHarness()
    harness.loadModule(HSHashModule.self, as: "hash")

    harness.eval("var testString = 'Emoji test: 😀😃😄'")
    harness.expectEqual(
        "hash.base64Decode(hash.base64Encode(testString))",
        "Emoji test: 😀😃😄"
    )
}
```

### 2️⃣ Timer Module Tests (`HSTimerIntegrationTests.swift`)

**What it tests:**
- Timer creation (`doAfter`, `doEvery`, `new`)
- Timer lifecycle (start, stop, running state)
- Callback execution (one-shot and repeating)
- Time utilities (secondsSinceEpoch, absoluteTime, localTime)
- JavaScript enhancements (minutes, hours, days, weeks, seconds parser)
- Predicate-based timers (waitUntil, doUntil, doWhile)
- Delayed/debounced timers

**Key tests:**
- `testDoAfterFromJS()` - Validates async callback execution
- `testTimerStop()` - Ensures timers stop when requested
- `testDelayedTimer()` - Tests debouncing pattern
- `testPollingPattern()` - Real-world polling use case

**Example:**
```swift
@Test("doAfter creates and fires a one-shot timer")
func testDoAfterFromJS() {
    let harness = JSTestHarness()
    harness.loadModule(HSTimerModule.self, as: "timer")

    var callbackFired = false
    harness.registerCallback("testCallback") {
        callbackFired = true
    }

    harness.eval("timer.doAfter(0.05, testCallback)")

    let success = harness.waitFor(timeout: 0.2) { callbackFired }
    #expect(success, "Timer should have fired within timeout")
}
```

### 3️⃣ Application Module Tests (`HSApplicationIntegrationTests.swift`)

**What it tests:**
- Application discovery (runningApplications, frontmost, matchingName)
- Application objects (name, bundleID, pid, path)
- Bundle operations (pathForBundleID, infoForBundlePath)
- Application state (isHidden, isRunning, isFrontmost)
- Real-world patterns (finding browsers, filtering apps, switching apps)

**Key tests:**
- `testRunningApplicationsFromJS()` - Validates object array bridging
- `testFromPID()` - Tests PID lookup round-trip
- `testFindBrowsersPattern()` - Real-world app filtering
- `testGetApplicationInfo()` - Object property access pattern

**Note:** These tests interact with real running applications on the system.

**Example:**
```swift
@Test("Find all browsers pattern works")
func testFindBrowsersPattern() async {
    let harness = JSTestHarness()
    harness.loadModule(HSApplicationModule.self, as: "application")

    harness.eval("""
    var browserBundleIDs = [
        'com.apple.Safari',
        'com.google.Chrome',
        'org.mozilla.firefox'
    ];

    var runningBrowsers = browserBundleIDs
        .map(function(id) { return application.matchingBundleID(id); })
        .filter(function(app) { return app !== null; });
    """)

    harness.expectTrue("Array.isArray(runningBrowsers)")
}
```

### 4️⃣ JavaScript Enhancement Tests (`JSEnhancementTests.swift`)

**What it tests:**
- Automatic loading of .js enhancement files
- Time conversion functions (minutes, hours, days, weeks)
- Time string parsing (HH:MM:SS, duration formats)
- Predicate-based timer functions
- Delayed/debounced timer objects
- Enhancement error handling
- Real-world enhancement patterns (debouncing, scheduling, polling)

**Key tests:**
- `testEnhancementsAutoLoad()` - Validates .js files load with modules
- `testTimerSecondsParser()` - Tests flexible time parsing
- `testDebouncingUseCase()` - Real-world debounce pattern
- `testEnhancementsDontBreakCore()` - Ensures compatibility

**Example:**
```swift
@Test("Timer.seconds() parses various formats")
func testTimerSecondsParser() {
    let harness = JSTestHarness()
    harness.loadModule(HSTimerModule.self, as: "timer")

    // Duration formats
    harness.expectEqual("timer.seconds('30s')", 30.0)
    harness.expectEqual("timer.seconds('5m')", 300.0)
    harness.expectEqual("timer.seconds('2h')", 7200.0)

    // Time of day formats
    harness.expectEqual("timer.seconds('01:30:00')", 5400.0)
    harness.expectEqual("timer.seconds('12:00')", 43200.0)
}
```

## JSTestHarness API Reference

### Module Loading

```swift
// Load a single module
harness.loadModule(HSHashModule.self, as: "hash")

// Load the full ModuleRoot (mimics real environment)
harness.loadModuleRoot()
```

### Script Execution

```swift
// Evaluate and get Swift-typed result
let result = harness.eval("1 + 1")  // Returns 2 as Any

// Evaluate and get raw JSValue
let jsValue = harness.evalValue("({foo: 'bar'})")

// Check for exceptions
harness.eval("throw new Error('test')")
if harness.hasException {
    print(harness.exceptionMessage)
}
```

### Async Testing

```swift
// Register a callback that JavaScript can invoke
var called = false
harness.registerCallback("myCallback") {
    called = true
}
harness.eval("myCallback()")

// Register callback with arguments
harness.registerCallback("withArgs") { (arg: String) in
    print("Got: \(arg)")
}

// Wait for a condition with timeout
let success = harness.waitFor(timeout: 1.0) { called }
```

### Assertions

```swift
// Assert JavaScript expression is true
harness.expectTrue("typeof hash === 'object'")

// Assert JavaScript expression is false
harness.expectFalse("nonexistent === undefined")

// Assert JavaScript expression equals value
harness.expectEqual("1 + 1", 2)

// Assert exception was thrown
harness.eval("throw new Error()")
harness.expectException()
```

## Running Tests

### In Xcode

1. Open Hammerspoon 2.xcodeproj
2. Select the "Hammerspoon 2" scheme
3. Press `Cmd+U` or Product → Test
4. View results in the Test Navigator (Cmd+6)

### Command Line

```bash
# Run all tests
xcodebuild test -scheme "Hammerspoon 2" -destination 'platform=macOS'

# Run specific test suite
xcodebuild test -scheme "Hammerspoon 2" \
    -destination 'platform=macOS' \
    -only-testing:Hammerspoon_2Tests/HSHashIntegrationTests

# Run specific test
xcodebuild test -scheme "Hammerspoon 2" \
    -destination 'platform=macOS' \
    -only-testing:Hammerspoon_2Tests/HSHashIntegrationTests/testMD5FromJS
```

## Writing New Tests

### Pattern 1: Testing Pure Functions

For modules like hs.hash that have pure functions:

```swift
@Test("MD5 hash produces correct output")
func testMD5FromJS() {
    let harness = JSTestHarness()
    harness.loadModule(HSHashModule.self, as: "hash")

    harness.expectEqual("hash.md5('hello')", "5d41402abc4b2a76b9719d911017c592")
}
```

### Pattern 2: Testing Async Behavior

For modules with callbacks and timers:

```swift
@Test("Timer fires callback")
func testTimerCallback() {
    let harness = JSTestHarness()
    harness.loadModule(HSTimerModule.self, as: "timer")

    var fired = false
    harness.registerCallback("onFire") { fired = true }

    harness.eval("timer.doAfter(0.1, onFire)")

    let success = harness.waitFor(timeout: 0.3) { fired }
    #expect(success, "Timer should have fired")
}
```

### Pattern 3: Testing Object Bridging

For modules that return Swift objects to JavaScript:

```swift
@Test("Application object has correct properties")
func testApplicationObject() async {
    let harness = JSTestHarness()
    harness.loadModule(HSApplicationModule.self, as: "application")

    harness.eval("var app = application.frontmost()")
    harness.expectTrue("typeof app.name === 'function'")
    harness.expectTrue("typeof app.bundleID === 'function'")
}
```

### Pattern 4: Testing JavaScript Enhancements

For testing .js enhancement files:

```swift
@Test("Enhancement function exists")
func testEnhancement() {
    let harness = JSTestHarness()
    harness.loadModule(HSTimerModule.self, as: "timer")

    // Enhancement should be auto-loaded
    harness.expectTrue("typeof timer.minutes === 'function'")
    harness.expectEqual("timer.minutes(5)", 300.0)
}
```

## Best Practices

### ✅ DO

- **Test real user patterns** - Write tests that mirror how users will actually use the modules
- **Test JavaScript integration** - Focus on the JS→Swift bridging, not just Swift internals
- **Use descriptive test names** - Make failures self-documenting
- **Test error cases** - Ensure proper error handling and exception throwing
- **Keep tests fast** - Use short timeouts (50-200ms) for async tests
- **Clean up resources** - Stop timers, remove watchers in tests

### ❌ DON'T

- **Don't test Swift internals** - These are integration tests, not unit tests
- **Don't use long timeouts** - Keep tests fast; 1-2 seconds max
- **Don't test implementation details** - Test the public API only
- **Don't skip cleanup** - Leaking timers/watchers can cause flaky tests
- **Don't ignore MainActor** - Mark tests `@MainActor` if they use AppKit/UI

## Test Coverage Statistics

As of 2025-11-06:

| Module | Tests | Coverage |
|--------|-------|----------|
| hs.hash | 17 tests | ✅ Complete |
| hs.timer | 26 tests | ✅ Complete |
| hs.application | 21 tests | ✅ Complete |
| JS Enhancements | 19 tests | ✅ Complete |
| **Total** | **83 integration tests** | |

## Troubleshooting

### Tests not running?

1. Check that the test target is enabled in your scheme:
   - Product → Scheme → Edit Scheme → Test tab
   - Ensure "Hammerspoon 2Tests" is checked

### Tests failing with "context is nil"?

- Ensure JavaScriptCore is available on your system
- Check that modules are being loaded correctly
- Verify test target has access to app bundle resources

### Timer tests are flaky?

- Increase timeouts (but keep them reasonable)
- Use `harness.waitFor()` instead of fixed `Thread.sleep()`
- Ensure timers are stopped in cleanup

### Application tests failing?

- Check that the app being tested (e.g., Finder) is actually running
- Grant necessary permissions (Accessibility) if testing window/AX modules
- Use `@MainActor` for tests that interact with AppKit

## Next Steps

### Modules Still Needing Tests

- hs.appinfo - Application metadata
- hs.console - Console window control
- hs.permissions - System permission management
- hs.ax - Low-level Accessibility API
- hs.window - High-level window management

### Recommended Test Additions

1. **Performance tests** - Ensure operations complete within acceptable time
2. **Memory leak tests** - Verify timers/objects clean up properly
3. **Concurrent tests** - Test module behavior with multiple simultaneous calls
4. **Error injection tests** - Test behavior when macOS APIs fail
5. **Real-world config tests** - Test complete user configurations

## Resources

- [Apple Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [JavaScriptCore Framework Reference](https://developer.apple.com/documentation/javascriptcore)
- [Hammerspoon 1.0 Test Suite](https://github.com/Hammerspoon/hammerspoon/tree/master/tests) (for inspiration)

---

**Happy Testing! 🧪**

*Questions? Issues? Check the main README or open an issue on GitHub.*
