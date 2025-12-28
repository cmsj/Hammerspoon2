# hs2 Test Fixtures

This directory contains JavaScript test files for the hs2 command-line tool.

## Purpose

These fixture files are used to test hs2 functionality by executing complete JavaScript programs and verifying their output. This approach is modeled after the original Hammerspoon's `test_*.lua` files.

## Available Fixtures

### basic_print.js
Tests basic print functionality.
- **Expected**: Prints "Hello from hs2"
- **Exit Code**: 0

### math_operations.js
Tests JavaScript math operations and Math object.
- **Expected**: Various mathematical results
- **Exit Code**: 0

### functions.js
Tests function definitions, calls, and recursion.
- **Expected**: Function return values (add, greet, factorial)
- **Exit Code**: 0

### arrays_objects.js
Tests arrays, objects, and array methods (map, reduce, join).
- **Expected**: Array and object property access and transformations
- **Exit Code**: 0

### hs_timer.js
Tests access to Hammerspoon hs.timer module and helper functions.
- **Expected**: hs.timer helper function results (minutes, hours, days, weeks)
- **Exit Code**: 0

### error_test.js
Tests error handling - this file deliberately throws an error.
- **Expected**: Error message
- **Exit Code**: Non-zero (error)

## Usage

### From XCTest

```swift
func testMyFixture() {
    let fixturePath = "Hammerspoon 2Tests/Fixtures/hs2/my_test.js"
    let (stdout, stderr, exitCode) = runHS2Command([fixturePath], quiet: true)

    XCTAssertEqual(exitCode, 0)
    XCTAssertTrue(stdout.contains("expected output"))
}
```

### From Shell Script

The `test-hs2.sh` script automatically discovers and runs all `*.js` files in this directory:

```bash
./scripts/test-hs2.sh
```

### Manual Execution

```bash
# Build first
xcodebuild -scheme "Development" -configuration Debug build

# Start Hammerspoon 2
open "Build/Products/Debug/Hammerspoon 2.app"

# Run fixture
Build/Products/Debug/hs2 "Hammerspoon 2Tests/Fixtures/hs2/basic_print.js"
```

## Adding New Fixtures

1. **Create new .js file** in this directory
2. **Add descriptive comments** at the top
3. **Write test code**
4. **Document expected output and exit code**

### Template

```javascript
// Test: [Brief description of what this tests]
// Expected Output: [What should be printed/returned]
// Expected Exit Code: [0 for success, 1 for error]

// Your test code here
print("Test output");
```

### Example

```javascript
// Test: String manipulation methods
// Expected Output: Various string results
// Expected Exit Code: 0

var str = "Hello, Hammerspoon!";

print(str.length);                   // 19
print(str.toUpperCase());            // HELLO, HAMMERSPOON!
print(str.substring(0, 5));          // Hello
print(str.indexOf("Hammer"));        // 7
print(str.replace("Hammer", "Test"));// Hello, Testspoon!
```

## Best Practices

### 1. Self-Documenting
Use comments to explain what each test does and what output is expected.

### 2. Focused Tests
Each fixture should test one specific area (functions, arrays, module access, etc.)

### 3. Clear Output
Use `print()` statements to produce verifiable output.

### 4. Error Tests
If testing error handling, use a filename like `error_*.js` and throw errors explicitly.

### 5. Module Tests
When testing hs.* modules, verify:
- Module is accessible (`typeof hs.module === "object"`)
- Functions exist (`typeof hs.module.function === "function"`)
- Functions work correctly (call them and check results)

## Comparison to Hammerspoon's Lua Tests

Original Hammerspoon uses `test_*.lua` files in each extension directory:

```lua
-- Hammerspoon Lua test
function test()
    hs.alert.show("test")
    return "Success"
end
```

hs2 JavaScript equivalents:

```javascript
// hs2 JavaScript test
print(typeof hs.alert);              // object
// hs.alert.show is async, so we just verify it exists
print(typeof hs.alert.show);         // function
```

## Debugging Failed Fixtures

If a fixture test fails:

1. **Run manually**
   ```bash
   Build/Products/Debug/hs2 "path/to/fixture.js"
   ```

2. **Check output**
   - Does it match expected output?
   - Are there error messages?

3. **Add debug prints**
   ```javascript
   console.log("Debug: variable value is", someVar);
   ```

4. **Test in Console**
   - Open Hammerspoon 2 Console
   - Paste and run code interactively

5. **Check dependencies**
   - Does the fixture rely on specific hs modules?
   - Are those modules loaded?

## See Also

- [HS2-TESTING-GUIDE.md](../HS2-TESTING-GUIDE.md) - Complete testing guide
- [HS2CommandTests.swift](../../IntegrationTests/HS2CommandTests.swift) - XCTest suite
- `scripts/test-hs2.sh` - Shell test runner
