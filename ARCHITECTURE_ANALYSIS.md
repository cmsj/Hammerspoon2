# Hammerspoon 2 - Architectural Analysis & Improvement Suggestions

**Date:** 2025-10-29
**Codebase:** Hammerspoon 2
**Total LOC:** ~1,861 lines of Swift + 131 lines of JavaScript

---

## Executive Summary

Hammerspoon 2 is a well-architected macOS automation tool that bridges JavaScript scripting with native macOS capabilities. It uses a **modular, protocol-based design** with clear separation between the JavaScript engine layer, module system, managers, and UI. The architecture leverages both modern Swift features (SwiftUI, @Observable) and Apple frameworks (JavaScriptCore, Cocoa, Accessibility Services). The codebase is relatively compact but functionally complete for current use cases, with clear extension points for new modules and features.

**Key Strengths:**
- Clean separation of concerns
- Extensible module system
- Type-safe Swift implementation
- Good resource management

**Key Areas for Improvement:**
- Error handling and resilience
- Dependency injection and testability
- Thread safety and concurrency
- Documentation and developer experience

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Current Architecture](#current-architecture)
3. [Architectural Improvement Suggestions](#architectural-improvement-suggestions)
4. [Priority Matrix](#priority-matrix)
5. [Implementation Roadmap](#implementation-roadmap)

---

## Project Overview

### What is Hammerspoon 2?

Hammerspoon 2 is a macOS automation and configuration application that allows users to write JavaScript-based scripts to control and interact with their Mac. It's a modernized rewrite/successor to the original Hammerspoon project.

**Key Purpose:**
- Provide JavaScript-based scripting for macOS automation
- Allow users to control applications, timers, system interactions
- Offer accessibility features through a console UI
- Support user configuration through JavaScript files (init.js)
- Provide auto-update capabilities via Sparkle

**Target Users:** macOS power users and developers who want to automate their Mac using JavaScript

---

## Current Architecture

### Overall Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    SwiftUI Frontend (macOS)                      │
│  ┌──────────────┬──────────────┬────────────┬──────────────────┐ │
│  │ConsoleView   │SettingsView  │ ContentView│ AboutView        │ │
│  │(JS console)  │(Config UI)   │(Main)      │(App info)        │ │
│  └──────────────┴──────────────┴────────────┴──────────────────┘ │
└──────────────────────────────────┬──────────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────────┐
│               Managers Layer (Singleton Pattern)                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ManagerManager (Boot/Shutdown orchestration)               ││
│  │ SettingsManager (Config persistence via UserDefaults)      ││
│  │ PermissionsManager (Accessibility permissions)             ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────────────────────────┬──────────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────────┐
│                JavaScript Engine Layer                           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ JSEngine (Singleton)                                        ││
│  │  - Manages JSVirtualMachine & JSContext                    ││
│  │  - Provides subscript access to context variables          ││
│  │  - Loads & executes user config files                      ││
│  │  - Injects logging console object                          ││
│  │  - Loads engine.js and module-specific JS files            ││
│  └─────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ ModuleRoot (ns.xxx namespace root in JS)                   ││
│  │  - Lazy-loads modules on first access                      ││
│  │  - Manages module lifecycle                                ││
│  │  - Provides reload() for config reloading                  ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────────────────────────┬──────────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────────┐
│              Module System (HSModuleAPI Protocol)                │
│  ┌──────────────┬──────────────┬───────────┬─────────────────┐  │
│  │hs.appInfo    │hs.application│hs.console │hs.permissions  │  │
│  │hs.timer      │hs.hashing    │hs.window* │                │  │
│  └──────────────┴──────────────┴───────────┴─────────────────┘  │
│  (* indicates incomplete/not enabled)                            │
└──────────────────────────────────┬──────────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────────┐
│               macOS System Framework Integration                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │NSWorkspace (app lifecycle, notifications)                  ││
│  │Cocoa/AppKit (application control)                          ││
│  │AXSwift (accessibility framework)                           ││
│  │ApplicationServices (accessibility API)                     ││
│  │Sparkle (auto-updates)                                      ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```

### Main Components

1. **Lifecycle** (`Hammerspoon_2App.swift`)
   - App entry point
   - AppDelegate for lifecycle hooks
   - Menu bar integration
   - Window management (Console, Settings, About)

2. **Engine** (JavaScript Runtime)
   - `JSEngine.swift` - Manages JSVirtualMachine and JSContext
   - `ModuleRoot.swift` - Root namespace (hs) object
   - `HSModuleAPI.swift` - Base protocol for modules

3. **Modules** (Scriptable APIs)
   - AppInfo - App metadata (version, build, etc)
   - Application - App control and lifecycle monitoring
   - Console - Console window control
   - Timer - Scheduled callbacks
   - Hash - Encoding/decoding utilities
   - Permissions - Accessibility permission management
   - Windows - (Incomplete) Window management via Accessibility

4. **Managers** (Application State)
   - ManagerManager - Orchestrates boot/shutdown
   - SettingsManager - Configuration persistence
   - PermissionsManager - Accessibility permission checks

5. **Windows/UI** (SwiftUI Views)
   - ConsoleView - REPL for JavaScript with history
   - SettingsView - Configuration management
   - AboutView - App information

6. **Utilities**
   - Logging - Structured logging with HammerspoonLog
   - Exceptions - Custom error types
   - Extensions - Extension methods (NSRunningApplication)
   - Sparkle integration - Auto-update support

### Technologies & Frameworks

**Primary Technologies:**
- **Language:** Swift 5.9+ (macOS native)
- **UI Framework:** SwiftUI (modern Apple UI framework)
- **JavaScript Engine:** JavaScriptCore (Apple's built-in JS runtime)
- **Package Manager:** Xcode (native build system)

**Key Frameworks & Libraries:**
- **Cocoa/AppKit** - macOS application control
- **Accessibility Services** - AXSwift library for app/window control
- **Sparkle** - Software update framework
- **Foundation** - Core utilities
- **os.Logger** - System logging

**Architecture Patterns:**
- **Singleton Pattern** - JSEngine, ManagerManager, SettingsManager, PermissionsManager, HammerspoonLog
- **Protocol-Based Design** - HSModuleAPI, JSExport (for JS bridging)
- **Lazy Loading** - Modules loaded on-demand via getOrCreate()
- **Observer Pattern** - NSWorkspace notifications for app lifecycle events
- **SwiftUI Observable** - @Observable for reactive state management

### Directory Structure

```
Hammerspoon 2/
├── Engine/                           # JavaScript VM and initialization
│   ├── JSEngine.swift               # Core JS runtime management
│   ├── ModuleRoot.swift             # 'hs' namespace implementation
│   ├── HSModuleAPI.swift            # Module protocol
│   └── engine.js                    # JS-side bootstrap code
│
├── Modules/                          # Scriptable functionality
│   ├── AppInfo.swift                # hs.appInfo module
│   ├── Console.swift                # hs.console module
│   ├── Hash.swift                   # hs.hashing module
│   ├── Permissions.swift            # hs.permissions module
│   ├── Timer.swift                  # hs.timer module
│   ├── Windows.swift                # hs.window module (incomplete)
│   └── hs.application/              # hs.application namespace
│       ├── ApplicationModule.swift   # Module implementation
│       ├── ApplicationObject.swift   # HSApplication object
│       └── hs.application.js         # JS watcher helper
│
├── Managers/                         # Application state managers
│   ├── ManagerManager.swift          # Boot/shutdown orchestration
│   ├── SettingsManager.swift         # Configuration persistence
│   └── PermissionsManager.swift      # System permissions
│
├── Windows/                          # SwiftUI interface
│   ├── ContentView.swift             # Main window (mostly test harness)
│   ├── ConsoleView.swift             # Interactive JS console
│   ├── AboutView.swift               # About dialog
│   └── Settings/
│       ├── SettingsView.swift        # Settings window container
│       ├── SettingsConfigView.swift  # Config file picker
│       └── SettingsAdvancedView.swift# Auto-update settings
│
├── Utilities/                        # Helper functionality
│   ├── Logging.swift                 # HammerspoonLog infrastructure
│   ├── Exceptions.swift              # HammerspoonError type
│   ├── Sparkle.swift                 # Update UI components
│   └── Extensions/
│       └── NSRunningApplication.swift# App conversion helper
│
├── Lifecycle/
│   └── Hammerspoon_2App.swift        # App entry point
│
└── Assets.xcassets                   # App icons and assets
```

### Key Files

| File | Lines | Role |
|------|-------|------|
| **JSEngine.swift** | ~130 | Core runtime - manages VM, context, JS evaluation, logging injection |
| **ModuleRoot.swift** | ~75 | Implements `hs` namespace, lazy-loads modules, manages lifecycle |
| **Hammerspoon_2App.swift** | ~104 | SwiftUI app entry, menu bar, window management, app lifecycle |
| **ManagerManager.swift** | ~32 | Orchestrates boot (JS init), config loading, shutdown |
| **ApplicationModule.swift** | ~233 | Main hs.application implementation - app queries, watchers, file type handling |
| **ConsoleView.swift** | ~157 | Interactive REPL console with history, filtering, evaluation |
| **SettingsManager.swift** | ~69 | UserDefaults-based config (config file path, console history length) |
| **Logging.swift** | ~117 | Structured logging with filtering, timestamp formatting |
| **engine.js** | ~50 | Bootstrap JS - defines EventEmitter, gets injected at startup |
| **hs.application.js** | ~82 | Implements watcher multiplexing (1:many events from 1:1 Swift API) |
| **ApplicationObject.swift** | ~69 | HSApplication object - app properties (pid, bundleID, hidden, active) |
| **Timer.swift** | ~154 | hs.timer - scheduled callbacks via Foundation.Timer |
| **PermissionsManager.swift** | ~43 | Accessibility permission checks using AXIsProcessTrusted() |

### Communication Patterns

**1. Swift ↔ JavaScript Bridge (JavaScriptCore)**

```
┌─── Swift Layer ───┐         ┌─── JavaScript Layer ───┐
│                   │         │                        │
│ @objc protocol    │◄───────►│ JSExport              │
│ HSApplicationsAPI │ JSValue  │ interface             │
│                   │         │                        │
│ @objc class       │◄───────►│ JavaScript object      │
│ HSApplicationModule         │ (via bridge)           │
└───────────────────┘         └────────────────────────┘
```

- **Protocol-Based Export** - @objc protocols define JS-accessible APIs
- **JSExport Conformance** - Bridges Swift objects to JS context
- **JSValue Callbacks** - JS functions passed to Swift, called as needed
- **Subscript Access** - `JSEngine[key]` for getting/setting context variables

**2. Event Handling (Observer Pattern)**

```
NSWorkspace.notificationCenter
    │
    ├─► willLaunchApplicationNotification
    │   └─► HSApplicationWatcherObject
    │       └─► JavaScript callback
    │
    ├─► didLaunchApplicationNotification
    │   └─► HSApplicationWatcherObject
    │       └─► JavaScript callback
    └─► ... (6 more app lifecycle events)
```

- **NSWorkspace Notifications** - System-level app events
- **Watcher Objects** - Holds references to JS callbacks
- **Event Multiplexing** - Swift 1:1 watcher → JS 1:many listeners (in hs.application.js)

**3. Module Loading (Lazy Singleton Pattern)**

```
ModuleRoot.getOrCreate<T>(name, type)
    │
    ├─► Check modules[name]
    │   ├─ If exists: return cached instance
    │   └─ If missing:
    │       ├─► Create new instance of type T
    │       ├─► Store in modules[name]
    │       └─► Load hs.modulename.js if exists
    │
    └─► Return module instance
```

- **On-Demand Loading** - Modules instantiated when first accessed
- **Bundled JS Enhancement** - Each module can include companion .js file
- **Cached Instances** - Same module returned on subsequent accesses

### Data Flow Examples

**Example 1: User launches app**
```
1. Hammerspoon_2App.main()
2. AppDelegate.applicationDidFinishLaunching()
3. ManagerManager.shared.boot()
4. JSEngine.resetContext()
   ├─ Create JSVirtualMachine
   ├─ Create JSContext
   ├─ Inject console object (logging)
   ├─ Load engine.js (EventEmitter)
   └─ Inject ModuleRoot as "hs"
5. ManagerManager.boot() loads user config file
6. JSEngine.evalFromURL(settingsManager.configLocation)
7. User code runs with full hs API available
```

**Example 2: User interacts with hs.application.addWatcher()**
```
1. JavaScript: hs.application.addWatcher("didLaunch", callback)
2. hs.application.js multiplexer routes to hs.application._addWatcher()
3. Swift: HSApplicationModule._addWatcher(eventName, jsCallback)
4. Register NSWorkspace notification observer
5. Store HSApplicationWatcherObject with callback reference
6. When app launches:
   ├─ NSWorkspace posts didLaunchApplicationNotification
   ├─ HSApplicationWatcherObject.handleEvent() called
   ├─ Convert NSRunningApplication to HSApplication
   └─ Call JS callback with (eventName, app)
```

**Example 3: Console REPL evaluation**
```
1. User types: "hs.appInfo.version" + Enter
2. ConsoleView.onSubmit()
3. JSEngine.shared.eval(evalString)
4. Returns JSValue from context
5. Convert JSValue to String
6. AKConsole() log message
7. HammerspoonLog.shared.log() adds entry
8. @Observable triggers ConsoleView re-render
9. New log entry appears in console
```

### Current Strengths

1. **Clean Separation of Concerns**
   - Engine isolated from UI
   - Managers separate from modules
   - Well-defined module protocol

2. **Extensibility**
   - Modular system allows easy addition of new modules
   - Protocol-based design decouples implementations
   - JavaScript enhancement files allow behavior customization

3. **Type Safety**
   - Swift provides compile-time safety
   - JSExport protocols enforce JS API contracts
   - Custom error types (HammerspoonError)

4. **Resource Management**
   - Singleton managers prevent multiple instances
   - Module shutdown() allows cleanup
   - Timer tracking prevents orphaned callbacks

5. **User Experience**
   - Interactive console with history
   - Auto-update support via Sparkle
   - Accessibility permission management
   - Instant config reload

### Current Weaknesses

1. **Incomplete Modules**
   - hs.window module commented out (Accessibility challenges)
   - Timer module has commented legacy code

2. **Error Handling**
   - Limited error types (only vmCreation defined)
   - Some silent failures (e.g., missing config file)
   - JS exceptions caught but minimal context

3. **Testing**
   - No obvious test infrastructure visible
   - ContentView contains manual test harness code

4. **Documentation**
   - Minimal API documentation
   - No architecture overview document
   - Missing usage examples

5. **Thread Safety**
   - Limited use of Sendable/explicit concurrency
   - HSApplicationModule marked @MainActor but interaction with JS needs review

6. **Performance Considerations**
   - No lazy-loading for large result sets (e.g., runningApplications())
   - No caching of Application metadata
   - Log array grows unbounded until configured limit

---

## Architectural Improvement Suggestions

### 1. Error Handling & Resilience (High Priority)

**Current Issues:**
- Only 2 error types defined (`HammerspoonError` with `vmCreation` and `unknown`)
- Silent failures (e.g., missing config file in `ManagerManager.swift:21-24`)
- JavaScript exceptions logged but not propagated to users
- No structured error recovery mechanisms

**File References:**
- `Utilities/Exceptions.swift:12-15` - Only 2 error kinds defined
- `Managers/ManagerManager.swift:21-24` - Silent failure on missing config
- `Engine/JSEngine.swift:72-74` - Exception handler only logs errors

**Recommendations:**

```swift
// Expand HammerspoonError with specific error kinds
enum ErrorKind: String {
    case vmCreation = "Creating JS VM"
    case moduleLoadFailed = "Module Loading Failed"
    case configFileNotFound = "Config File Not Found"
    case configFileInvalid = "Config File Invalid"
    case permissionDenied = "Permission Denied"
    case jsEvaluationFailed = "JavaScript Evaluation Failed"
    case moduleShutdownFailed = "Module Shutdown Failed"
    case unknown = "Unknown"
}

// Add Result<T, Error> return types for critical operations
func boot() -> Result<Void, HammerspoonError> {
    // Implementation with proper error propagation
}

// User-facing error notifications
class ErrorPresenter {
    static func presentError(_ error: HammerspoonError,
                           recoveryOptions: [String]? = nil) {
        // Show alert to user with recovery options
    }
}

// Error recovery manager
class ErrorRecoveryManager {
    func attemptRecovery(from error: HammerspoonError) async throws {
        switch error.kind {
        case .configFileNotFound:
            // Attempt to create default config
        case .moduleLoadFailed:
            // Attempt to reload module
        default:
            throw error
        }
    }
}

// JavaScript-side error boundaries
// In engine.js:
class ErrorBoundary {
    static wrap(fn) {
        return function(...args) {
            try {
                return fn.apply(this, args);
            } catch (e) {
                console.error("Error boundary caught:", e);
                // Send to Swift error handler
            }
        };
    }
}
```

**Implementation Steps:**
1. Expand `HammerspoonError.ErrorKind` enum with all error types
2. Update all error-throwing functions to use specific error kinds
3. Replace silent failures with proper error throwing/logging
4. Add user-facing error dialogs with recovery options
5. Implement automatic retry logic for transient failures
6. Add JavaScript error boundary pattern

**Impact:** Better debugging, graceful degradation, improved user experience

---

### 2. Dependency Injection & Testability (High Priority)

**Current Issues:**
- Heavy use of singletons (`JSEngine.shared`, `ManagerManager.shared`, `HammerspoonLog.shared`)
- Hard-coded dependencies make unit testing difficult
- No protocol abstractions for external dependencies (FileManager, NSWorkspace)
- No test infrastructure visible in codebase

**File References:**
- `Engine/JSEngine.swift:13` - Singleton pattern
- `Managers/ManagerManager.swift:13-16` - Hard-coded singleton dependencies
- `Utilities/Logging.swift:64` - Singleton logger

**Recommendations:**

```swift
// 1. Create protocol abstractions
protocol JSEngineProtocol {
    func eval(_ script: String) -> Any?
    func evalFromURL(_ url: URL) throws -> Any?
    subscript(key: String) -> Any? { get set }
    func resetContext() throws
}

protocol SettingsManagerProtocol {
    var configLocation: URL { get set }
    var consoleHistoryLength: Int { get set }
}

protocol FileSystemProtocol {
    func fileExists(atPath path: String) -> Bool
    func contentsOf(url: URL) throws -> String
}

// 2. Inject dependencies instead of using .shared
class ManagerManager {
    let engine: JSEngineProtocol
    let settings: SettingsManagerProtocol
    let fileSystem: FileSystemProtocol

    init(engine: JSEngineProtocol,
         settings: SettingsManagerProtocol,
         fileSystem: FileSystemProtocol = FileManager.default) {
        self.engine = engine
        self.settings = settings
        self.fileSystem = fileSystem
    }

    func boot() throws {
        try engine.resetContext()

        guard fileSystem.fileExists(atPath: settings.configLocation.path) else {
            throw HammerspoonError(.configFileNotFound,
                                  msg: settings.configLocation.path)
        }

        try engine.evalFromURL(settings.configLocation)
    }
}

// 3. Make JSEngine conform to protocol
extension JSEngine: JSEngineProtocol {
    // Implementation already exists
}

// 4. Create mock implementations for testing
class MockJSEngine: JSEngineProtocol {
    var evalCalls: [(script: String, result: Any?)] = []

    func eval(_ script: String) -> Any? {
        let result = "mock result"
        evalCalls.append((script, result))
        return result
    }

    // ... other mock implementations
}

class MockFileSystem: FileSystemProtocol {
    var existingFiles: Set<String> = []

    func fileExists(atPath path: String) -> Bool {
        return existingFiles.contains(path)
    }
}

// 5. Create test infrastructure
// Tests/ManagerManagerTests.swift
import XCTest
@testable import Hammerspoon_2

class ManagerManagerTests: XCTestCase {
    func testBootWithMissingConfigFile() throws {
        let mockEngine = MockJSEngine()
        let mockSettings = MockSettingsManager()
        let mockFileSystem = MockFileSystem()

        let manager = ManagerManager(
            engine: mockEngine,
            settings: mockSettings,
            fileSystem: mockFileSystem
        )

        XCTAssertThrowsError(try manager.boot()) { error in
            guard let hsError = error as? HammerspoonError else {
                XCTFail("Expected HammerspoonError")
                return
            }
            XCTAssertEqual(hsError.kind, .configFileNotFound)
        }
    }

    func testBootWithValidConfig() throws {
        let mockEngine = MockJSEngine()
        let mockSettings = MockSettingsManager()
        let mockFileSystem = MockFileSystem()
        mockFileSystem.existingFiles.insert("/path/to/init.js")
        mockSettings.configLocation = URL(fileURLWithPath: "/path/to/init.js")

        let manager = ManagerManager(
            engine: mockEngine,
            settings: mockSettings,
            fileSystem: mockFileSystem
        )

        XCTAssertNoThrow(try manager.boot())
        XCTAssertEqual(mockEngine.evalFromURLCalls.count, 1)
    }
}
```

**Implementation Steps:**
1. Create protocol abstractions for all external dependencies
2. Refactor singletons to support dependency injection
3. Update initialization code to inject dependencies
4. Create `Tests/` directory with XCTest targets
5. Add mock implementations for all protocols
6. Write unit tests for critical functionality
7. Add integration tests for JS ↔ Swift bridge
8. Consider SwiftUI previews for UI components

**Directory Structure for Tests:**
```
Tests/
├── Hammerspoon2Tests/
│   ├── EngineTests/
│   │   ├── JSEngineTests.swift
│   │   └── ModuleRootTests.swift
│   ├── ManagerTests/
│   │   ├── ManagerManagerTests.swift
│   │   └── SettingsManagerTests.swift
│   ├── ModuleTests/
│   │   ├── ApplicationModuleTests.swift
│   │   └── TimerModuleTests.swift
│   └── Mocks/
│       ├── MockJSEngine.swift
│       ├── MockFileSystem.swift
│       └── MockNSWorkspace.swift
└── IntegrationTests/
    ├── JSBridgeTests.swift
    └── EndToEndTests.swift
```

**Impact:** Enables unit testing, easier to refactor, better code quality, fewer regressions

---

### 3. Thread Safety & Concurrency (High Priority)

**Current Issues:**
- `HSApplicationModule` marked `@MainActor` but receives callbacks from NSWorkspace notifications
- JavaScript evaluation happens on various threads
- `HammerspoonLog` uses `Task { @MainActor in ... }` but could cause race conditions
- No clear threading model documented

**File References:**
- `Modules/hs.application/ApplicationModule.swift:71` - `@MainActor` annotation
- `Modules/hs.application/ApplicationModule.swift:64-67` - Notification callback
- `Utilities/Logging.swift:83-85` - Async logging without proper synchronization
- `Engine/JSEngine.swift:30-32` - eval() has no thread safety

**Recommendations:**

```swift
// 1. Define explicit threading model in documentation
/*
 Threading Model:

 - JavaScript Engine: Dedicated serial queue (jsEngineQueue)
   All JS evaluation must happen on this queue

 - UI Updates: @MainActor
   All SwiftUI state updates must be on main thread

 - Module Operations: Document per-module
   Most modules should be @MainActor unless doing heavy work

 - Callbacks: Always specify dispatch queue
   NSWorkspace callbacks should dispatch to appropriate queue
 */

// 2. Make JSEngine thread-safe with actor
@globalActor
actor JSEngineActor {
    static let shared = JSEngineActor()
}

actor JSEngine {
    static let shared = JSEngine()

    private var id = UUID()
    private var vm: JSVirtualMachine?
    private var context: JSContext?

    // All operations are now isolated to this actor
    func eval(_ script: String) -> Any? {
        return context?.evaluateScript(script)?.toObject()
    }

    func evalFromURL(_ url: URL) async throws -> Any? {
        let script = try String(contentsOf: url, encoding: .utf8)
        return eval(script)
    }

    subscript(key: String) -> Any? {
        get {
            context?.objectForKeyedSubscript(key as (NSCopying & NSObjectProtocol))
        }
        set {
            context?.setObject(newValue, forKeyedSubscript: key as (NSCopying & NSObjectProtocol))
        }
    }
}

// 3. Fix HammerspoonLog thread safety
@MainActor
@Observable
final class HammerspoonLog {
    static let shared = HammerspoonLog()

    private var entries: [HammerspoonLogEntry] = []
    private let maxEntries: Int = 100

    // This is already @MainActor so it's safe
    func log(_ level: HammerspoonLogType, _ msg: String) {
        entries.append(HammerspoonLogEntry(logType: level, msg: msg))
        if entries.count > maxEntries {
            entries.removeFirst()
        }
    }
}

// The global functions properly dispatch to main actor
func AKLog(_ level: HammerspoonLogType, _ msg: String) {
    Task { @MainActor in
        HammerspoonLog.shared.log(level, msg)
    }
}

// 4. Fix HSApplicationModule callback threading
@MainActor
class HSApplicationModule: NSObject, HSModuleAPI, HSApplicationsAPI {
    // ...

    @objc(_addWatcher::) func _addWatcher(eventName: String, callback: JSValue) {
        guard let event = eventNameToEvent(eventName: eventName) else {
            return
        }

        let watcherObject = HSApplicationWatcherObject(
            eventName: eventName,
            callback: callback,
            callbackQueue: .main  // Specify callback queue
        )

        // Observe on background queue, callback on main
        NotificationCenter.default.addObserver(
            forName: event,
            object: nil,
            queue: .main  // Ensure callback on main queue
        ) { [weak watcherObject] notification in
            watcherObject?.handleEvent(notification: notification)
        }

        watchers[event] = watcherObject
    }
}

class HSApplicationWatcherObject {
    let eventName: String
    let callback: JSValue
    let callbackQueue: DispatchQueue

    init(eventName: String, callback: JSValue, callbackQueue: DispatchQueue) {
        self.eventName = eventName
        self.callback = callback
        self.callbackQueue = callbackQueue
    }

    @MainActor
    func handleEvent(notification: NSNotification) {
        let eventApp = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.asHSApplication()

        // Call JavaScript on JSEngine's queue
        Task {
            await withCheckedContinuation { continuation in
                callback.call(withArguments: [eventName, eventApp as Any])
                continuation.resume()
            }
        }
    }
}

// 5. Use async/await for module operations
protocol HSModuleAPI: JSExport {
    var name: String { get }
    init()
    func startup() async throws  // New async startup
    func shutdown() async throws  // Make shutdown async
}

// 6. Document threading in module implementations
/// Module for interacting with applications
///
/// Thread Safety: All methods are @MainActor isolated.
/// Callbacks are dispatched to the main queue.
@MainActor
@objc class HSApplicationModule: NSObject, HSModuleAPI, HSApplicationsAPI {
    // Implementation
}
```

**Implementation Steps:**
1. Document threading model in Architecture.md
2. Convert JSEngine to actor for thread safety
3. Audit all shared state for race conditions
4. Add proper queue specifications for all callbacks
5. Convert blocking operations to async/await
6. Add thread safety annotations (@MainActor, @Sendable)
7. Test with Thread Sanitizer enabled
8. Document threading requirements in each module

**Testing:**
```bash
# Enable Thread Sanitizer in Xcode scheme
# Product > Scheme > Edit Scheme > Diagnostics > Thread Sanitizer
```

**Impact:** Prevents race conditions, crashes, and undefined behavior. Makes code safer and more predictable.

---

### 4. Module System Enhancements (Medium Priority)

**Current Issues:**
- No dependency management between modules
- No versioning or compatibility checks
- Module loading is synchronous (could block on large files)
- No way to dynamically load/unload modules at runtime
- No hot-reloading for module development

**File References:**
- `Engine/ModuleRoot.swift:30-44` - getOrCreate() implementation
- `Engine/HSModuleAPI.swift:12-16` - Basic module protocol

**Recommendations:**

```swift
// 1. Enhanced module protocol
@objc protocol HSModuleAPI: JSExport {
    var name: String { get }
    var version: String { get }  // NEW: Semantic version
    var dependencies: [String] { get }  // NEW: Module dependencies
    var author: String? { get }  // NEW: Module author
    var description: String? { get }  // NEW: Module description

    init()
    func startup() async throws  // NEW: Async initialization
    func shutdown() async throws  // Make shutdown async
    func reload() async throws  // NEW: Hot reload support
}

// 2. Module metadata
struct ModuleMetadata: Codable {
    let name: String
    let version: String
    let dependencies: [Dependency]
    let author: String?
    let description: String?
    let minimumHammerspoonVersion: String?

    struct Dependency: Codable {
        let name: String
        let version: String  // Semantic version constraint
    }
}

// 3. Module registry
actor ModuleRegistry {
    private var modules: [String: any HSModuleAPI] = [:]
    private var metadata: [String: ModuleMetadata] = [:]
    private var loadOrder: [String] = []

    func register(
        module: any HSModuleAPI.Type,
        metadata: ModuleMetadata
    ) throws {
        // Validate version compatibility
        try validateVersion(metadata)

        // Check dependencies
        try validateDependencies(metadata)

        // Store metadata
        self.metadata[metadata.name] = metadata
    }

    func load(name: String) async throws -> any HSModuleAPI {
        // Check if already loaded
        if let module = modules[name] {
            return module
        }

        // Check metadata exists
        guard let meta = metadata[name] else {
            throw HammerspoonError(.moduleLoadFailed,
                                  msg: "Module \(name) not registered")
        }

        // Load dependencies first
        for dep in meta.dependencies {
            _ = try await load(name: dep.name)
        }

        // Create module instance
        guard let moduleType = lookupModuleType(name) else {
            throw HammerspoonError(.moduleLoadFailed,
                                  msg: "Module type not found: \(name)")
        }

        let module = moduleType.init()

        // Load companion JS file if exists
        if let moduleJS = Bundle.main.url(forResource: "hs.\(name)",
                                          withExtension: "js") {
            try await JSEngine.shared.evalFromURL(moduleJS)
        }

        // Startup module
        try await module.startup()

        // Cache and track load order
        modules[name] = module
        loadOrder.append(name)

        AKInfo("Loaded module: \(name) v\(meta.version)")
        return module
    }

    func unload(name: String) async throws {
        guard let module = modules[name] else {
            return
        }

        // Check if other modules depend on this one
        let dependents = findDependents(of: name)
        if !dependents.isEmpty {
            throw HammerspoonError(.moduleShutdownFailed,
                msg: "Module \(name) is required by: \(dependents.joined(separator: ", "))")
        }

        // Shutdown module
        try await module.shutdown()

        // Remove from registry
        modules.removeValue(forKey: name)
        loadOrder.removeAll { $0 == name }

        AKInfo("Unloaded module: \(name)")
    }

    func reload(name: String) async throws {
        // Unload and reload
        try await unload(name: name)
        _ = try await load(name: name)
    }

    func listLoaded() -> [String] {
        return loadOrder
    }

    private func validateDependencies(_ meta: ModuleMetadata) throws {
        for dep in meta.dependencies {
            guard metadata[dep.name] != nil else {
                throw HammerspoonError(.moduleLoadFailed,
                    msg: "Missing dependency: \(dep.name)")
            }

            // TODO: Validate version constraints
        }
    }

    private func findDependents(of moduleName: String) -> [String] {
        return metadata.values
            .filter { meta in
                meta.dependencies.contains { $0.name == moduleName }
            }
            .map { $0.name }
    }
}

// 4. Update ModuleRoot to use registry
@objc class ModuleRoot: NSObject, ModuleRootAPI {
    private let registry = ModuleRegistry()

    override init() {
        super.init()
        registerBuiltInModules()
    }

    private func registerBuiltInModules() {
        try? registry.register(
            module: HSAppInfo.self,
            metadata: ModuleMetadata(
                name: "appInfo",
                version: "1.0.0",
                dependencies: [],
                author: "Hammerspoon Team",
                description: "Application information"
            )
        )

        try? registry.register(
            module: HSApplicationModule.self,
            metadata: ModuleMetadata(
                name: "application",
                version: "1.0.0",
                dependencies: [],
                author: "Hammerspoon Team",
                description: "Application control and monitoring"
            )
        )

        // ... register other modules
    }

    @objc var application: HSApplicationModule {
        get {
            // Synchronous wrapper around async load
            let semaphore = DispatchSemaphore(value: 0)
            var result: HSApplicationModule!

            Task {
                result = try? await registry.load(name: "application") as? HSApplicationModule
                semaphore.signal()
            }

            semaphore.wait()
            return result
        }
    }

    // Async version for better performance
    func loadModule<T: HSModuleAPI>(_ name: String) async throws -> T {
        return try await registry.load(name: name) as! T
    }
}

// 5. Module configuration
struct ModuleConfig: Codable {
    let enabled: [String]  // Modules to auto-load
    let disabled: [String]  // Modules to never load
    let settings: [String: [String: Any]]  // Per-module settings
}

// 6. External module support (future enhancement)
class ExternalModuleLoader {
    func loadFromPath(_ path: String) async throws -> ModuleMetadata {
        // Load module from external path
        // Support .hammerspoon2module bundles
        // Verify code signatures
        // Load into isolated context
    }
}
```

**Implementation Steps:**
1. Extend `HSModuleAPI` with new properties
2. Create `ModuleRegistry` actor
3. Add module metadata definitions
4. Implement dependency resolution
5. Add async loading support
6. Implement hot-reloading
7. Create module configuration system
8. Document module development process

**Impact:** Better extensibility, developer experience, runtime flexibility, and module ecosystem support

---

### 5. Configuration Management (Medium Priority)

**Current Issues:**
- Settings limited to just config file path and console history
- No validation of user configuration
- No schema or type checking for settings
- No way to persist module-specific settings
- Hard-coded values (e.g., log limit of 100 in `Logging.swift:71`)

**File References:**
- `Managers/SettingsManager.swift` - Limited settings
- `Utilities/Logging.swift:71` - Hard-coded log limit
- `Windows/ConsoleView.swift` - Hard-coded UI settings

**Recommendations:**

```swift
// 1. Comprehensive settings structure
struct HammerspoonSettings: Codable {
    var general: GeneralSettings = GeneralSettings()
    var console: ConsoleSettings = ConsoleSettings()
    var logging: LoggingSettings = LoggingSettings()
    var updates: UpdateSettings = UpdateSettings()
    var modules: [String: ModuleSettings] = [:]

    struct GeneralSettings: Codable {
        var configLocation: URL = defaultConfigLocation()
        var autoReloadConfig: Bool = true
        var showDockIcon: Bool = false
        var showMenuBarIcon: Bool = true
        var launchAtLogin: Bool = false
    }

    struct ConsoleSettings: Codable {
        var historyLength: Int = 100
        var fontSize: Int = 12
        var fontFamily: String = "SF Mono"
        var theme: String = "system"  // "light", "dark", "system"
        var showTimestamps: Bool = true
        var autoScroll: Bool = true
        var maxOutputLength: Int = 10000
    }

    struct LoggingSettings: Codable {
        var maxEntries: Int = 100
        var level: LogLevel = .info
        var enableFileLogging: Bool = false
        var logFilePath: URL? = nil
        var rotateLogFiles: Bool = true
        var maxLogFileSize: Int = 10_485_760  // 10 MB
        var maxLogFiles: Int = 5
    }

    struct UpdateSettings: Codable {
        var checkForUpdates: Bool = true
        var automaticallyInstall: Bool = false
        var checkInterval: TimeInterval = 86400  // 24 hours
        var channel: String = "stable"  // "stable", "beta", "nightly"
    }

    struct ModuleSettings: Codable {
        var enabled: Bool = true
        var settings: [String: AnyCodable] = [:]
    }

    enum LogLevel: String, Codable {
        case trace, info, warning, error
    }
}

// 2. Settings manager with validation
@MainActor
@Observable
class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let settingsKey = "hammerspoon.settings"

    var settings: HammerspoonSettings {
        didSet {
            save()
            notifyObservers()
        }
    }

    private init() {
        // Load from UserDefaults or use default
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(HammerspoonSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = HammerspoonSettings()
        }

        // Validate loaded settings
        validateAndMigrate()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: settingsKey)
        } catch {
            AKError("Failed to save settings: \(error)")
        }
    }

    func reset() {
        settings = HammerspoonSettings()
        save()
    }

    private func validateAndMigrate() {
        // Validate settings values
        if settings.console.historyLength < 10 {
            settings.console.historyLength = 10
        }
        if settings.console.historyLength > 10000 {
            settings.console.historyLength = 10000
        }

        // Migrate old settings if needed
        migrateFromLegacySettings()

        save()
    }

    private func migrateFromLegacySettings() {
        // Migrate from old UserDefaults keys
        if let oldConfigPath = defaults.string(forKey: "configLocation") {
            settings.general.configLocation = URL(fileURLWithPath: oldConfigPath)
            defaults.removeObject(forKey: "configLocation")
        }
    }

    private func notifyObservers() {
        NotificationCenter.default.post(
            name: .settingsDidChange,
            object: self
        )
    }
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

// 3. Settings validation
struct SettingsValidator {
    static func validate(_ settings: HammerspoonSettings) throws {
        // Validate console settings
        guard (10...10000).contains(settings.console.historyLength) else {
            throw HammerspoonError(.unknown,
                msg: "Console history must be between 10 and 10000")
        }

        guard (8...72).contains(settings.console.fontSize) else {
            throw HammerspoonError(.unknown,
                msg: "Font size must be between 8 and 72")
        }

        // Validate logging settings
        guard settings.logging.maxLogFileSize > 0 else {
            throw HammerspoonError(.unknown,
                msg: "Log file size must be positive")
        }

        // Validate config file exists
        if !FileManager.default.fileExists(atPath: settings.general.configLocation.path) {
            AKWarning("Config file does not exist: \(settings.general.configLocation.path)")
        }
    }
}

// 4. Settings UI improvements
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ConsoleSettingsView()
                .tabItem {
                    Label("Console", systemImage: "terminal")
                }

            LoggingSettingsView()
                .tabItem {
                    Label("Logging", systemImage: "doc.text")
                }

            ModulesSettingsView()
                .tabItem {
                    Label("Modules", systemImage: "puzzlepiece")
                }

            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.down.circle")
                }
        }
    }
}

// 5. Module-specific settings
extension HSModuleAPI {
    var settingsSchema: [String: SettingDefinition] { [:] }

    func validateSettings(_ settings: [String: Any]) throws {
        // Override in module to validate settings
    }
}

struct SettingDefinition {
    let key: String
    let type: SettingType
    let defaultValue: Any
    let description: String
    let validator: ((Any) -> Bool)?

    enum SettingType {
        case bool, int, double, string, url, array, dictionary
    }
}

// Example module with settings
extension HSTimer {
    override var settingsSchema: [String: SettingDefinition] {
        [
            "maxConcurrentTimers": SettingDefinition(
                key: "maxConcurrentTimers",
                type: .int,
                defaultValue: 100,
                description: "Maximum number of concurrent timers",
                validator: { value in
                    guard let intValue = value as? Int else { return false }
                    return intValue > 0 && intValue <= 1000
                }
            )
        ]
    }
}

// 6. Export/Import settings
extension SettingsManager {
    func export(to url: URL) throws {
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url)
    }

    func `import`(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder().decode(HammerspoonSettings.self, from: data)
        try SettingsValidator.validate(imported)
        self.settings = imported
    }
}

// 7. Environment variable support
extension SettingsManager {
    func loadFromEnvironment() {
        let env = ProcessInfo.processInfo.environment

        if let configPath = env["HAMMERSPOON_CONFIG"] {
            settings.general.configLocation = URL(fileURLWithPath: configPath)
        }

        if let logLevel = env["HAMMERSPOON_LOG_LEVEL"],
           let level = HammerspoonSettings.LogLevel(rawValue: logLevel) {
            settings.logging.level = level
        }
    }
}

// Helper for Codable Any
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    // Codable implementation...
}
```

**Implementation Steps:**
1. Create `HammerspoonSettings` struct with all settings
2. Update `SettingsManager` to use new structure
3. Implement validation and migration
4. Create comprehensive Settings UI
5. Add module-specific settings support
6. Implement export/import functionality
7. Add environment variable support
8. Update all hard-coded values to use settings

**Impact:** More configurable, user-friendly, maintainable, and professional

---

### 6. Logging Architecture Improvements (Medium Priority)

**Current Issues:**
- Fixed limit of 100 log entries (`Logging.swift:71`)
- No log level filtering (all logs stored equally)
- No structured logging (just strings)
- No log rotation or persistence
- Performance impact of storing all logs in memory

**File References:**
- `Utilities/Logging.swift:68-74` - Log storage implementation
- `Utilities/Logging.swift:82-116` - Logging functions

**Recommendations:**

```swift
// 1. Enhanced log entry with metadata
struct HammerspoonLogEntry: Identifiable, Equatable, Hashable {
    let id = UUID()
    let date = Date()
    let logType: HammerspoonLogType
    let msg: String
    let metadata: [String: String]  // NEW: Structured metadata
    let source: SourceLocation?  // NEW: Source file/line
    let correlationID: UUID?  // NEW: For tracking related events

    struct SourceLocation: Equatable, Hashable {
        let file: String
        let line: Int
        let function: String
    }
}

// 2. Log level filtering
enum HammerspoonLogType: Int, CaseIterable, Comparable {
    case trace = 0
    case info = 1
    case warning = 2
    case error = 3
    case console = 4

    static func < (lhs: HammerspoonLogType, rhs: HammerspoonLogType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// 3. Enhanced logging system
@MainActor
@Observable
final class HammerspoonLog {
    static let shared = HammerspoonLog()

    private var entries: [HammerspoonLogEntry] = []
    private var settings: HammerspoonSettings.LoggingSettings
    private var fileLogger: FileLogger?

    var filteredEntries: [HammerspoonLogEntry] {
        entries.filter { $0.logType >= settings.level }
    }

    init() {
        self.settings = SettingsManager.shared.settings.logging

        if settings.enableFileLogging {
            self.fileLogger = FileLogger(settings: settings)
        }

        // Observe settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .settingsDidChange,
            object: nil
        )
    }

    func log(
        _ level: HammerspoonLogType,
        _ msg: String,
        metadata: [String: String] = [:],
        source: HammerspoonLogEntry.SourceLocation? = nil,
        correlationID: UUID? = nil
    ) {
        // Check if we should log this level
        guard level >= settings.level else { return }

        let entry = HammerspoonLogEntry(
            logType: level,
            msg: msg,
            metadata: metadata,
            source: source,
            correlationID: correlationID
        )

        entries.append(entry)

        // Trim to max entries
        if entries.count > settings.maxEntries {
            entries.removeFirst()
        }

        // Log to file if enabled
        fileLogger?.write(entry)
    }

    func clearLog() {
        entries.removeAll()
    }

    func export() -> String {
        entries.map { entry in
            let timestamp = entry.date.ISO8601Format()
            let level = entry.logType.asString
            var line = "[\(timestamp)] [\(level)] \(entry.msg)"

            if !entry.metadata.isEmpty {
                line += " \(entry.metadata)"
            }

            if let source = entry.source {
                line += " (\(source.file):\(source.line))"
            }

            return line
        }.joined(separator: "\n")
    }

    @objc private func settingsDidChange() {
        self.settings = SettingsManager.shared.settings.logging

        // Update file logger
        if settings.enableFileLogging && fileLogger == nil {
            fileLogger = FileLogger(settings: settings)
        } else if !settings.enableFileLogging {
            fileLogger = nil
        }
    }
}

// 4. File logging with rotation
class FileLogger {
    private let settings: HammerspoonSettings.LoggingSettings
    private let fileHandle: FileHandle
    private var currentSize: Int = 0
    private let queue = DispatchQueue(label: "com.hammerspoon.filelogger")

    init(settings: HammerspoonSettings.LoggingSettings) {
        self.settings = settings

        let logPath = settings.logFilePath ?? Self.defaultLogPath()

        // Create log directory if needed
        try? FileManager.default.createDirectory(
            at: logPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Open or create log file
        if !FileManager.default.fileExists(atPath: logPath.path) {
            FileManager.default.createFile(atPath: logPath.path, contents: nil)
        }

        self.fileHandle = try! FileHandle(forWritingTo: logPath)
        self.currentSize = try! FileManager.default.attributesOfItem(atPath: logPath.path)[.size] as! Int

        fileHandle.seekToEndOfFile()
    }

    func write(_ entry: HammerspoonLogEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = entry.date.ISO8601Format()
            let level = entry.logType.asString
            let line = "[\(timestamp)] [\(level)] \(entry.msg)\n"

            if let data = line.data(using: .utf8) {
                self.fileHandle.write(data)
                self.currentSize += data.count

                // Check if rotation is needed
                if self.settings.rotateLogFiles && self.currentSize > self.settings.maxLogFileSize {
                    self.rotate()
                }
            }
        }
    }

    private func rotate() {
        let logPath = settings.logFilePath ?? Self.defaultLogPath()

        // Close current file
        try? fileHandle.close()

        // Rotate existing log files
        for i in (1..<settings.maxLogFiles).reversed() {
            let oldPath = logPath.appendingPathExtension(".\(i)")
            let newPath = logPath.appendingPathExtension(".\(i + 1)")
            try? FileManager.default.moveItem(at: oldPath, to: newPath)
        }

        // Move current log to .1
        let firstRotated = logPath.appendingPathExtension(".1")
        try? FileManager.default.moveItem(at: logPath, to: firstRotated)

        // Create new log file
        FileManager.default.createFile(atPath: logPath.path, contents: nil)
        // Reopen file handle would happen here in real implementation
    }

    static func defaultLogPath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Hammerspoon 2")
            .appendingPathComponent("hammerspoon.log")
    }
}

// 5. Enhanced logging functions with source location
func AKLog(
    _ level: HammerspoonLogType,
    _ msg: String,
    metadata: [String: String] = [:],
    file: String = #file,
    line: Int = #line,
    function: String = #function
) {
    let source = HammerspoonLogEntry.SourceLocation(
        file: URL(fileURLWithPath: file).lastPathComponent,
        line: line,
        function: function
    )

    // Log to system logger
    switch level {
    case .trace:
        Logger.Hammerspoon.debug("\(msg)")
    case .info:
        Logger.Hammerspoon.info("\(msg)")
    case .warning:
        Logger.Hammerspoon.warning("\(msg)")
    case .error:
        Logger.Hammerspoon.error("\(msg)")
    case .console:
        Logger.Hammerspoon.info("JS: \(msg)")
    }

    // Log to our storage
    Task { @MainActor in
        HammerspoonLog.shared.log(level, msg, metadata: metadata, source: source)
    }
}

func AKInfo(
    _ msg: String,
    metadata: [String: String] = [:],
    file: String = #file,
    line: Int = #line,
    function: String = #function
) {
    AKLog(.info, msg, metadata: metadata, file: file, line: line, function: function)
}

// And similar for AKWarning, AKError, AKTrace, AKConsole...

// 6. Structured logging helpers
extension HammerspoonLog {
    func logModuleEvent(
        _ module: String,
        event: String,
        details: [String: String] = [:],
        level: HammerspoonLogType = .info
    ) {
        var metadata = details
        metadata["module"] = module
        metadata["event"] = event

        log(level, "[\(module)] \(event)", metadata: metadata)
    }

    func logPerformance(
        _ operation: String,
        duration: TimeInterval,
        metadata: [String: String] = [:]
    ) {
        var meta = metadata
        meta["operation"] = operation
        meta["duration"] = String(format: "%.2fms", duration * 1000)

        log(.trace, "Performance: \(operation) took \(String(format: "%.2fms", duration * 1000))",
            metadata: meta)
    }
}

// 7. Performance measurement helper
func measure<T>(_ name: String, block: () throws -> T) rethrows -> T {
    let start = Date()
    defer {
        let duration = Date().timeIntervalSince(start)
        HammerspoonLog.shared.logPerformance(name, duration: duration)
    }
    return try block()
}

// 8. Correlation ID for tracking related events
class CorrelationContext {
    static var current: UUID?

    static func withCorrelation<T>(_ block: () throws -> T) rethrows -> T {
        let id = UUID()
        current = id
        defer { current = nil }
        return try block()
    }
}

// Usage:
CorrelationContext.withCorrelation {
    AKInfo("Starting config load")
    // ... do work ...
    AKInfo("Config loaded")
}
// Both logs will have the same correlation ID
```

**Implementation Steps:**
1. Enhance `HammerspoonLogEntry` with metadata
2. Add log level filtering
3. Implement file logging with rotation
4. Add structured logging helpers
5. Update all logging call sites
6. Add log export functionality
7. Create log viewer UI improvements
8. Add performance measurement utilities

**Impact:** Better debugging, performance monitoring, and operational visibility

---

### 7. JavaScript Bridge Safety (High Priority)

**Current Issues:**
- Direct Swift object exposure to JavaScript
- No validation of JS callback signatures
- Potential memory leaks (JSValue callbacks retained)
- No sandboxing or security boundaries
- No timeout protection for long-running callbacks

**File References:**
- `Engine/JSEngine.swift:30-32` - Direct eval exposure
- `Modules/hs.application/ApplicationModule.swift:140-161` - Callback storage

**Recommendations:**

```swift
// 1. Callback validation
class JSCallbackValidator {
    static func validate(
        _ callback: JSValue,
        expectedArgs: Int? = nil,
        timeout: TimeInterval = 5.0
    ) throws {
        guard !callback.isUndefined && !callback.isNull else {
            throw HammerspoonError(.jsEvaluationFailed,
                                  msg: "Callback is undefined or null")
        }

        guard callback.isObject else {
            throw HammerspoonError(.jsEvaluationFailed,
                                  msg: "Callback is not an object")
        }

        // Check if it's callable (has 'call' property or is function)
        if !callback.hasProperty("call") {
            throw HammerspoonError(.jsEvaluationFailed,
                                  msg: "Callback is not callable")
        }

        // Validate argument count if specified
        if let expected = expectedArgs {
            if let length = callback.forProperty("length")?.toInt32(),
               Int(length) != expected {
                AKWarning("Callback expects \(length) args, but will receive \(expected)")
            }
        }
    }
}

// 2. Safe callback wrapper with timeout
class SafeJSCallback {
    private let callback: JSValue
    private let timeout: TimeInterval
    private let name: String

    init(callback: JSValue, timeout: TimeInterval = 5.0, name: String = "callback") throws {
        try JSCallbackValidator.validate(callback)
        self.callback = callback
        self.timeout = timeout
        self.name = name
    }

    func call(withArguments args: [Any]) -> JSValue? {
        let context = callback.context

        // Set up timeout watchdog
        var didTimeout = false
        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            didTimeout = true
            AKError("Callback '\(self.name)' timed out after \(self.timeout)s")
        }

        // Call the callback
        let result = callback.call(withArguments: args)

        timer.invalidate()

        if didTimeout {
            // Timeout occurred, return undefined
            return JSValue(undefinedIn: context)
        }

        return result
    }
}

// 3. Memory-safe callback storage using JSManagedValue
class HSApplicationWatcherObject {
    let eventName: String
    private let managedCallback: JSManagedValue
    private weak var context: JSContext?

    init(eventName: String, callback: JSValue, context: JSContext) throws {
        try JSCallbackValidator.validate(callback)

        self.eventName = eventName
        self.context = context

        // Use JSManagedValue to prevent memory leaks
        guard let managed = JSManagedValue(value: callback) else {
            throw HammerspoonError(.jsEvaluationFailed,
                                  msg: "Failed to create managed callback")
        }

        self.managedCallback = managed

        // Add to VM's memory management
        context.virtualMachine?.addManagedReference(managed, withOwner: self)
    }

    @MainActor
    func handleEvent(notification: NSNotification) {
        guard let callback = managedCallback.value,
              let context = context else {
            AKWarning("Callback or context no longer available")
            return
        }

        let eventApp = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.asHSApplication()

        // Use safe callback wrapper
        do {
            let safeCallback = try SafeJSCallback(
                callback: callback,
                timeout: 5.0,
                name: "application.\(eventName)"
            )
            _ = safeCallback.call(withArguments: [eventName, eventApp as Any])
        } catch {
            AKError("Failed to call callback: \(error)")
        }
    }

    deinit {
        // Clean up managed reference
        context?.virtualMachine?.removeManagedReference(managedCallback, withOwner: self)
    }
}

// 4. Input validation for Swift-to-JS data
class JSValueConverter {
    static func validate(value: Any) throws -> Any {
        switch value {
        case let string as String:
            // Check for excessively long strings
            guard string.count < 1_000_000 else {
                throw HammerspoonError(.jsEvaluationFailed,
                                      msg: "String too long for JS conversion")
            }
            return string

        case let array as [Any]:
            // Recursively validate array elements
            return try array.map { try validate(value: $0) }

        case let dict as [String: Any]:
            // Recursively validate dictionary values
            return try dict.mapValues { try validate(value: $0) }

        case is NSNumber, is Int, is Double, is Bool:
            return value

        case is NSNull:
            return value

        default:
            AKWarning("Unsupported type for JS conversion: \(type(of: value))")
            return NSNull()
        }
    }
}

// 5. Rate limiting for expensive operations
actor RateLimiter {
    private var lastCallTimes: [String: Date] = [:]
    private let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 0.1) {
        self.minimumInterval = minimumInterval
    }

    func checkAllowed(for operation: String) -> Bool {
        let now = Date()

        if let lastCall = lastCallTimes[operation] {
            let elapsed = now.timeIntervalSince(lastCall)
            if elapsed < minimumInterval {
                return false
            }
        }

        lastCallTimes[operation] = now
        return true
    }
}

// Usage in module:
@MainActor
class HSApplicationModule: NSObject, HSModuleAPI, HSApplicationsAPI {
    private let rateLimiter = RateLimiter(minimumInterval: 0.1)

    @objc func runningApplications() -> [HSApplication] {
        // Check rate limit
        Task {
            guard await rateLimiter.checkAllowed(for: "runningApplications") else {
                AKWarning("runningApplications() called too frequently")
                return []
            }
        }

        return NSWorkspace.shared.runningApplications
            .compactMap { $0.asHSApplication() }
    }
}

// 6. Sandboxing for user configuration (future enhancement)
class SandboxedJSContext {
    private let context: JSContext

    init() throws {
        let vm = JSVirtualMachine()
        guard let ctx = JSContext(virtualMachine: vm) else {
            throw HammerspoonError(.vmCreation, msg: "Failed to create sandboxed context")
        }

        self.context = ctx

        // Set up restricted environment
        setupSandbox()
    }

    private func setupSandbox() {
        // Remove dangerous global objects
        context.setObject(nil, forKeyedSubscript: "eval" as NSString)
        context.setObject(nil, forKeyedSubscript: "Function" as NSString)

        // Provide safe console
        injectSafeConsole()

        // Set resource limits
        context.virtualMachine?.addManagedReference(nil, withOwner: self)
    }

    private func injectSafeConsole() {
        // Only allow logging, no eval
        let consoleLog: @convention(block) (String) -> Void = { message in
            AKConsole(message)
        }

        let console = JSValue(newObjectIn: context)!
        console.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }
}

// 7. Error propagation from Swift to JS
extension JSContext {
    func throwError(_ error: HammerspoonError) {
        let errorObject = JSValue(newErrorFromMessage: error.localizedDescription, in: self)
        self.exception = errorObject
    }
}

// Usage:
@objc func someFunction() -> JSValue? {
    guard let context = JSContext.current() else {
        return nil
    }

    do {
        // ... some operation that might fail
        throw HammerspoonError(.permissionDenied, msg: "Accessibility not enabled")
    } catch let error as HammerspoonError {
        context.throwError(error)
        return nil
    } catch {
        context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
        return nil
    }
}

// 8. Audit trail for security-sensitive operations
class SecurityAuditLog {
    static let shared = SecurityAuditLog()

    func logSensitiveOperation(
        _ operation: String,
        module: String,
        parameters: [String: Any] = [:]
    ) {
        let entry = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "operation": operation,
            "module": module,
            "parameters": parameters
        ] as [String: Any]

        AKInfo("Security audit: \(operation)", metadata: [
            "module": module,
            "operation": operation
        ])

        // Could also write to separate audit log file
    }
}

// Usage in sensitive operations:
@objc func execute(_ command: String) -> Bool {
    SecurityAuditLog.shared.logSensitiveOperation(
        "execute_shell_command",
        module: "hs.execute",
        parameters: ["command": command]
    )

    // ... execute command
}
```

**Implementation Steps:**
1. Create `JSCallbackValidator` for callback validation
2. Implement `SafeJSCallback` wrapper with timeout protection
3. Update all callback storage to use `JSManagedValue`
4. Add `JSValueConverter` for input validation
5. Implement rate limiting for expensive operations
6. Add proper error propagation to JavaScript
7. Create security audit logging
8. Consider sandboxing for untrusted code
9. Document security model and best practices

**Impact:** Prevents crashes, memory leaks, security vulnerabilities, and denial-of-service attacks

---

### 8. Documentation & Developer Experience (Medium Priority)

**Current Issues:**
- Minimal API documentation (`JavaScript API.docc` is mostly empty)
- No architectural overview document
- No contribution guidelines
- No module development guide
- No example configurations

**File References:**
- `JavaScript API.docc/JavaScript API.md` - Stub documentation

**Recommendations:**

**1. Documentation Structure:**
```
Hammerspoon2/
├── docs/
│   ├── README.md
│   ├── Architecture.md
│   ├── ModuleDevelopment.md
│   ├── ThreadingModel.md
│   ├── JSBridgeGuide.md
│   ├── Contributing.md
│   ├── Security.md
│   └── Migration.md (from Hammerspoon 1)
│
├── examples/
│   ├── basic/
│   │   ├── init.js (starter config)
│   │   ├── app-launcher.js
│   │   └── timer-example.js
│   ├── intermediate/
│   │   ├── window-management.js
│   │   ├── app-watchers.js
│   │   └── custom-console.js
│   └── advanced/
│       ├── custom-module/
│       │   ├── MyModule.swift
│       │   └── README.md
│       └── complex-automation.js
│
└── JavaScript API.docc/
    ├── JavaScript API.md (overview)
    ├── GettingStarted.tutorial
    ├── Modules/
    │   ├── Application.md
    │   ├── Timer.md
    │   ├── Console.md
    │   └── ...
    └── Articles/
        ├── CreatingModules.md
        ├── Debugging.md
        └── BestPractices.md
```

**2. Architecture Documentation (docs/Architecture.md):**
- Based on this analysis document
- Include diagrams (using Mermaid or similar)
- Document design decisions and rationale
- Explain threading model
- Describe module system
- Document communication patterns

**3. Module Development Guide (docs/ModuleDevelopment.md):**
```markdown
# Module Development Guide

## Creating a New Module

### 1. Define the API Protocol

Create a new file in `Modules/`:

```swift
import Foundation
import JavaScriptCore

/// Module for custom functionality
@objc protocol HSMyModuleAPI: JSExport {
    /// Description of function
    /// - Parameter arg: Description
    /// - Returns: Description
    @objc func myFunction(_ arg: String) -> String
}
```

### 2. Implement the Module

```swift
@MainActor
@objc class HSMyModule: NSObject, HSModuleAPI, HSMyModuleAPI {
    var name = "hs.mymodule"

    required override init() {
        super.init()
    }

    func startup() async throws {
        // Initialize resources
    }

    func shutdown() async throws {
        // Clean up resources
    }

    @objc func myFunction(_ arg: String) -> String {
        return "Hello, \(arg)!"
    }
}
```

### 3. Register the Module

In `ModuleRoot.swift`:

```swift
@objc var mymodule: HSMyModule {
    get { getOrCreate(name: "mymodule", type: HSMyModule.self) }
}
```

### 4. Add JavaScript Enhancement (Optional)

Create `hs.mymodule.js`:

```javascript
// Add convenience methods
hs.mymodule.greet = function(name) {
    return hs.mymodule.myFunction(name);
};
```

### 5. Test the Module

```javascript
// In init.js
console.log(hs.mymodule.greet("World"));
// Output: Hello, World!
```
```

**4. API Documentation (JavaScript API.docc):**

Expand with comprehensive DocC documentation:

```markdown
# ``Hammerspoon2``

JavaScript automation for macOS

## Overview

Hammerspoon 2 allows you to automate your Mac using JavaScript...

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:YourFirstScript>
- <doc:Configuration>

### Core Modules

- ``hs/application``
- ``hs/timer``
- ``hs/console``
- ``hs/permissions``

### Guides

- <doc:CreatingModules>
- <doc:Debugging>
- <doc:BestPractices>
```

**5. Example Configurations:**

Create comprehensive examples in `examples/`:

```javascript
// examples/basic/init.js
// Hammerspoon 2 - Starter Configuration

// Load at startup
console.info("Hammerspoon 2 loading...");

// Simple app launcher
function launchOrFocus(appName) {
    const app = hs.application.matchingName(appName);
    if (app) {
        app.activate();
    } else {
        // Launch app (implementation depends on hs.application API)
        console.info(`Launching ${appName}...`);
    }
}

// Watch for application events
hs.application.addWatcher("didLaunch", (eventName, app) => {
    console.info(`${app.name} launched`);
});

// Auto-reload configuration when changed
hs.timer.doEvery(5, () => {
    // Check if config file changed
    // Reload if needed
});

console.info("Hammerspoon 2 ready!");
```

**6. Contributing Guide (docs/Contributing.md):**

```markdown
# Contributing to Hammerspoon 2

## Development Setup

1. Clone the repository
2. Open `Hammerspoon 2.xcodeproj`
3. Build and run (⌘R)

## Code Style

- Use Swift 5.9+ features
- Follow Swift API Design Guidelines
- Document all public APIs
- Write tests for new features

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Update documentation
6. Submit PR

## Module Development

See [Module Development Guide](ModuleDevelopment.md)
```

**7. Migration Guide (docs/Migration.md):**

```markdown
# Migrating from Hammerspoon 1

## Key Differences

### Language
- **Hammerspoon 1:** Lua
- **Hammerspoon 2:** JavaScript (ES6+)

### Module Names
- Same module structure: `hs.application`, `hs.timer`, etc.

### API Differences

#### Application Module

Hammerspoon 1 (Lua):
```lua
local app = hs.application.get("Safari")
app:activate()
```

Hammerspoon 2 (JavaScript):
```javascript
const app = hs.application.matchingName("Safari");
app.activate();
```

...
```

**8. Interactive Documentation:**

Create a documentation viewer within the app:

```swift
struct DocumentationView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("Getting Started") {
                    MarkdownView(file: "GettingStarted")
                }

                Section("Modules") {
                    NavigationLink("hs.application") {
                        MarkdownView(file: "ApplicationModule")
                    }
                    // ... other modules
                }
            }
        } detail: {
            Text("Select a topic")
        }
    }
}
```

**Implementation Steps:**
1. Create `docs/` directory with architecture documentation
2. Write comprehensive module development guide
3. Expand JavaScript API.docc documentation
4. Create example configurations for all levels
5. Write contribution guidelines
6. Create migration guide from Hammerspoon 1
7. Add in-app documentation viewer
8. Set up documentation website (GitHub Pages)

**Impact:** Easier onboarding, community contributions, better maintenance, professional appearance

---

### 9. Performance & Resource Management (Low-Medium Priority)

**Current Issues:**
- No caching of application objects (`ApplicationModule.swift:91-92`)
- Repeated file system operations
- Module JS files loaded synchronously
- No lazy loading for expensive resources
- No performance monitoring

**File References:**
- `Modules/hs.application/ApplicationModule.swift:90-93` - No caching
- `Engine/ModuleRoot.swift:38-40` - Synchronous JS loading

**Recommendations:**

```swift
// 1. Application object caching
@MainActor
class HSApplicationModule: NSObject, HSModuleAPI, HSApplicationsAPI {
    private var applicationCache: [pid_t: (app: HSApplication, timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 1.0  // Cache for 1 second

    @objc func runningApplications() -> [HSApplication] {
        let now = Date()

        let apps = NSWorkspace.shared.runningApplications.compactMap { nsApp -> HSApplication? in
            let pid = nsApp.processIdentifier

            // Check cache
            if let cached = applicationCache[pid],
               now.timeIntervalSince(cached.timestamp) < cacheTimeout {
                return cached.app
            }

            // Create new and cache
            if let hsApp = nsApp.asHSApplication() {
                applicationCache[pid] = (hsApp, now)
                return hsApp
            }

            return nil
        }

        // Clean up cache for terminated apps
        let currentPIDs = Set(apps.map { $0.pid })
        applicationCache = applicationCache.filter { currentPIDs.contains($0.key) }

        return apps
    }

    // Invalidate cache when apps terminate
    override init() {
        super.init()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.applicationCache.removeValue(forKey: app.processIdentifier)
        }
    }
}

// 2. LRU Cache utility
class LRUCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let value: Value
        var lastAccess: Date
    }

    private var cache: [Key: CacheEntry] = [:]
    private let maxSize: Int

    init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }

    func get(_ key: Key) -> Value? {
        guard var entry = cache[key] else {
            return nil
        }

        entry.lastAccess = Date()
        cache[key] = entry
        return entry.value
    }

    func set(_ key: Key, value: Value) {
        // Remove oldest if at capacity
        if cache.count >= maxSize {
            let oldest = cache.min { $0.value.lastAccess < $1.value.lastAccess }
            if let oldestKey = oldest?.key {
                cache.removeValue(forKey: oldestKey)
            }
        }

        cache[key] = CacheEntry(value: value, lastAccess: Date())
    }

    func clear() {
        cache.removeAll()
    }
}

// 3. Async module loading
class ModuleRoot: NSObject, ModuleRootAPI {
    private let moduleLoadQueue = DispatchQueue(label: "com.hammerspoon.moduleload", attributes: .concurrent)

    private func getOrCreate<T>(name: String, type: T.Type) -> T where T: HSModuleAPI {
        if let result = modules[name] as? T {
            return result
        }

        AKTrace("Loading module: \(name)")
        let module = type.init()
        modules[name] = module

        // Load module JS file asynchronously
        if let moduleJS = Bundle.main.url(forResource: "hs.\(name)", withExtension: "js") {
            moduleLoadQueue.async {
                do {
                    try JSEngine.shared.evalFromURL(moduleJS)
                    AKTrace("Loaded JS for module: \(name)")
                } catch {
                    AKError("Failed to load JS for module \(name): \(error)")
                }
            }
        }

        return module
    }
}

// 4. Parallel module initialization
class ModuleRegistry {
    func loadModules(_ names: [String]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask {
                    _ = try await self.load(name: name)
                }
            }

            try await group.waitForAll()
        }
    }
}

// 5. Resource limits
class ResourceMonitor {
    static let shared = ResourceMonitor()

    private var timerCount = 0
    private var watcherCount = 0

    let maxTimers = 1000
    let maxWatchers = 100

    func allocateTimer() throws {
        guard timerCount < maxTimers else {
            throw HammerspoonError(.unknown,
                                  msg: "Maximum timer count (\(maxTimers)) exceeded")
        }
        timerCount += 1
    }

    func deallocateTimer() {
        timerCount = max(0, timerCount - 1)
    }

    func allocateWatcher() throws {
        guard watcherCount < maxWatchers else {
            throw HammerspoonError(.unknown,
                                  msg: "Maximum watcher count (\(maxWatchers)) exceeded")
        }
        watcherCount += 1
    }

    func deallocateWatcher() {
        watcherCount = max(0, watcherCount - 1)
    }

    func getStats() -> [String: Int] {
        return [
            "timers": timerCount,
            "watchers": watcherCount
        ]
    }
}

// Usage in Timer module:
@objc func doAfter(_ interval: TimeInterval, callback: JSValue) -> HSTimerObject? {
    do {
        try ResourceMonitor.shared.allocateTimer()
    } catch {
        AKError("Failed to create timer: \(error)")
        return nil
    }

    // ... create timer
}

// 6. Memory usage monitoring
class MemoryMonitor {
    static let shared = MemoryMonitor()

    func getCurrentUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    func startMonitoring(interval: TimeInterval = 60.0, threshold: UInt64 = 500_000_000) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let usage = self.getCurrentUsage()
            let usageMB = Double(usage) / 1_000_000

            AKTrace("Memory usage: \(String(format: "%.2f", usageMB)) MB")

            if usage > threshold {
                AKWarning("High memory usage: \(String(format: "%.2f", usageMB)) MB")
            }
        }
    }
}

// 7. Performance profiling
class PerformanceProfiler {
    static let shared = PerformanceProfiler()

    private var measurements: [String: [TimeInterval]] = [:]

    func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let start = Date()
        defer {
            let duration = Date().timeIntervalSince(start)
            recordMeasurement(name, duration: duration)
        }
        return try operation()
    }

    func measure<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let start = Date()
        defer {
            let duration = Date().timeIntervalSince(start)
            recordMeasurement(name, duration: duration)
        }
        return try await operation()
    }

    private func recordMeasurement(_ name: String, duration: TimeInterval) {
        if measurements[name] == nil {
            measurements[name] = []
        }
        measurements[name]?.append(duration)

        // Keep only last 100 measurements
        if let count = measurements[name]?.count, count > 100 {
            measurements[name]?.removeFirst()
        }
    }

    func getStats(for name: String) -> (avg: TimeInterval, min: TimeInterval, max: TimeInterval)? {
        guard let durations = measurements[name], !durations.isEmpty else {
            return nil
        }

        let avg = durations.reduce(0, +) / Double(durations.count)
        let min = durations.min() ?? 0
        let max = durations.max() ?? 0

        return (avg, min, max)
    }

    func printReport() {
        print("=== Performance Report ===")
        for (name, _) in measurements {
            if let stats = getStats(for: name) {
                print("\(name):")
                print("  avg: \(String(format: "%.2fms", stats.avg * 1000))")
                print("  min: \(String(format: "%.2fms", stats.min * 1000))")
                print("  max: \(String(format: "%.2fms", stats.max * 1000))")
            }
        }
    }
}

// 8. Lazy property initialization
class LazyResource<T> {
    private var value: T?
    private let initializer: () -> T

    init(_ initializer: @escaping () -> T) {
        self.initializer = initializer
    }

    func get() -> T {
        if let existing = value {
            return existing
        }

        let new = initializer()
        value = new
        return new
    }

    func invalidate() {
        value = nil
    }
}

// Usage:
class HSMyModule {
    private lazy var expensiveResource = LazyResource {
        // Create expensive resource
        return ExpensiveResource()
    }

    func doWork() {
        let resource = expensiveResource.get()
        // Use resource
    }
}
```

**Implementation Steps:**
1. Add caching to application queries
2. Implement LRU cache utility
3. Make module loading asynchronous
4. Add resource limits and monitoring
5. Implement memory usage monitoring
6. Create performance profiling tools
7. Optimize hot paths identified by profiling
8. Add lazy loading for expensive resources

**Impact:** Better performance, reduced resource usage, scalability improvements

---

### 10. Code Organization & Structure (Low Priority)

**Current Issues:**
- Mixed responsibilities in some files
- No clear separation between public and internal APIs
- Extension in separate directory but could be better organized
- Some commented-out code (`Windows` module)

**Recommendations:**

**Improved Directory Structure:**
```
Hammerspoon 2/
├── Core/
│   ├── Engine/
│   │   ├── JSEngine.swift
│   │   ├── ModuleRoot.swift
│   │   ├── ModuleRegistry.swift
│   │   └── engine.js
│   │
│   ├── Managers/
│   │   ├── ManagerManager.swift
│   │   ├── SettingsManager.swift
│   │   └── PermissionsManager.swift
│   │
│   └── Utilities/
│       ├── Logging/
│       │   ├── HammerspoonLog.swift
│       │   ├── FileLogger.swift
│       │   └── LogFormatter.swift
│       │
│       ├── Errors/
│       │   ├── HammerspoonError.swift
│       │   └── ErrorPresenter.swift
│       │
│       └── Extensions/
│           ├── NSRunningApplication+Extensions.swift
│           └── Date+Extensions.swift
│
├── Modules/
│   ├── Application/
│   │   ├── ApplicationModule.swift
│   │   ├── ApplicationObject.swift
│   │   ├── ApplicationWatcher.swift
│   │   └── hs.application.js
│   │
│   ├── Timer/
│   │   ├── TimerModule.swift
│   │   └── TimerObject.swift
│   │
│   ├── Console/
│   │   └── ConsoleModule.swift
│   │
│   └── Shared/
│       └── HSModuleAPI.swift
│
├── Bridge/
│   ├── JSBridge.swift (JS ↔ Swift utilities)
│   ├── JSCallbackValidator.swift
│   ├── SafeJSCallback.swift
│   └── JSValueConverter.swift
│
├── UI/
│   ├── App/
│   │   └── Hammerspoon_2App.swift
│   │
│   ├── Console/
│   │   ├── ConsoleView.swift
│   │   └── ConsoleViewModel.swift
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── GeneralSettingsView.swift
│   │   ├── ConsoleSettingsView.swift
│   │   ├── LoggingSettingsView.swift
│   │   └── ModulesSettingsView.swift
│   │
│   └── About/
│       └── AboutView.swift
│
├── Resources/
│   ├── Assets.xcassets
│   └── Sparkle/
│
└── Tests/
    ├── CoreTests/
    ├── ModuleTests/
    ├── BridgeTests/
    └── Mocks/
```

**Code Organization Guidelines:**

1. **File Size:**
   - Keep files under 500 lines
   - Split large files into logical components
   - Use extensions for protocol conformance

2. **Naming:**
   - Prefix internal types with `_` or use `private`/`fileprivate`
   - Use `HS` prefix for JS-exposed types
   - Use `AK` prefix for logging functions (already established)

3. **Documentation:**
   - Public APIs: Full DocC documentation
   - Internal APIs: Brief comments
   - Complex logic: Inline comments

4. **Access Control:**
```swift
// Public API (exposed to other modules)
public class HSApplicationModule {
    // Public properties/methods
    public func runningApplications() -> [HSApplication]
}

// Internal implementation (module-private)
fileprivate class ApplicationCache {
    // Internal details
}

// Private (file-private)
private extension HSApplicationModule {
    func invalidateCache() {
        // Private helper
    }
}
```

5. **Remove Commented Code:**
```swift
// Instead of:
//    @objc var window: HSWindows { get { getOrCreate(name: "window", type: HSWindows.self)}}

// Create a feature branch or remove entirely
// Document why it's not included in Architecture.md
```

**Impact:** Easier navigation, better maintainability, clearer responsibilities

---

### 11. State Management & Reactive Patterns (Low Priority)

**Current Issues:**
- State scattered across singletons
- No centralized state management
- Limited use of SwiftUI's reactive features

**Recommendations:**

```swift
// 1. Centralized app state
@MainActor
@Observable
class AppState {
    static let shared = AppState()

    // Module states
    var loadedModules: [String] = []
    var moduleErrors: [String: Error] = [:]

    // Application state
    var isConfigLoaded = false
    var configLocation: URL?

    // UI state
    var isConsoleVisible = false
    var isSettingsVisible = false

    // Performance metrics
    var memoryUsage: UInt64 = 0
    var cpuUsage: Double = 0

    // Errors
    var recentErrors: [HammerspoonError] = []

    func addError(_ error: HammerspoonError) {
        recentErrors.append(error)
        if recentErrors.count > 10 {
            recentErrors.removeFirst()
        }
    }
}

// 2. Event bus for decoupled communication
class EventBus {
    static let shared = EventBus()

    typealias Handler = (Event) -> Void

    private var handlers: [String: [UUID: Handler]] = [:]

    func subscribe<T: Event>(_ eventType: T.Type, handler: @escaping (T) -> Void) -> UUID {
        let id = UUID()
        let eventName = String(describing: eventType)

        let wrapper: Handler = { event in
            if let typedEvent = event as? T {
                handler(typedEvent)
            }
        }

        if handlers[eventName] == nil {
            handlers[eventName] = [:]
        }
        handlers[eventName]?[id] = wrapper

        return id
    }

    func unsubscribe(_ id: UUID) {
        for eventName in handlers.keys {
            handlers[eventName]?.removeValue(forKey: id)
        }
    }

    func publish<T: Event>(_ event: T) {
        let eventName = String(describing: T.self)
        handlers[eventName]?.values.forEach { $0(event) }
    }
}

protocol Event {}

struct ModuleLoadedEvent: Event {
    let moduleName: String
}

struct ConfigReloadedEvent: Event {
    let configURL: URL
}

struct ErrorOccurredEvent: Event {
    let error: HammerspoonError
}

// Usage:
let subscription = EventBus.shared.subscribe(ModuleLoadedEvent.self) { event in
    print("Module loaded: \(event.moduleName)")
}

EventBus.shared.publish(ModuleLoadedEvent(moduleName: "application"))

// 3. State persistence
class StatePersistence {
    static func snapshot() -> [String: Any] {
        let state = AppState.shared
        return [
            "loadedModules": state.loadedModules,
            "configLocation": state.configLocation?.path ?? "",
            "timestamp": Date().timeIntervalSince1970
        ]
    }

    static func restore(from snapshot: [String: Any]) {
        // Restore state from snapshot
    }
}
```

**Impact:** More predictable state management, easier debugging, better testability

---

### 12. Accessibility & Window Management (Medium Priority)

**Current Issues:**
- `Windows` module commented out (`ModuleRoot.swift:23`)
- Limited AXSwift usage
- No clear plan for window management API
- Accessibility API can be challenging to work with

**File References:**
- `Engine/ModuleRoot.swift:23` - Commented out window module
- `Modules/Windows.swift` - Incomplete implementation

**Recommendations:**

```swift
// 1. Complete the Windows module with proper error handling
@MainActor
@objc class HSWindows: NSObject, HSModuleAPI, HSWindowsAPI {
    var name = "hs.window"

    required override init() {
        super.init()
    }

    func startup() async throws {
        // Check accessibility permissions
        guard await PermissionsManager.shared.checkAccessibility() else {
            throw HammerspoonError(.permissionDenied,
                                  msg: "Accessibility permissions required for window management")
        }
    }

    func shutdown() async throws {
        // Cleanup
    }

    @objc func focusedWindow() -> HSWindow? {
        do {
            guard let app = NSWorkspace.shared.frontmostApplication else {
                return nil
            }

            let axApp = try Application(app)
            let axWindow = try axApp.attribute(.focusedWindow, forKey: AXWindow.self)

            return HSWindow(axWindow: axWindow)
        } catch {
            AKError("Failed to get focused window: \(error)")
            return nil
        }
    }

    @objc func allWindows() -> [HSWindow] {
        var windows: [HSWindow] = []

        for app in NSWorkspace.shared.runningApplications {
            do {
                let axApp = try Application(app)
                let axWindows: [AXWindow] = try axApp.windows()
                windows.append(contentsOf: axWindows.map { HSWindow(axWindow: $0) })
            } catch {
                // Continue with next app
                continue
            }
        }

        return windows
    }
}

// 2. Window object with proper error handling
@objc protocol HSWindowAPI: JSExport {
    @objc var title: String? { get }
    @objc var frame: [String: Int] { get }
    @objc var isVisible: Bool { get }
    @objc var isMinimized: Bool { get }

    @objc func setFrame(_ frame: [String: Int]) -> Bool
    @objc func minimize() -> Bool
    @objc func unminimize() -> Bool
    @objc func focus() -> Bool
}

@objc class HSWindow: NSObject, HSWindowAPI {
    private let axWindow: UIElement

    init(axWindow: UIElement) {
        self.axWindow = axWindow
    }

    @objc var title: String? {
        return try? axWindow.attribute(.title)
    }

    @objc var frame: [String: Int] {
        do {
            let position: CGPoint = try axWindow.attribute(.position)
            let size: CGSize = try axWindow.attribute(.size)

            return [
                "x": Int(position.x),
                "y": Int(position.y),
                "w": Int(size.width),
                "h": Int(size.height)
            ]
        } catch {
            AKError("Failed to get window frame: \(error)")
            return ["x": 0, "y": 0, "w": 0, "h": 0]
        }
    }

    @objc var isVisible: Bool {
        return (try? axWindow.attribute(.hidden)) == false
    }

    @objc var isMinimized: Bool {
        return (try? axWindow.attribute(.minimized)) == true
    }

    @objc func setFrame(_ frame: [String: Int]) -> Bool {
        guard let x = frame["x"], let y = frame["y"],
              let w = frame["w"], let h = frame["h"] else {
            return false
        }

        do {
            try axWindow.setAttribute(.position, value: CGPoint(x: x, y: y))
            try axWindow.setAttribute(.size, value: CGSize(width: w, height: h))
            return true
        } catch {
            AKError("Failed to set window frame: \(error)")
            return false
        }
    }

    @objc func minimize() -> Bool {
        do {
            try axWindow.setAttribute(.minimized, value: true)
            return true
        } catch {
            AKError("Failed to minimize window: \(error)")
            return false
        }
    }

    @objc func unminimize() -> Bool {
        do {
            try axWindow.setAttribute(.minimized, value: false)
            return true
        } catch {
            AKError("Failed to unminimize window: \(error)")
            return false
        }
    }

    @objc func focus() -> Bool {
        do {
            try axWindow.setAttribute(.focused, value: true)
            return true
        } catch {
            AKError("Failed to focus window: \(error)")
            return false
        }
    }
}

// 3. Enhanced permission handling
class PermissionsManager {
    static let shared = PermissionsManager()

    func checkAccessibility() async -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func requestAccessibility() async -> Bool {
        // Prompt user for accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func monitorPermissionChanges(callback: @escaping (Bool) -> Void) {
        // Poll for permission changes
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task {
                let hasPermission = await self.checkAccessibility()
                callback(hasPermission)
            }
        }
    }
}

// 4. Re-enable in ModuleRoot
@objc var window: HSWindows {
    get { getOrCreate(name: "window", type: HSWindows.self) }
}
```

**Implementation Steps:**
1. Research Accessibility API limitations and workarounds
2. Implement core window operations with proper error handling
3. Add comprehensive permission checking
4. Test with various applications and edge cases
5. Document known limitations
6. Consider fallback approaches for apps that don't support Accessibility
7. Re-enable in ModuleRoot when stable

**Known Challenges:**
- Some apps don't fully support Accessibility API
- Permission prompts can be confusing for users
- Window management can be slow for large numbers of windows
- Some window properties may not be available on all apps

**Impact:** Feature completeness, parity with original Hammerspoon, improved user value

---

## Priority Matrix

| Priority | Improvements | Impact | Effort | ROI |
|----------|-------------|--------|--------|-----|
| **High** | 1. Error Handling | High | Medium | High |
| **High** | 2. Dependency Injection & Testing | High | High | High |
| **High** | 3. Thread Safety | High | Medium | High |
| **High** | 7. JS Bridge Safety | High | Medium | High |
| **Medium** | 4. Module System | Medium | Medium | Medium |
| **Medium** | 5. Configuration | Medium | Medium | Medium |
| **Medium** | 6. Logging | Medium | Low | High |
| **Medium** | 8. Documentation | High | Medium | High |
| **Medium** | 12. Windows Module | Medium | High | Medium |
| **Low** | 9. Performance | Medium | Medium | Medium |
| **Low** | 10. Code Organization | Low | Low | Medium |
| **Low** | 11. State Management | Low | Medium | Low |

---

## Implementation Roadmap

### Phase 1: Foundation (2-3 weeks)
**Goal:** Make the codebase robust and testable

1. **Week 1-2: Error Handling & Testing**
   - Expand `HammerspoonError` with all error types
   - Create protocol abstractions for dependencies
   - Set up test infrastructure
   - Write initial unit tests for critical paths
   - Add user-facing error notifications

2. **Week 2-3: Thread Safety**
   - Document threading model
   - Convert JSEngine to actor or add proper synchronization
   - Fix callback threading issues
   - Add thread safety tests
   - Enable Thread Sanitizer in CI

**Success Criteria:**
- 50%+ code coverage for core functionality
- No Thread Sanitizer warnings
- All error conditions have specific error types
- User-visible error messages for common failures

---

### Phase 2: Architecture (2-3 weeks)
**Goal:** Improve architecture and developer experience

3. **Week 3-4: Module System Enhancement**
   - Add module versioning
   - Implement dependency resolution
   - Create module registry
   - Add async module loading
   - Implement hot-reloading

4. **Week 4-5: JS Bridge Safety**
   - Implement callback validation
   - Add timeout protection
   - Use JSManagedValue for callbacks
   - Add rate limiting
   - Create security audit logging

**Success Criteria:**
- Modules can declare dependencies
- Hot-reload works without crashing
- No memory leaks from JS callbacks
- Long-running callbacks are interrupted

---

### Phase 3: Features (3-4 weeks)
**Goal:** Complete features and improve usability

5. **Week 5-6: Configuration Management**
   - Create comprehensive settings structure
   - Implement validation
   - Build enhanced Settings UI
   - Add export/import functionality

6. **Week 6-7: Logging Improvements**
   - Add structured logging
   - Implement file logging with rotation
   - Add log level filtering
   - Create log export

7. **Week 7-8: Documentation**
   - Write architecture documentation
   - Create module development guide
   - Expand API documentation
   - Create example configurations
   - Write contribution guidelines

**Success Criteria:**
- All settings configurable through UI
- File logging works with rotation
- Documentation covers all public APIs
- At least 5 example configurations

---

### Phase 4: Polish (2-3 weeks)
**Goal:** Performance optimization and code cleanup

8. **Week 8-9: Windows Module**
   - Research Accessibility API limitations
   - Implement core window operations
   - Add comprehensive error handling
   - Test with various applications
   - Document limitations

9. **Week 9-10: Performance Optimization**
   - Add caching where beneficial
   - Profile and optimize hot paths
   - Implement resource monitoring
   - Add lazy loading

10. **Week 10: Code Organization**
    - Reorganize directory structure
    - Split large files
    - Remove commented code
    - Clean up access control

**Success Criteria:**
- Windows module functional for 90% of apps
- Performance improvement measured
- No files over 500 lines
- All commented code removed or documented

---

## Summary

The Hammerspoon 2 codebase has a **solid foundation** with:
- Clean modular architecture
- Good separation of concerns
- Modern Swift features
- Elegant design

The **12 improvement areas** identified would make the codebase:
- **More Robust:** Better error handling, thread safety, testing
- **More Extensible:** Enhanced module system, configuration management
- **More Professional:** Comprehensive documentation, examples, testing
- **More Complete:** Windows module, enhanced features, performance optimization

**Priority Focus:**
1. **High Priority (Weeks 1-5):** Error handling, testing, thread safety, JS bridge safety
2. **Medium Priority (Weeks 5-8):** Module system, configuration, logging, documentation, Windows module
3. **Low Priority (Weeks 8-10):** Performance, code organization, state management

This phased approach allows for:
- Early wins in stability and testability
- Incremental improvements without major rewrites
- Continuous value delivery
- Manageable scope for each phase

The recommended 10-week roadmap balances technical debt reduction with feature development, ensuring the codebase becomes more maintainable while also more capable.
