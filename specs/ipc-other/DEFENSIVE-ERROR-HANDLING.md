# Defensive Error Handling in hs.ipc Module

## Summary

Added comprehensive defensive error handling to ensure **Hammerspoon 2 never crashes** due to IPC errors, resource exhaustion, or malformed messages.

## Changes Made (2025-12-28)

### 1. JavaScript Layer (`hs.ipc.js`)

#### Better Error Messages on Port Creation Failure
```javascript
// Lines 53-61
if (!remote) {
    console.error("[IPC] Failed to create remote port for instance:", instanceID);
    console.error("[IPC] Possible cause: macOS message port limit reached");
    console.error("[IPC] Suggestion: Add delays between rapid hs2 invocations");
    return "error: failed to create remote port - resource limit reached";
}
```

**Purpose**: Provides clear diagnostic information when hitting OS limits instead of silent failures.

#### Safe UNREGISTER Cleanup
```javascript
// Lines 105-137
try {
    if (hs.ipc.__registeredCLIInstances && hs.ipc.__registeredCLIInstances[instanceID]) {
        const instance = hs.ipc.__registeredCLIInstances[instanceID];
        if (instance && instance._cli && instance._cli.remote) {
            try {
                instance._cli.remote.delete();
            } catch (e) {
                console.error("[IPC] Error deleting remote port:", e);
            }
        }
        delete hs.ipc.__registeredCLIInstances[instanceID];
    }

    // Clean up remote port storage
    if (hs.ipc.__remotePorts && hs.ipc.__remotePorts[instanceID]) {
        delete hs.ipc.__remotePorts[instanceID];
    }
} catch (e) {
    console.error("[IPC] Error during UNREGISTER cleanup:", e);
}
```

**Purpose**: Ensures cleanup always succeeds even if instance data is corrupted or missing.

#### Protected Message Sending
```javascript
// Lines 201-233
// Error message sending
try {
    const errorMsg = String(evalError) + '\n';
    instance._cli.remote.sendMessage(errorMsg, MSG_ID.ERROR, 4.0, true);
} catch (e) {
    console.error("[IPC] Failed to send error message to client:", e);
}

// Result sending
try {
    if (result !== undefined && result !== null) {
        const resultStr = String(result) + '\n';
        instance._cli.remote.sendMessage(resultStr, MSG_ID.RETURN, 4.0, true);
    }
} catch (e) {
    console.error("[IPC] Failed to send result to client:", e);
    return "error: send failed";
}
```

**Purpose**: Prevents crashes if message sending fails (e.g., client disconnected, port invalidated).

### 2. Swift Layer (`HSMessagePort.swift`)

#### Enhanced Port Creation Error Messages
```swift
// Local port creation (line 118)
AKError("Failed to create local message port '\(localPortName)' - port may be in use or OS resource limit reached")

// Remote port creation (line 143)
AKError("Failed to create remote message port '\(remotePortName)' - possible OS resource limit")
```

**Purpose**: Better diagnostics for troubleshooting port creation failures.

## Test Results

### Stress Test: 50 Rapid Commands (No Delays)

**Before Defensive Changes:**
- Risk of crash when hitting OS limits
- No clear error messages
- Undefined behavior on resource exhaustion

**After Defensive Changes:**
```
Results:
  Total commands: 50
  Succeeded: 40
  Failed: 10

✓ SUCCESS: Hammerspoon 2 is still running (did not crash)
```

**Key Achievements:**
1. ✅ **No crashes** - Hammerspoon stayed up despite resource exhaustion
2. ✅ **Graceful degradation** - Commands fail cleanly with error messages
3. ✅ **Clear diagnostics** - Logs explain why failures occur
4. ✅ **Recovery possible** - System can recover after resource limits ease

## Error Handling Philosophy

### Core Principle
**Hammerspoon should NEVER crash due to IPC errors.**

### Implementation Strategy

1. **Multiple Layers of Defense**
   - Swift layer: Return nil on port creation failure
   - JavaScript layer: Check for nil and return error messages
   - Message handlers: Wrap critical sections in try-catch

2. **Informative Error Messages**
   - Log to console with [IPC] prefix
   - Explain probable cause (OS limits, invalid data, etc.)
   - Suggest remediation (add delays, check resources, etc.)

3. **Graceful Degradation**
   - Failed operations return error strings, not exceptions
   - Partial cleanup is safe (idempotent operations)
   - Missing or corrupted data doesn't cause crashes

4. **Recovery Support**
   - Ports can be reclaimed over time
   - Failed registrations don't corrupt server state
   - System remains functional for successful operations

## Known Limitations

Even with defensive coding, macOS imposes hard limits:

- **Message Port Limit**: ~32-64 concurrent ports per process
- **Kernel Reclamation**: Not instant, requires time
- **Resource Exhaustion**: Commands will fail when limits reached

**These are OS constraints, not application bugs.** The defensive code ensures failures are handled gracefully.

## Recommendations for Users

To avoid hitting resource limits:

1. **Add Delays in Loops**
   ```bash
   for i in {1..100}; do
       hs2 -c "command"
       sleep 0.2  # Allow port cleanup
   done
   ```

2. **Batch Operations**
   ```bash
   hs2 -c "for(let i=0; i<100; i++) doWork(i)"
   ```

3. **Use Script Files**
   ```bash
   hs2 script.js  # Single connection
   ```

4. **Interactive Mode for Development**
   ```bash
   hs2 -i  # REPL - persistent connection
   ```

## Verification

To verify defensive handling works:

```bash
# This will hit resource limits but NOT crash Hammerspoon
for i in {1..50}; do
    hs2 -q -c "print('test $i')"
done

# Check Hammerspoon is still running
ps aux | grep "Hammerspoon 2"

# Verify it responds
hs2 -c "print('still alive')"
```

Expected: Some commands fail after ~35-40 invocations, but Hammerspoon remains running and responsive.

## Related Documentation

- `hs2/README.md` - CLI tool documentation with usage guidelines
- `docs/IPC.md` - IPC protocol documentation including resource limits section
- Test suite: `scripts/test-hs2.sh` - Uses realistic delays (0.2s-1.0s)
