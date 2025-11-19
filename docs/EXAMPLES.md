# Documentation System Examples

This document shows examples of how the documentation system processes Swift and JavaScript files.

## Example 1: Swift Module with Documentation

### Input: Swift File (hs.timer/TimerModule.swift)

```swift
@objc protocol HSTimerModuleAPI: JSExport {
    /// Create a new timer
    /// - Parameters:
    ///   - interval: The interval in seconds at which the timer should fire
    ///   - callback: A JavaScript function to call when the timer fires
    ///   - continueOnError: If true, the timer will continue running even if the callback throws an error
    /// - Returns: A timer object. Call start() to begin the timer.
    @objc func new(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool) -> HSTimerObject
}
```

### Output: JSON (docs/json/hs.timer.json)

```json
{
  "name": "hs.timer",
  "swift": {
    "protocols": [{
      "name": "HSTimerModuleAPI",
      "methods": [{
        "name": "new",
        "signature": "func new(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool) -> HSTimerObject",
        "documentation": "Create a new timer\n- Parameters:\n  - interval: The interval in seconds...",
        "params": [
          {"name": "interval", "type": "TimeInterval"},
          {"name": "callback", "type": "JSValue"},
          {"name": "continueOnError", "type": "Bool"}
        ],
        "returns": {
          "type": "HSTimerObject",
          "description": "A timer object. Call start() to begin the timer."
        }
      }]
    }]
  }
}
```

### Output: Combined JSDoc (docs/json/combined/hs.timer.js)

```javascript
/**
 * @module hs.timer
 */

/**
 * Create a new timer
 * - Parameters:
 *   - interval: The interval in seconds at which the timer should fire
 *   - callback: A JavaScript function to call when the timer fires
 *   - continueOnError: If true, the timer will continue running even if the callback throws an error
 * - Returns: A timer object. Call start() to begin the timer.
 * @param {number} interval
 * @param {JSValue} callback
 * @param {boolean} continueOnError
 * @returns {HSTimerObject} A timer object. Call start() to begin the timer.
 * @memberof hs.timer
 * @instance
 */
function _new(interval, callback, continueOnError) {}
```

Note: `new` is a JavaScript keyword, so it's escaped to `_new`.

## Example 2: JavaScript Enhancement File

### Input: JavaScript File (hs.window/hs.window.js)

```javascript
/**
 * Filter windows by title
 * @param {string} title - The title to search for
 * @returns {Array<HSWindow>} Array of matching windows
 */
hs.window.findByTitle = function(title) {
    return hs.window.allWindows().filter(win => {
        return win.title && win.title.includes(title);
    });
};
```

### Output: JSON (docs/json/hs.window.json)

```json
{
  "javascript": {
    "functions": [{
      "name": "hs.window.findByTitle",
      "params": ["title"],
      "documentation": {
        "description": "Filter windows by title",
        "params": [{
          "name": "title",
          "type": "string",
          "description": "The title to search for"
        }],
        "returns": {
          "type": "Array<HSWindow>",
          "description": "Array of matching windows"
        }
      }
    }]
  }
}
```

### Output: Combined JSDoc

```javascript
/**
 * Filter windows by title
 * @param {string} title The title to search for
 * @returns {Array<HSWindow>} Array of matching windows
 * @memberof hs.window
 * @function
 */
hs.window.findByTitle = function(title) {}
```

## Example 3: Type Conversion

The system automatically converts Swift types to JSDoc-compatible types:

| Swift Type | JSDoc Type |
|------------|------------|
| `String` | `string` |
| `Int`, `Double`, `Float` | `number` |
| `Bool` | `boolean` |
| `TimeInterval` | `number` |
| `[Type]` | `Array<Type>` |
| `[Key: Value]` | `Object<Key, Value>` |
| `Type?` | `Type` (optional marker removed) |
| `Any` | `*` |

### Example:

```swift
@objc func windowsForApp(_ app: HSApplication) -> [HSWindow]
```

Becomes:

```javascript
/**
 * @param {HSApplication} app
 * @returns {Array<HSWindow>}
 */
function windowsForApp(app) {}
```

## Example 4: Combined Module Documentation

A complete module combines both Swift and JavaScript documentation:

### Module: hs.alert

**Swift Protocol** (AlertModule.swift):
- `newAlert() -> HSAlert` - Creates an alert object
- `showAlert(_ alert: HSAlert)` - Displays an alert

**JavaScript Enhancement** (hs.alert.js):
- `hs.alert.show(message)` - Convenience function to show a simple alert

The final HTML documentation shows all of these together under the `hs.alert` module.

## Viewing the Documentation

### JSON Format
```bash
# View all modules
cat docs/json/index.json | jq '.modules'

# View specific module
cat docs/json/hs.window.json | jq '.swift.protocols[0].methods'
```

### HTML Format
```bash
# Generate and open
npm run docs:generate
open docs/api/index.html
```

The HTML documentation provides:
- Module overview page
- Searchable function/method index
- Detailed parameter and return type information
- Source links (for JavaScript functions)

## Coverage Report

```bash
npm run docs:coverage
```

Output:
```
Documentation Coverage Report
============================

Module Breakdown:
--------------------------------------------------------------------------------
Module              Swift Methods  Swift Props  JS Functions
--------------------------------------------------------------------------------
hs.timer             7/7 (100%)     1/1 (100%)   0/10 (0%)
hs.window            7/7 (100%)     1/1 (100%)   0/6 (0%)
...

Overall Summary:
--------------------------------------------------------------------------------
Swift Methods:     60/65 (92%)
Swift Properties:  6/7 (86%)
JS Functions:      0/25 (0%)
Total:             66/97 (68%)
```

## Best Practices

### For Swift Files

1. Use `///` comments for all public API methods and properties
2. Document parameters with `- Parameter name: description`
3. Document return values with `- Returns: description`
4. Keep documentation concise but complete

Example:
```swift
/// Get the currently focused window
/// - Returns: The focused window, or nil if none
@objc func focusedWindow() -> HSWindow?
```

### For JavaScript Files

1. Use JSDoc `/** */` comments for all public functions
2. Include `@param` for each parameter with type and description
3. Include `@returns` with type and description
4. Add `@example` sections when helpful

Example:
```javascript
/**
 * Move window to left half of screen
 * @param {HSWindow} win - The window to move (defaults to focused window)
 * @returns {boolean} True if successful
 * @example
 * hs.window.moveToLeftHalf()
 */
hs.window.moveToLeftHalf = function(win) {
    // implementation
}
```
