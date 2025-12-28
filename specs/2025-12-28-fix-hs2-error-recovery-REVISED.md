# Chore: Fix hs2 CLI Error Recovery (REVISED)

## Chore Description

When running hs2 CLI commands, if a JavaScript command encounters an error (such as `throw new Error()`, syntax errors, or undefined variables), the hs2 tool immediately exits instead of reporting the error and continuing to accept additional commands. This makes it impossible to run multiple commands in sequence when one of them might fail.

**Current Behavior:**
- User runs: `hs2 -c "throw new Error('test')" -c "console.log('hello')"`
- The first command errors
- hs2 exits with code 65 (EX_DATAERR)
- The second command never executes

**Expected Behavior:**
- User runs: `hs2 -c "throw new Error('test')" -c "console.log('hello')"`
- The first command errors and prints the error to stderr
- hs2 continues and executes the second command
- hs2 exits with code 0 if it successfully communicated with Hammerspoon (even if user code had errors)
- hs2 only exits with error codes for IPC/communication failures, not user JavaScript errors

This behavior should match standard REPL behavior where errors are reported but execution continues. The distinction is:
- **Communication/IPC errors** (can't connect, timeout, etc.) → exit with error code
- **User JavaScript errors** (syntax errors, exceptions, etc.) → print error, continue execution, exit 0

## Relevant Files

Use these files to resolve the chore:

- **hs2/main.swift** - Main entry point for hs2 CLI tool
  - Contains command execution loop that currently breaks on first error
  - Needs modification to continue execution even when executeCommand() returns false for JavaScript errors
  - Should only break/exit on actual communication failures
  - **BUG IDENTIFIED**: Flag mappings are incorrect (see Step 0)

- **hs2/HSClient.swift** - IPC client implementation
  - Contains executeCommand() method that returns false on any error
  - Currently treats JavaScript evaluation errors the same as communication errors
  - Needs to distinguish between:
    - Communication failures (no response, timeout) → return false
    - JavaScript errors (error message received) → return true (communication succeeded)
  - Contains localPortCallback() that receives error messages
  - Already properly outputs errors to stderr with color support

- **Hammerspoon 2/Modules/hs.ipc/hs.ipc.js** - JavaScript IPC protocol handler
  - Contains error handling in COMMAND/QUERY handler that sends error message and returns "error"
  - The "error" return value causes executeCommand() to fail
  - Should return "ok" for JavaScript errors since the command was executed (even though it errored)
  - The actual error message is already sent via MSG_ID.ERROR before returning

## Step by Step Tasks

### Step 0: Fix command-line flag mappings (PREREQUISITE)

**Background**: The current hs2 flag mappings are incorrect compared to the original hs tool. This needs to be fixed to maintain compatibility.

**Original hs flag semantics**:
- `-n`: Disable colorized output
- `-N`: Force colorized output
- `-C`: Enable console mirroring (print cloning FROM Hammerspoon Console TO CLI instance)
- `-P`: Enable print mirroring (FROM CLI instance TO Hammerspoon Console)

**Current hs2 bug** (in main.swift):
- Line 83-84: `-n` → `useColors = false` ✓ CORRECT
- Line 86-87: `-N` → `consoleMirroring = false` ✗ WRONG (should be `useColors = true`)
- Line 89-90: `-C` → `useColors = true` ✗ WRONG (should be `consoleMirroring = true`)
- Missing `-P` flag entirely

**Fix required in main.swift**:

1. Locate the flag parsing section (lines 83-90)
2. Fix `-N` flag to set `useColors = true` (force colors)
3. Fix `-C` flag to set `consoleMirroring = true` (enable console mirroring)
4. Add `-P` flag for print mirroring (if print mirroring is implemented; otherwise document as future feature)
5. Update help text (lines 117-120) to match corrected behavior
6. Ensure flag logic matches the old hs behavior: `-C` and `-P` are mutually exclusive

**Updated flag mapping should be**:
```swift
case "-n":
    useColors = false

case "-N":
    useColors = true

case "-C":
    consoleMirroring = true
    // Note: In old hs, -C disables -P; implement if -P exists

case "-P":
    // TODO: Implement print mirroring (CLI → Hammerspoon)
    // printMirroring = true
    // consoleMirroring = false  // -P disables -C
```

### Step 1: Modify JavaScript error handling to distinguish error types

- Open `Hammerspoon 2/Modules/hs.ipc/hs.ipc.js`
- Locate the error handling section in the COMMAND/QUERY handler (line 232-239)
- **Change line 239 ONLY**: Change `return "error";` to `return "ok";`
- This ONLY affects the JavaScript evaluation error case
- All other error returns (protocol errors, IPC failures at lines 51, 62, 76, 182, 252, 261, 266, 270) should remain unchanged as they indicate actual communication failures
- Add a comment explaining this distinction:

```javascript
// Handle errors
if (evalError) {
    try {
        const errorMsg = String(evalError) + '\n';
        instance._cli.remote.sendMessage(errorMsg, MSG_ID.ERROR, 4.0, true);
    } catch (e) {
        console.error("[IPC] Failed to send error message to client:", e);
    }
    // Return "ok" to indicate IPC protocol succeeded even though JavaScript evaluation failed.
    // This allows the CLI to continue executing subsequent commands instead of exiting.
    // The actual error message was already sent to the client via MSG_ID.ERROR above.
    return "ok";
}
```

**Rationale**: The distinction is:
- JavaScript evaluation errors: error message sent via MSG_ID.ERROR, return "ok" (IPC succeeded)
- IPC/protocol errors: return "error: ..." strings (IPC failed)

### Step 2: Update HSClient to handle responses correctly

- Open `hs2/HSClient.swift`
- Locate the `executeCommand()` method (lines 169-198)
- The current logic checks if response is "ok" (line 188) and returns false if not
- Since JavaScript errors now return "ok" (after Step 1), the logic should be:
  - Response is "ok" → return true (command executed successfully via IPC)
  - Response is nil or not "ok" → return false (IPC communication failure)
- Error messages are already printed to stderr via `localPortCallback()` before `executeCommand()` returns
- No changes needed to the actual code - the existing check at line 188 already implements the correct logic
- **Verify** that the logic is:

```swift
guard let response = String(data: responseData as Data, encoding: .utf8),
      response.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
    exitCode = EX_DATAERR
    return false
}
return true
```

**Note**: After Step 1, JavaScript errors will return "ok", so this will return true and continue execution.

### Step 3: Verify main.swift command loop handles errors correctly

- Open `hs2/main.swift`
- Locate the command execution loop (lines 273-283)
- **VERIFY** (do not modify) that the loop only breaks when `executeCommand()` returns false:

```swift
for command in commandsToExecute {
    if !client.executeCommand(command) {
        break
    }
}
```

- After implementing Steps 1-2, this loop will automatically:
  - Continue execution when JavaScript errors occur (executeCommand returns true)
  - Only break on IPC communication failures (executeCommand returns false)
- **No code changes needed** - the existing logic is already correct

### Step 4: Test error recovery with multiple commands

Run validation commands to ensure:
- Single error command still prints error but exits 0
- Multiple commands with errors in the middle continue execution
- Communication errors still exit with error code
- Error messages are properly displayed to stderr
- Success messages continue to work

### Step 5: Test interactive REPL mode

Verify that:
- Errors in interactive mode don't terminate the REPL
- Error messages are displayed with proper formatting
- Next command can be entered after an error
- REPL only exits on explicit exit command or Ctrl-D

## Validation Commands

Execute every command to validate the chore is complete with zero regressions.

```bash
# Test 1: Single error command should print error and exit 0
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "throw new Error('test error')" 2>&1
echo "Exit code: $?"
# Expected: Error printed to stderr, exit code 0

# Test 2: Multiple commands with error in first position
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "throw new Error('first error')" -c "console.log('second command')" 2>&1
echo "Exit code: $?"
# Expected: Error printed, then "second command" printed, exit code 0

# Test 3: Multiple commands with error in middle position
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "console.log('first')" -c "undefined_var" -c "console.log('third')" 2>&1
echo "Exit code: $?"
# Expected: "first", error about undefined_var, "third", exit code 0

# Test 4: Multiple commands with error in last position
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "console.log('first')" -c "console.log('second')" -c "throw new Error('last error')" 2>&1
echo "Exit code: $?"
# Expected: "first", "second", error, exit code 0

# Test 5: Syntax error recovery
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "invalid syntax {{" -c "console.log('after syntax error')" 2>&1
echo "Exit code: $?"
# Expected: Syntax error printed, then "after syntax error", exit code 0

# Test 6: Successful commands should still work
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "console.log('hello')" -c "1 + 1" 2>&1
echo "Exit code: $?"
# Expected: "hello" and "2" printed, exit code 0

# Test 7: Test that connection failures still exit with error code
# This tests the pre-flight check in main.swift (lines 211-219), not IPC error recovery
# (Quit Hammerspoon 2 first, then run with -A to prevent auto-launch)
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -A -c "console.log('test')" 2>&1
echo "Exit code: $?"
# Expected: Connection error, exit code 69 (EX_UNAVAILABLE)

# Test 8: Verify command-line flags work correctly after Step 0 fix
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -N -c "console.log('colors forced')" 2>&1
# Expected: Output with color codes even if stdout is redirected

/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -n -c "console.log('no colors')" 2>&1
# Expected: Output without color codes

# Test 9: Verify existing tests still pass
cd /Users/dmg/git.w/hs2/Hammerspoon2 && xcodebuild test -scheme "Hammerspoon 2" -only-testing:Hammerspoon\ 2Tests/HS2CommandTests 2>&1 | grep -E "(Test Case .* passed|Test Suite .* passed|FAIL)"
# Expected: All HS2CommandTests pass (or update tests if they expect old behavior)
```

## Document Changes

Update/create the following documentation to reflect the new error handling behavior:

### Create/Update: hs2/README.md

Create if missing. Add a section explaining error handling:

```markdown
## Error Handling

### JavaScript Errors vs IPC Errors

hs2 distinguishes between two types of errors:

1. **JavaScript Errors** - Errors in user code (syntax errors, exceptions, undefined variables)
   - Reported to stderr with color coding
   - Execution continues to next `-c` command
   - Exit code remains 0 (IPC communication succeeded)

2. **IPC/Communication Errors** - Failures in communicating with Hammerspoon
   - Connection failures, timeouts, protocol errors
   - Execution stops immediately
   - Exit code set to non-zero (e.g., 69 for EX_UNAVAILABLE)

### Multiple Command Execution

When multiple `-c` commands are specified, all will execute even if earlier ones error:

```bash
# Both commands execute, even though first has error
hs2 -c "throw new Error('oops')" -c "console.log('still runs')"
```

### Exit Code Semantics

- **Exit code 0**: IPC communication succeeded (user code may have had errors)
- **Exit code 69 (EX_UNAVAILABLE)**: Cannot connect to Hammerspoon
- **Exit code 65 (EX_DATAERR)**: IPC protocol error

To check for JavaScript errors, parse stderr output rather than relying on exit codes.
```

### Create/Update: docs/IPC.md

Create if missing. Add error handling philosophy section:

```markdown
## IPC Error Handling Philosophy

### Protocol Errors vs User Code Errors

The IPC module distinguishes between two error categories:

1. **Protocol/IPC Errors**: Problems with the communication channel itself
   - Invalid message format
   - Failed to create ports
   - Instance not registered
   - Message port timeout

2. **User Code Errors**: JavaScript evaluation errors
   - Syntax errors
   - Runtime exceptions
   - Undefined variables

### Server-Side Behavior (hs.ipc.js)

When handling COMMAND/QUERY messages:
- JavaScript evaluation errors: Send error via MSG_ID.ERROR, return "ok"
- Protocol errors: Return "error: <description>"

This allows the client to:
- Continue execution after user code errors (REPL behavior)
- Stop execution on protocol failures (communication broken)

### Client-Side Behavior (HSClient.swift)

The `executeCommand()` method returns:
- `true`: IPC succeeded (command was executed, even if it errored)
- `false`: IPC failed (communication problem)

Error messages are delivered asynchronously via `localPortCallback()` and printed to stderr.

### CLI Tool Behavior (hs2)

When executing multiple `-c` commands:
- JavaScript errors: Printed to stderr, execution continues
- IPC errors: Execution stops, non-zero exit code

Exit codes indicate IPC success, not JavaScript correctness.
```

### Update: CLAUDE.md

Update the existing hs2 Command-Line Tool section (around line 903):

Find the section starting with `### hs2 Command-Line Tool` and add after the examples:

```markdown
**Error Handling**:

hs2 uses REPL-style error handling where JavaScript errors are reported but don't terminate execution:

```bash
# First command errors but second still runs
hs2 -c "undefined_variable" -c "console.log('still executes')"

# Exit code is 0 because IPC succeeded
echo $?  # Outputs: 0
```

**Error Types**:
- **JavaScript errors**: Reported to stderr, execution continues, exit code 0
- **IPC errors**: Reported to stderr, execution stops, exit code 69 or 65

**Exit Code Semantics**:
- `0` - IPC communication succeeded (JavaScript may have had errors)
- `69` (EX_UNAVAILABLE) - Cannot connect to Hammerspoon 2
- `65` (EX_DATAERR) - IPC protocol/communication error

Scripts that need to detect JavaScript errors should parse stderr output rather than checking exit codes.
```

## Git Log

```
Fix hs2 CLI error recovery and flag mappings

This commit fixes two issues with the hs2 CLI tool:

1. Error Recovery: When hs2 executes JavaScript commands that encounter
   errors (syntax errors, exceptions, undefined variables), it now reports
   the error and continues execution instead of immediately exiting. This
   matches standard REPL behavior where user code errors are reported but
   don't terminate the tool.

2. Flag Mappings: Fixed command-line flags to match original hs tool:
   - -N now forces colors (was: disable console mirroring)
   - -C now enables console mirroring (was: force colors)
   - Help text updated to reflect correct behavior

Changes:
- Modified hs.ipc.js to return "ok" for JavaScript evaluation errors
  since the IPC protocol successfully executed the command
- Updated flag parsing in main.swift to match original hs semantics
- JavaScript errors are printed to stderr but don't stop command execution
- Exit code 0 indicates successful IPC communication (even if JS errored)
- Non-zero exit codes reserved for actual IPC/communication failures

This enables multi-command workflows like:
  hs2 -c "risky_command()" -c "fallback_command()"

where both commands execute regardless of whether the first one errors.
```

## Notes

### Key Design Decision: Exit Codes

The fundamental change is in how we interpret "success":
- **Old behavior**: Exit code reflects whether JavaScript executed without errors
- **New behavior**: Exit code reflects whether IPC communication succeeded

This is the correct UNIX philosophy: the tool (hs2) succeeded in its job of communicating with Hammerspoon and executing code. Whether that code had bugs is a separate concern.

### Exit Code Flow

After this change, the exit code flow is:
1. Start with `client.exitCode = 0` (HSClient.swift initialization)
2. IPC/communication failures set `client.exitCode = EX_UNAVAILABLE` or `EX_DATAERR`
3. JavaScript errors do NOT modify exitCode (remains 0)
4. `main.swift:320` exits with `client.exitCode`

Therefore, exit code 0 indicates all IPC operations succeeded, regardless of JavaScript errors.

### Error Message Flow

The current error reporting mechanism already works correctly:
1. JavaScript error occurs in hs.ipc.js
2. Error message sent via `MSG_ID.ERROR` to client
3. Client callback receives message and prints to stderr with color
4. Server returns response to executeCommand()

We're only changing step 4: return "ok" instead of "error" to indicate IPC success.

### Backward Compatibility

This is technically a breaking change for any scripts that rely on hs2's exit code to detect JavaScript errors. However:
- This is more consistent with standard REPL/shell behavior
- It enables important use cases (error recovery, fallback commands)
- The actual error output is still visible on stderr
- Scripts can still parse stderr for errors if needed
- Matches the philosophy of the original hs tool

### Testing Considerations

The existing test suite in `HS2CommandTests` should be reviewed to ensure:
- Tests expecting non-zero exit codes on JavaScript errors are updated
- Tests for communication failures still expect non-zero exit codes
- New tests are added for multi-command error recovery scenarios

### Flag Fix Compatibility

The flag mapping fixes restore compatibility with the original hs tool, ensuring:
- Users familiar with the original tool can use the same flags
- Documentation examples from original Hammerspoon work correctly
- Scripts using hs CLI flags work with hs2
