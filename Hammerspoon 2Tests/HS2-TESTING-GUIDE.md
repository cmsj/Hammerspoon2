# hs2 Command-Line Tool - Testing Guide

This guide explains how to test the hs2 command-line tool using the comprehensive test infrastructure modeled after the original Hammerspoon's testing framework.

## Table of Contents

- [Overview](#overview)
- [Test Infrastructure](#test-infrastructure)
- [Running Tests](#running-tests)
- [XCTest Integration Tests](#xctest-integration-tests)
- [Shell Script Tests](#shell-script-tests)
- [Test Fixtures](#test-fixtures)
- [Writing New Tests](#writing-new-tests)
- [CI/CD Integration](#cicd-integration)

## Overview

The hs2 testing infrastructure includes:

1. **XCTest Integration Tests** - Swift-based tests that run in Xcode
2. **Shell Script Test Runner** - Standalone script for command-line testing
3. **Test Fixtures** - JavaScript files for comprehensive scenario testing
4. **Helper Utilities** - Reusable test infrastructure

This approach mirrors the original Hammerspoon's test structure while adapting it for JavaScript and the hs2 tool.

## Test Infrastructure

### Directory Structure

```
Hammerspoon 2Tests/
├── IntegrationTests/
│   ├── HS2CommandTests.swift        # XCTest suite for hs2
│   ├── HSIPCIntegrationTests.swift  # Tests for hs.ipc module
│   └── ...
├── Fixtures/
│   └── hs2/
│       ├── basic_print.js           # Simple print test
│       ├── math_operations.js       # Math operations
│       ├── functions.js             # Function definitions
│       ├── arrays_objects.js        # Arrays and objects
│       ├── hs_timer.js              # hs.timer module access
│       └── error_test.js            # Error handling
├── Helpers/
│   └── JSTestHarness.swift          # Test harness utility
└── HS2-TESTING-GUIDE.md             # This file

scripts/
└── test-hs2.sh                      # Shell-based test runner
```

## Running Tests

### Method 1: Xcode (XCTest Suite)

1. **Open Project in Xcode**
   ```bash
   open "Hammerspoon 2.xcodeproj"
   ```

2. **Run All Tests**
   - Press `Cmd+U` or use Product → Test
   - Tests will run in Xcode's test navigator

3. **Run Specific Test Suite**
   - Open `HS2CommandTests.swift`
   - Click the diamond icon next to the test class or method
   - Or use `Cmd+Ctrl+U` to re-run last test

4. **View Test Results**
   - Test navigator (Cmd+6) shows pass/fail status
   - Report navigator (Cmd+9) shows detailed logs

### Method 2: Command Line (Shell Script)

1. **Build the Project First**
   ```bash
   xcodebuild -scheme "Development" -configuration Debug build
   ```

2. **Run Test Script**
   ```bash
   ./scripts/test-hs2.sh
   ```

   The script will:
   - Verify binaries exist
   - Start Hammerspoon 2
   - Run all test suites
   - Report results with color-coded output
   - Stop Hammerspoon 2

3. **Expected Output**
   ```
   ==================================
   hs2 Integration Test Suite
   ==================================
   [INFO] Checking prerequisites...
   [INFO] All prerequisites met
   [INFO] Starting Hammerspoon 2...
   [INFO] Hammerspoon 2 is ready

   [INFO] Running basic functionality tests...
     Test 1: Simple print ... PASS
     Test 2: Math operations ... PASS
     ...

   [INFO] Running error handling tests...
     Test 8: Syntax error detection ... PASS
     ...

   [INFO] Running fixture file tests...
     Fixture: basic_print ... PASS
     ...

   [INFO] Running stress tests (rapid execution)...
     Rapid execution (10 commands) ... PASS

   ==================================
   Test Results Summary
   ==================================
   Tests run:    20
   Tests passed: 20
   Tests failed: 0
   ==================================
   [INFO] All tests passed!
   ```

### Method 3: GitHub Actions / CI

```yaml
# .github/workflows/test.yml
- name: Run hs2 Tests
  run: |
    xcodebuild -scheme "Development" -configuration Debug build
    ./scripts/test-hs2.sh
```

## XCTest Integration Tests

### Test Class: HS2CommandTests

Located in: `Hammerspoon 2Tests/IntegrationTests/HS2CommandTests.swift`

#### Features

- **Automatic Hammerspoon Management**: Starts/stops Hammerspoon 2 for each test run
- **Helper Methods**: `runHS2Command()`, `evalCode()` for easy test writing
- **Comprehensive Coverage**: Basic functionality, errors, files, stdin, stress tests
- **Timeout Handling**: Prevents hanging tests
- **Exit Code Validation**: Verifies proper error codes

#### Example Test

```swift
func testSimplePrint() {
    let output = evalCode("print('Hello, World!')")
    XCTAssertEqual(output, "Hello, World!", "Should print simple string")
}

func testMultipleStatements() {
    let code = """
    print('Line 1');
    print('Line 2');
    print('Line 3');
    """
    let output = evalCode(code)
    XCTAssertEqual(output, "Line 1\nLine 2\nLine 3", "Should execute multiple statements")
}
```

#### Test Categories

1. **Basic Functionality**
   - Simple print statements
   - Multiple statements
   - Math operations
   - Functions and variables

2. **Hammerspoon Module Access**
   - hs namespace availability
   - hs.timer module
   - Helper functions (minutes, hours, etc.)

3. **Error Handling**
   - Syntax errors
   - Runtime errors
   - Undefined variables

4. **File Execution**
   - Execute .js files
   - Handle non-existent files

5. **Stdin Processing**
   - Read from stdin
   - Pipe input

6. **Stress Tests**
   - Rapid command execution
   - Concurrent commands
   - Memory management regression tests

7. **Command-line Flags**
   - Multiple -c commands
   - Help flag
   - Interactive mode detection

## Shell Script Tests

### Script: test-hs2.sh

Located in: `scripts/test-hs2.sh`

#### Features

- **Self-contained**: Manages Hammerspoon lifecycle
- **Color-coded Output**: Green for pass, red for fail
- **Test Categories**: Basic, errors, fixtures, stress
- **Detailed Reporting**: Summary with counts
- **Exit Codes**: Returns 0 on success, 1 on failure

#### Customization

Edit the script to:
- Add new test categories
- Adjust timeouts
- Change build paths
- Add custom assertions

#### Example Addition

```bash
run_custom_test() {
    echo ""
    log_info "Running custom tests..."

    run_test "Custom test name" \
        "$HS2_BINARY -q -c 'print(\"custom\")'"
}

# In main():
run_custom_test  # Add after other test suites
```

## Test Fixtures

### Purpose

Fixture files are JavaScript files that test specific scenarios. They're similar to Hammerspoon's `test_*.lua` files.

### Location

`Hammerspoon 2Tests/Fixtures/hs2/*.js`

### Available Fixtures

| File | Tests | Expected Output |
|------|-------|----------------|
| `basic_print.js` | Simple print | "Hello from hs2" |
| `math_operations.js` | Arithmetic, Math functions | Results of operations |
| `functions.js` | Function definitions, recursion | Function results |
| `arrays_objects.js` | Arrays, objects, map/reduce | Array/object operations |
| `hs_timer.js` | hs.timer module access | Timer helper results |
| `error_test.js` | Error throwing | Should exit with error |

### Creating New Fixtures

1. **Create file in fixtures directory**
   ```bash
   touch "Hammerspoon 2Tests/Fixtures/hs2/my_test.js"
   ```

2. **Add test code with comments**
   ```javascript
   // Test description
   // Expected output: What should happen

   print("Test output");
   ```

3. **Tests automatically discover new fixtures**
   - Shell script scans `*.js` files
   - XCTest can use `runHS2Command()` with file path

### Fixture Template

```javascript
// Test: [What this tests]
// Expected: [Expected behavior]
// Exit Code: [0 for success, 1 for error]

// Your test code here
print("Result");
```

## Writing New Tests

### Adding XCTest

1. **Open HS2CommandTests.swift**
2. **Add new test method**
   ```swift
   func testMyNewFeature() {
       let output = evalCode("print('new feature')")
       XCTAssertEqual(output, "new feature")
   }
   ```
3. **Run tests** (Cmd+U in Xcode)

### Adding Shell Script Test

1. **Open scripts/test-hs2.sh**
2. **Add to appropriate test suite**
   ```bash
   run_test "My new test" \
       "$HS2_BINARY -q -c 'print(\"test\")'"
   ```
3. **Or create new test suite**
   ```bash
   run_my_tests() {
       echo ""
       log_info "Running my tests..."
       run_test "Test 1" "$HS2_BINARY -q -c '...'"
   }

   # In main():
   run_my_tests
   ```

### Testing Checklist

When adding new hs2 functionality, test:

- [ ] Basic execution works
- [ ] Handles errors gracefully
- [ ] Exit codes are correct
- [ ] Works from files and -c commands
- [ ] Works from stdin
- [ ] Multiple rapid executions don't crash
- [ ] Integrates with hs modules
- [ ] Command-line flags work
- [ ] Help text is accurate

## Best Practices

### 1. Test Independence

Each test should:
- Not depend on other tests
- Clean up after itself
- Not affect global state

### 2. Descriptive Names

```swift
// Good
func testMultipleStatementsExecuteSequentially()

// Bad
func test1()
```

### 3. Clear Assertions

```swift
// Good
XCTAssertEqual(output, "expected", "Math should calculate 2+2=4")

// Bad
XCTAssertTrue(output == "expected")
```

### 4. Test Error Cases

```swift
func testDivisionByZeroHandled() {
    let (_, stderr, exitCode) = runHS2Command(["-c", "print(1/0)"])
    // Verify it handles the error appropriately
}
```

### 5. Use Fixtures for Complex Tests

Instead of inline multi-line strings, create a fixture file for readability.

## Troubleshooting

### Tests Fail to Start

**Problem**: "Hammerspoon 2 failed to start"

**Solutions**:
- Ensure app is built: `xcodebuild ...`
- Check no zombie processes: `killall -9 "Hammerspoon 2"`
- Verify paths in test configuration

### Tests Timeout

**Problem**: Tests hang indefinitely

**Solutions**:
- Increase timeout in `setUp()` or test methods
- Check Hammerspoon 2 is responding
- Look for infinite loops in test code

### Flaky Tests

**Problem**: Tests pass sometimes, fail other times

**Solutions**:
- Add proper waits for async operations
- Increase startup timeout
- Check for race conditions
- Run tests sequentially, not concurrently

### Permission Errors

**Problem**: Accessibility or other permissions

**Solutions**:
- Grant permissions to Xcode
- Grant permissions to Hammerspoon 2
- Check System Preferences → Security & Privacy

## CI/CD Integration

### GitHub Actions Example

```yaml
name: hs2 Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v2

      - name: Build Hammerspoon 2
        run: |
          xcodebuild -scheme "Development" \
                     -configuration Debug \
                     build

      - name: Run hs2 Integration Tests
        run: |
          ./scripts/test-hs2.sh

      - name: Run XCTests
        run: |
          xcodebuild -scheme "Development" \
                     -configuration Debug \
                     test

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v2
        with:
          name: test-results
          path: build/TestResults.xcresult
```

## Comparison to Original Hammerspoon

| Aspect | Original Hammerspoon | hs2 (Hammerspoon 2) |
|--------|---------------------|---------------------|
| Language | Lua | JavaScript |
| Test Files | `test_*.lua` | `*.js` fixtures |
| Test Framework | Custom Lua runner | XCTest + Shell script |
| Module Loading | `require('test_module')` | `hs.module` |
| Assertions | Lua assertions | XCTest assertions |
| CI Integration | `github-ci-test.sh` | `test-hs2.sh` |
| Test Harness | `HSTestCase.m` | `JSTestHarness.swift` |

## Summary

The hs2 testing infrastructure provides:

✅ **Comprehensive Coverage** - Unit, integration, and stress tests
✅ **Multiple Methods** - XCTest for Xcode, Shell for CI
✅ **Modeled on Hammerspoon** - Familiar structure and patterns
✅ **Easy to Extend** - Add tests via XCTest methods or fixtures
✅ **CI-Ready** - Shell script designed for automated testing

For questions or issues, refer to the XCTest documentation or examine the original Hammerspoon's test suite in `hs_repo_old/`.
