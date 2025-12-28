# Chore: Fix IPC Registered Instances Becoming Undefined

## Chore Description

The hs2 CLI tool experiences a critical failure where the `hs.ipc.__registeredCLIInstances` object becomes undefined after executing commands, causing subsequent commands and new hs2 connections to fail.

**Symptoms:**
1. First hs2 command succeeds (e.g., `print("hello")`)
2. Second hs2 command succeeds (e.g., `console.log("hello world")`)
3. Third hs2 command fails with: `TypeError: undefined is not an object (evaluating 'hs.ipc.__registeredCLIInstances[instanceID]')`
4. After the failure, attempting to reconnect hs2 results in "Registration failed" error
5. The error indicates that `hs.ipc.__registeredCLIInstances` itself has become undefined, not just missing a key

**Root Cause:**
The `hs.ipc.__registeredCLIInstances` object is initialized in `hs.ipc.js` at line 22 and used throughout the IPC protocol handler. However, the code does not defensively check if this object still exists before accessing it. If the object becomes undefined (through engine reset, garbage collection, or other JavaScript runtime issues), the entire IPC system breaks down.

**Impact:**
- hs2 CLI tool becomes completely unusable after a failure
- Requires restarting Hammerspoon 2 application to restore functionality
- Users cannot reliably use the REPL or execute commands from terminal

## Relevant Files

Use these files to resolve the chore:

- **Hammerspoon 2/Modules/hs.ipc/hs.ipc.js** - JavaScript IPC protocol handler
  - Contains the `__registeredCLIInstances` object initialization (line 22)
  - Contains the `__defaultHandler` function that processes IPC messages
  - Contains the vulnerable code at lines 150, 73, 112, 253 that access `__registeredCLIInstances` without defensive checks
  - Needs defensive initialization checks to prevent undefined access errors

- **Hammerspoon 2/Modules/hs.ipc/IPCModule.swift** - Swift IPC module implementation
  - Creates the local message port for IPC communication
  - Loads the companion hs.ipc.js file
  - May need to ensure proper initialization order

- **Hammerspoon 2/Engine/ModuleRoot.swift** - Module loading system
  - Lines 42-44: Loads companion .js files for modules
  - Ensures hs.ipc.js is loaded when hs.ipc module is accessed
  - Verify that .js file loading happens correctly

## Step by Step Tasks

IMPORTANT: Execute every step in order, top to bottom.

### Step 1: Add Defensive Initialization to IPC Handler

Add defensive checks throughout `hs.ipc.js` to ensure `__registeredCLIInstances` and `__remotePorts` objects always exist before accessing them:

- At the beginning of `__defaultHandler` function (after the try block starts), add initialization check:
  ```javascript
  // Defensive: Ensure storage objects exist
  if (!hs.ipc.__registeredCLIInstances) {
      hs.ipc.__registeredCLIInstances = {};
  }
  if (!hs.ipc.__remotePorts) {
      hs.ipc.__remotePorts = {};
  }
  ```

- This ensures that even if these objects somehow get cleared, they will be re-initialized on the next IPC message

### Step 2: Add Defensive Checks in COMMAND/QUERY Handler

In the COMMAND/QUERY message handler section (around line 150), add a defensive check and re-initialization:

- Before accessing `hs.ipc.__registeredCLIInstances[instanceID]`, ensure the object exists
- If the instance is not found, provide a more informative error message that distinguishes between:
  - Object itself is undefined (needs re-registration)
  - Instance ID not found (client disconnected)

- Update the error handling to suggest re-registration when the storage object is missing

### Step 3: Add Defensive Checks in Print Function

In the `hs.ipc.print` function (line 246), add defensive checks:

- Before iterating `for (const instanceID in hs.ipc.__registeredCLIInstances)`, verify the object exists
- If undefined, re-initialize and skip console mirroring (fail gracefully)

### Step 4: Add Module Re-initialization Safety

Ensure that if the module is accessed after being garbage collected or reset:

- The initialization code at lines 22-23 should use a pattern that checks if the property already exists
- Consider using: `hs.ipc.__registeredCLIInstances = hs.ipc.__registeredCLIInstances || {};`
- This makes re-loading the module idempotent and safe

### Step 5: Add Logging for Diagnostics

Add diagnostic logging when re-initializing storage objects:

- Log when `__registeredCLIInstances` is found to be undefined and gets re-created
- Log when `__remotePorts` is found to be undefined and gets re-created
- This will help identify the root cause if the issue persists

### Step 6: Review and Strengthen Error Boundaries

Review the entire `__defaultHandler` function to ensure:

- All access to `hs.ipc.__registeredCLIInstances` has defensive checks
- All access to `hs.ipc.__remotePorts` has defensive checks
- Errors in one IPC operation cannot corrupt the storage objects for other operations
- The try-catch at line 29 properly catches and reports all errors without leaving system in broken state

### Step 7: Test Edge Cases

Create test scenarios to validate the fix:

- Test rapid successive hs2 commands (what was failing)
- Test hs2 reconnection after a command failure
- Test multiple concurrent hs2 instances
- Test hs2 commands while Hammerspoon config is reloading
- Test with intentionally malformed IPC messages to ensure error handling is robust

### Step 8: Run Validation Commands

Execute the validation commands below to ensure the fix works correctly with zero regressions.

## Validation Commands

Execute every command to validate the chore is complete with zero regressions.

```bash
# Build the project
cd /Users/dmg/git.w/hs2/Hammerspoon2
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug build

# Launch Hammerspoon 2 in background
open "/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/Hammerspoon 2.app"

# Wait for startup
sleep 2

# Test basic connectivity
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "print('Test 1: Basic print')"

# Test console.log
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "console.log('Test 2: Console log')"

# Test rapid successive commands (the failing scenario)
for i in {1..10}; do
    /Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "console.log('Rapid test $i')"
done

# Test interactive REPL with multiple commands
echo -e "print('REPL test 1')\nconsole.log('REPL test 2')\nprint('REPL test 3')" | /Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -s

# Test reconnection after potential failure
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "print('After reconnect test')"

# Test that hs.ipc storage objects are accessible
/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2 -c "print('Instances: ' + Object.keys(hs.ipc.__registeredCLIInstances).length)"

# All commands should succeed without errors
```

## Document changes

No documentation changes required. This is an internal bug fix that makes the existing IPC system more robust. The user-facing API and behavior remain unchanged.

## Git log

```
Fix IPC registered instances becoming undefined

The hs.ipc module's __registeredCLIInstances and __remotePorts
storage objects could become undefined during runtime, causing
complete failure of the hs2 CLI tool.

Added defensive initialization checks throughout hs.ipc.js to ensure
these critical storage objects always exist before being accessed.
This prevents TypeError exceptions and ensures the IPC system can
recover gracefully from unexpected state corruption.

Changes:
- Add defensive re-initialization at start of __defaultHandler
- Add defensive checks before all __registeredCLIInstances access
- Add defensive checks before all __remotePorts access
- Make module initialization idempotent and safe for re-loading
- Add diagnostic logging when storage objects are re-created

Fixes issue where rapid hs2 commands would fail with:
"TypeError: undefined is not an object (evaluating
'hs.ipc.__registeredCLIInstances[instanceID]')"
```

## Notes

**Potential Root Causes to Investigate Further:**

While the defensive programming approach will fix the immediate issue, the underlying cause of why `hs.ipc.__registeredCLIInstances` becomes undefined is still unclear. Potential causes to investigate in the future:

1. **JavaScript Engine Resets**: If `hs.reload()` or `ManagerManager.boot()` is called while hs2 is connected, the JS context may be reset, clearing all module state
2. **Garbage Collection**: JavaScript GC may be collecting objects that are still referenced
3. **Memory Corruption**: Some operation may be corrupting the JavaScript heap
4. **Module Re-loading**: The hs.ipc.js file may be loaded multiple times, each creating a new closure

**Testing Notes:**

The original failure occurred on the third consecutive command. Testing should focus on:
- Rapid successive commands without delays
- Commands that trigger console output
- Commands that access the print() function
- Multiple concurrent hs2 instances

**Code Review Notes:**

The IPC protocol uses a complex callback and instance management system. The defensive approach taken here ensures robustness but doesn't prevent the original corruption. A deeper investigation into the JS engine lifecycle and module loading would be beneficial for long-term stability.
