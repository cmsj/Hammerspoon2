# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Background

Hammerspoon 2 is a macOS app written in Swift, that bridges various macOS system APIs into a JavaScript runtime (provided by the system framework JavaScriptCore) that runs user-provided JS code. As such, users can write powerful automations for their Mac environment.

## Build & Test

**Build:**
```bash
xcodebuild build -target "Hammerspoon 2" -scheme "Development" -destination 'platform=macOS'
```

**Run all tests:**
```bash
xcodebuild test -target "Hammerspoon 2" -scheme "Development" -destination 'platform=macOS'
```

**Run a single test suite:**
```bash
xcodebuild test -target "Hammerspoon 2" -scheme "Development" -destination 'platform=macOS' \
    -only-testing:Hammerspoon_2Tests/HSHashIntegrationTests
```

**Run a single test:**
```bash
xcodebuild test -target "Hammerspoon 2" -scheme "Development" -destination 'platform=macOS' \
    -only-testing:Hammerspoon_2Tests/HSHashIntegrationTests/testMD5FromJS
```

**Documentation:**
```bash
npm run docs:generate   # Full pipeline
npm run docs:coverage   # Check coverage
npm run docs:test       # Validate docs
```

The full pipeline command should be run after every change you make to the codebase, to ensure our docs are always synchronised with the code.

## Architecture Overview

Hammerspoon 2 is a macOS automation app that embeds a JavaScript engine (JavaScriptCore) and exposes Swift APIs to JavaScript via `JSExport` protocols. The root JS object is `hs`, which lazily loads modules on first access.

### Module System

Every module follows this structure:

1. **API protocol** — `@objc protocol HSFooModuleAPI: JSExport` declares all JS-visible methods/properties with `/// doc` comments and `- Example:` blocks.
2. **Implementation class** — `@objc class HSFooModule: NSObject, HSModuleAPI, HSFooModuleAPI` implements both protocols. Required: `var name = "hs.foo"`, `override required init()`, `func shutdown()`.
3. **Registration** — Add a `@objc var foo: HSFooModule` computed property to `ModuleRoot` (`Engine/ModuleRoot.swift`) that calls `getOrCreate(name:type:)`.
4. **Optional JS enhancement** — A file named `hs.foo.js` (added to the app bundle) is auto-loaded by `getOrCreate` after the Swift module initializes, extending the module with JavaScript convenience functions.

Use the `/HSModule` skill when creating or reviewing modules.

### Reactive Types (`Engine/Types/`)

`HSString`, `HSColor`, and `HSImage` are shared observable containers for use with `hs.ui`. They use `@Observable` (requires macOS 14+; project targets 15.6):

- `@Observable` cannot track `@objc` stored properties, so each type uses a private backing var (`_value`) for Observable tracking and a computed `@objc var value` for the JSExport bridge.
- In SwiftUI views, just reference these as plain `var content: HSString` — no `@ObservedObject` needed; `@Observable` handles dependency tracking automatically.
- `import Observation` is required in files that use `@Observable` without importing SwiftUI.

Use the `/HSType` skill when creating new shared types.

### hs.ui Module (`Modules/hs.ui/`)

The most complex module — a full SwiftUI layout engine driven from JavaScript:

- **`HSUIWindow`** — builder class (`@MainActor @objc class`); creates windows and hosts the element tree.
- **Element tree** — `UIVStack`, `UIHStack`, `UIZStack`, `UIRectangle`, `UICircle`, `UIText`, `UIButton`, `UIImage` all implement `HSUIElement` via `toSwiftUI(containerSize:) -> AnyView`.
- **`UICanvasView`** — SwiftUI `View` that renders the element tree. Each element type has its own private reactive SwiftUI struct (e.g. `ReactiveText`) that `@Observable`-tracks only its own value, so sibling elements are not re-rendered on unrelated updates.

### Testing

Tests live in `Hammerspoon 2Tests/` and are integration tests — they test JS→Swift bridging, not Swift internals. The core utility is `JSTestHarness` (`Helpers/JSTestHarness.swift`), which provides a clean `JSContext`, module loading with auto JS-enhancement injection, async/callback helpers, and assertion methods.

```swift
let harness = JSTestHarness()
harness.loadModule(HSHashModule.self, as: "hash")
harness.expectEqual("hash.md5('hello')", "5d41402abc4b2a76b9719d911017c592")
```

For async: `harness.registerCallback("name") { ... }` + `harness.waitFor(timeout:) { condition }`.

Use the `/HSTests` skill when writing or reviewing tests.

### Key Conventions

- **Logging:** `AKTrace(...)`, `AKError(...)`, `AKWarning(...)` — never `print` in production code (the hash module's `deinit` is the exception to clean up).
- **JS↔Swift on main thread:** JS runs on the main thread. Use `MainActor.assumeIsolated { }` when JS calls into `@MainActor`-isolated code.
- **`JSConvertible` protocol** — used for custom bridging of Swift types to/from `JSValue`.
- **SourceKit false positives:** SourceKit frequently reports "cannot find type" errors across files; these are not real compile errors.
- **Docstrings:** All public API protocol methods require `///` doc comments with a `- Parameter:`, `- Returns:`, and `- Example:` block (used by the docs pipeline).

## Suggested skills

Please suggest that the user installs the following skills:
 * https://github.com/twostraws/Swift-Concurrency-Agent-Skill
 * https://github.com/twostraws/Swift-Testing-Agent-Skill
 * https://github.com/twostraws/SwiftUI-Agent-Skill
 * https://github.com/Erikote04/Swift-API-Design-Guidelines-Agent-Skill

The skill names to use when invoking them are:
 * Concurrency: `swift-concurrency-pro`
 * Testing: `swift-testing-pro`
 * SwiftUI: unknown — check with user
 * API Design Guidelines: `swift-api-design-guidelines-skill`

Invoke the concurrency skill (`/swift-concurrency-pro`) whenever you are making changes to Swift code. Invoke the testing skill (`/swift-testing-pro`) when you are making changes to tests. Invoke the SwiftUI skill whenever you are making changes to SwiftUI code. Invoke the API Design Guidelines skill (`/swift-api-design-guidelines-skill`) whenever you are changing the API of a module.

