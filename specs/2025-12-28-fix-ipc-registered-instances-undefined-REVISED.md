# Chore: Fix IPC Registered Instances Becoming Undefined - REVISED PLAN

## Chore Description

The hs2 CLI tool experiences a critical failure where the `hs.ipc.__registeredCLIInstances` object becomes undefined after executing commands, causing subsequent commands and new hs2 connections to fail.

**Symptoms:**
1. First hs2 command succeeds (e.g., `print("hello")`)
2. Second hs2 command succeeds (e.g., `console.log("hello world")`)
3. Third hs2 command fails with: `TypeError: undefined is not an object (evaluating 'hs.ipc.__registeredCLIInstances[instanceID]')`
4. After the failure, attempting to reconnect hs2 results in "Registration failed" error
5. The error indicates that `hs.ipc.__registeredCLIInstances` itself has become undefined, not just missing a key

**Root Cause:**
The `hs.ipc.__registeredCLIInstances` object is initialized in `hs.ipc.js` but can become undefined during runtime. The code does not defensively check if this object still exists before accessing it.

**Impact:**
- hs2 CLI tool becomes completely unusable after a failure
- Requires restarting Hammerspoon 2 application to restore functionality
- Users cannot reliably use the REPL or execute commands from terminal

**Design Decisions (User-Confirmed):**
1. **Module reload behavior:** Clear CLI instances on reload (fresh start)
2. **Robustness:** Hammerspoon must never crash; hs2 must handle communication failures gracefully
3. **Logging:** Verbose console.log for debugging
4. **Error recovery:** Always defensive - recover gracefully, inform CLI of failures
5. **Priority:** Fix immediately (utmost priority)

## Relevant Files

- **Hammerspoon 2/Modules/hs.ipc/hs.ipc.js** - JavaScript IPC protocol handler
  - Contains `__registeredCLIInstances` initialization
  - Contains `__defaultHandler` function that processes IPC messages
  - Needs defensive initialization checks throughout

- **scripts/test-hs2.sh** - Shell-based integration tests for hs2
  - Add new test for multiple console.log calls

## Step by Step Tasks

IMPORTANT: Execute every step in order, top to bottom.

### Step 1: Add Defensive Initialization at Start of __defaultHandler

In `hs.ipc.js`, immediately after the try block starts (around line 30), add:

```javascript
// DEFENSIVE: Ensure storage objects exist before processing any message
// This prevents TypeError if objects become undefined during runtime
if (!hs.ipc.__registeredCLIInstances) {
    console.log("[IPC] CRITICAL: __registeredCLIInstances was undefined, re-initializing");
    hs.ipc.__registeredCLIInstances = {};
}
if (!hs.ipc.__remotePorts) {
    console.log("[IPC] CRITICAL: __remotePorts was undefined, re-initializing");
    hs.ipc.__remotePorts = {};
}
```

**Rationale:** Guards against undefined objects for ALL message types before any processing.

### Step 2: Add Defensive Check in COMMAND/QUERY Handler

In `hs.ipc.js`, find the line that reads:
```javascript
const instance = hs.ipc.__registeredCLIInstances[instanceID];
```

(This is in the COMMAND/QUERY message handler section)

Add defensive check BEFORE this line:
```javascript
// DEFENSIVE: Verify storage object exists before accessing
if (!hs.ipc.__registeredCLIInstances) {
    console.log("[IPC] CRITICAL: __registeredCLIInstances undefined during COMMAND/QUERY, re-initializing");
    hs.ipc.__registeredCLIInstances = {};
}

const instance = hs.ipc.__registeredCLIInstances[instanceID];
if (!instance) {
    console.log("[IPC] ERROR: Instance", instanceID, "not registered. Storage object exists:", !!hs.ipc.__registeredCLIInstances);
    console.log("[IPC] ERROR: Registered instances:", hs.ipc.__registeredCLIInstances ? Object.keys(hs.ipc.__registeredCLIInstances) : 'undefined');
    return "error: instance not registered - client must reconnect";
}
```

**Rationale:** Prevents TypeError and provides verbose diagnostic information.

### Step 3: Add Defensive Check in hs.ipc.print Function

In `hs.ipc.js`, find the hs.ipc.print function (contains the for loop over __registeredCLIInstances).

Add defensive check BEFORE the for loop:
```javascript
// DEFENSIVE: Ensure storage object exists before iterating
if (!hs.ipc.__registeredCLIInstances) {
    console.log("[IPC] CRITICAL: __registeredCLIInstances undefined in hs.ipc.print(), re-initializing");
    console.log("[IPC] WARNING: Console mirroring skipped due to missing storage");
    hs.ipc.__registeredCLIInstances = {};
    // Cannot mirror to instances that don't exist, but we've recovered the object
    // Just call original print and return
    hs.ipc.__originalPrint(...args);
    return;
}

for (const instanceID in hs.ipc.__registeredCLIInstances) {
```

**Rationale:** Prevents TypeError during console mirroring, fails gracefully by skipping mirroring.

### Step 4: Add Defensive Check in Instance Print Function

In `hs.ipc.js`, find the instance.print function (created during REGISTER).

Find the line inside instance.print that reads:
```javascript
const instance = hs.ipc.__registeredCLIInstances[instanceID];
```

Add defensive check BEFORE this line:
```javascript
// DEFENSIVE: Check if storage still exists (can be cleared on reload)
if (!hs.ipc.__registeredCLIInstances) {
    console.log("[IPC] CRITICAL: __registeredCLIInstances undefined in instance.print() for", instanceID);
    console.log("[IPC] WARNING: Print output lost - instance storage cleared (likely due to reload)");
    return;
}

const instance = hs.ipc.__registeredCLIInstances[instanceID];
```

**Rationale:** Prevents TypeError in instance-specific print callback.

### Step 5: Make Module Initialization Clear on Reload

In `hs.ipc.js`, change the initialization line (around line 22) from:
```javascript
hs.ipc.__registeredCLIInstances = {};
```

To:
```javascript
// Always clear instances on module load - forces re-registration after reload
// This is safe because hs.reload() destroys the entire JS context
hs.ipc.__registeredCLIInstances = {};
console.log("[IPC] Initialized __registeredCLIInstances (cleared any previous instances)");
```

**Rationale:** Clear intent that reload means fresh start. Verbose logging for debugging.

### Step 6: Add Diagnostic Logging Throughout

Add console.log statements for key operations:

1. After creating storage objects in Step 1:
```javascript
console.log("[IPC] Storage check complete. Instances:", Object.keys(hs.ipc.__registeredCLIInstances).length, "RemotePorts:", hs.ipc.__remotePorts ? Object.keys(hs.ipc.__remotePorts).length : 0);
```

2. In REGISTER handler, after storing instance (already exists at line 102):
```javascript
// Keep existing logging
```

3. In UNREGISTER handler, after cleanup (already exists at line 132):
```javascript
// Keep existing logging
```

**Rationale:** Verbose diagnostic output helps track storage object lifecycle.

### Step 7: Add Test for Multiple Console.Log Calls

In `scripts/test-hs2.sh`, add a new test to `run_stress_tests()` function (after the sequential execution test):

```bash
echo -n "  Multiple console.log in rapid succession (15 calls) ... "
local failed=0
for i in {1..15}; do
    if ! "$HS2_BINARY" -q -c "console.log('console.log test $i')" >/dev/null 2>&1; then
        failed=1
        echo -e "\n    Failed on iteration $i"
        break
    fi
    # Small delay to allow port cleanup
    sleep 0.1
done

TESTS_RUN=$((TESTS_RUN + 1))
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
```

**Rationale:** Tests the exact failure scenario (rapid console.log calls) that triggers the bug.

### Step 8: Run Validation Commands

Execute the validation commands below to ensure the fix works correctly with zero regressions.

## Validation Commands

Execute every command to validate the chore is complete with zero regressions.

```bash
# Build the project
cd /Users/dmg/git.w/hs2/Hammerspoon2
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug build

# Run the test suite (includes new console.log test)
./scripts/test-hs2.sh

# Manual verification: Test rapid successive commands (the failing scenario)
HS2_BINARY="/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/hs2"

# Launch Hammerspoon 2 if not running
open "/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/Hammerspoon 2.app"
sleep 3

# Test 1: Basic connectivity
$HS2_BINARY -c "print('Test 1: Basic print')"

# Test 2: Console.log
$HS2_BINARY -c "console.log('Test 2: Console log')"

# Test 3: Rapid successive console.log (the original failure case)
for i in {1..20}; do
    echo "Iteration $i"
    $HS2_BINARY -c "console.log('Rapid console.log test $i')"
done

# Test 4: Mixed print and console.log
$HS2_BINARY -c "print('print output')"
$HS2_BINARY -c "console.log('console.log output')"
$HS2_BINARY -c "print('print again')"
$HS2_BINARY -c "console.log('console.log again')"

# Test 5: Verify storage objects are accessible
$HS2_BINARY -c "print('Instances: ' + Object.keys(hs.ipc.__registeredCLIInstances).length)"

# All commands should succeed without errors
# Console output should show verbose IPC logging
```

## Document Changes

No user-facing documentation changes required. This is an internal bug fix that makes the existing IPC system more robust. The user-facing API and behavior remain unchanged.

## Git Log

```
Fix IPC registered instances becoming undefined

The hs.ipc module's __registeredCLIInstances and __remotePorts
storage objects could become undefined during runtime, causing
complete failure of the hs2 CLI tool after 2-3 commands.

Added defensive initialization checks throughout hs.ipc.js to ensure
these critical storage objects always exist before being accessed.
This prevents TypeError exceptions and ensures the IPC system can
recover gracefully from unexpected state corruption.

Changes:
- Add defensive re-initialization at start of __defaultHandler
- Add defensive checks before all __registeredCLIInstances accesses
- Add defensive checks in instance print callback
- Add defensive checks in hs.ipc.print function
- Make module initialization explicit about clearing on reload
- Add verbose diagnostic logging for debugging
- Add test for rapid console.log calls in test-hs2.sh

Fixes issue where rapid hs2 commands would fail with:
"TypeError: undefined is not an object (evaluating
'hs.ipc.__registeredCLIInstances[instanceID]')"

Design decisions:
- Always clear instances on module reload (user confirmed)
- Verbose console.log logging (user confirmed)
- Never crash Hammerspoon or hs2 (user confirmed)
- Gracefully recover from storage corruption
```

## Notes

**Robustness Requirements (User-Confirmed):**
1. Hammerspoon must never crash from IPC errors
2. hs2 CLI must handle communication failures gracefully
3. Verbose logging for debugging
4. Defensive programming throughout

**Testing Focus:**
- Rapid successive console.log calls (original failure scenario)
- Mixed print and console.log commands
- Verification that storage objects persist correctly

**Root Cause Investigation (Deferred):**
While the defensive approach fixes the immediate issue, the underlying cause of why `__registeredCLIInstances` becomes undefined is still unclear. This could be investigated in the future, but the priority is making the system robust regardless of root cause.
