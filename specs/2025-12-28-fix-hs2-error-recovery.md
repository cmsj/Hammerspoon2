# Chore: Fix hs2 CLI Error Recovery

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

### Step 1: Modify JavaScript error handling to distinguish error types

- Open `Hammerspoon 2/Modules/hs.ipc/hs.ipc.js`
- Locate the error handling section in the COMMAND/QUERY handler where evalError is checked
- Change the return value from "error" to "ok" when a JavaScript evaluation error occurs
- The error message is already being sent to the client via `MSG_ID.ERROR`, so returning "ok" indicates that the IPC protocol succeeded in executing the command (even though the JavaScript code errored)
- This distinguishes between:
  - JavaScript errors: error message sent, return "ok" (IPC succeeded)
  - IPC/protocol errors: return "error: ..." strings (IPC failed)
- Add a comment explaining this distinction for future maintainers

### Step 2: Update HSClient to handle error messages correctly

- Open `hs2/HSClient.swift`
- Locate the `executeCommand()` method
- Modify the logic to distinguish between communication failures and JavaScript errors
- When response is "error", check if we've already received error output via the callback
- Since JavaScript errors are already printed to stderr via the callback (msgID=ERROR), we should return true to indicate the command executed successfully from an IPC perspective
- Only return false for actual communication failures (nil response, timeout, invalid response format)
- Consider tracking whether an error callback was received during command execution to provide better diagnostics

### Step 3: Update main.swift command loop to handle errors gracefully

- Open `hs2/main.swift`
- Locate the command execution loop that iterates through commandsToExecute
- Review the break condition that checks the return value of executeCommand()
- Since executeCommand() will now return true for JavaScript errors, the loop will continue automatically
- Keep the break for communication failures (executeCommand returns false)
- Ensure the exit code logic at the end of main still works correctly
- The exitCode should remain 0 for JavaScript errors, only non-zero for communication failures

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
# Expected: Error printed to stderr, exit code 0

# Test 2: Multiple commands with error in first position
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "throw new Error('first error')" -c "console.log('second command')" 2>&1
# Expected: Error printed, then "second command" printed, exit code 0

# Test 3: Multiple commands with error in middle position
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "console.log('first')" -c "undefined_var" -c "console.log('third')" 2>&1
# Expected: "first", error about undefined_var, "third", exit code 0

# Test 4: Multiple commands with error in last position
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "console.log('first')" -c "console.log('second')" -c "throw new Error('last error')" 2>&1
# Expected: "first", "second", error, exit code 0

# Test 5: Syntax error recovery
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "invalid syntax {{" -c "console.log('after syntax error')" 2>&1
# Expected: Syntax error printed, then "after syntax error", exit code 0

# Test 6: Successful commands should still work
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "console.log('hello')" -c "1 + 1" 2>&1
# Expected: "hello" and "2" printed, exit code 0

# Test 7: Test that connection failures still exit with error code
# (Stop Hammerspoon 2 first, then run)
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -A -c "console.log('test')" 2>&1
# Expected: Connection error, exit code 69 (EX_UNAVAILABLE)

# Test 8: Verify existing tests still pass
cd /Users/dmg/git.w/hs2/Hammerspoon2 && xcodebuild test -scheme "Hammerspoon 2" -only-testing:Hammerspoon\ 2Tests/HS2CommandTests 2>&1 | grep -E "(Test Case .* passed|Test Suite .* passed|FAIL)"
# Expected: All HS2CommandTests pass
```

## Document Changes

Update the following documentation to reflect the new error handling behavior:

- **hs2/README.md** - If it exists, add a section explaining error handling:
  - JavaScript errors are reported but don't stop execution
  - Multiple -c commands will all execute even if earlier ones error
  - Exit code 0 means IPC communication succeeded (even if JavaScript errored)
  - Non-zero exit codes indicate communication/IPC failures

- **docs/IPC.md** - Add a section on error handling philosophy:
  - Distinction between protocol errors (IPC) and user code errors (JavaScript)
  - Error recovery behavior in CLI mode
  - How errors are communicated via MSG_ID.ERROR

- **CLAUDE.md** - Update the hs2 Command-Line Tool section:
  - Add explanation of error handling behavior
  - Document that errors don't terminate execution
  - Explain exit code semantics (0 = IPC success, non-zero = IPC failure)

## Git Log

```
Fix hs2 CLI error recovery - continue execution after JavaScript errors

When hs2 executes JavaScript commands that encounter errors (syntax errors,
exceptions, undefined variables), it now reports the error and continues
execution instead of immediately exiting. This matches standard REPL
behavior where user code errors are reported but don't terminate the tool.

Changes:
- Modified hs.ipc.js to return "ok" for JavaScript evaluation errors
  since the IPC protocol successfully executed the command
- Updated HSClient.executeCommand() to distinguish between communication
  failures and JavaScript errors
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

### Testing Considerations

The existing test suite in `HS2CommandTests` should be reviewed to ensure:
- Tests expecting non-zero exit codes on JavaScript errors are updated
- Tests for communication failures still expect non-zero exit codes
- New tests are added for multi-command error recovery scenarios
