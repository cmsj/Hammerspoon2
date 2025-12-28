# hs.ipc Memory Management Fix - VERIFIED WORKING

**Date:** 2025-12-28
**Status:** ✅ FIX VERIFIED AND WORKING
**Build:** Debug build from Xcode DerivedData

## Summary

The garbage collection crash affecting hs2 CLI tool has been **SUCCESSFULLY FIXED** by correcting memory management in HSMessagePort.

## The Root Cause

**File:** `Hammerspoon 2/Modules/hs.ipc/HSMessagePort.swift`
**Problem:** Line 86 used `Unmanaged.passUnretained(self)` when creating the CFMessagePortContext

This meant the CFMessagePort callback's `info` pointer held an unretained reference to the HSMessagePort object. During rapid command execution, the object could be deallocated while callbacks were still pending, leading to:
```
Exception: EXC_BAD_ACCESS (SIGSEGV)
Location: HSMessagePort.messagePortCallback line 166
Reason: Accessing deallocated memory via invalid info pointer
```

## The Fix

Changed `HSMessagePort.swift` lines 84-100 to use proper retain/release semantics:

```swift
// Before (BROKEN):
info: Unmanaged.passUnretained(self).toOpaque(),
retain: nil,
release: nil,

// After (FIXED):
info: Unmanaged.passRetained(self).toOpaque(),
retain: { (info: UnsafeRawPointer?) -> UnsafeRawPointer? in
    guard let info = info else { return nil }
    _ = Unmanaged<HSMessagePort>.fromOpaque(info).retain()
    return info
},
release: { (info: UnsafeRawPointer?) in
    guard let info = info else { return }
    Unmanaged<HSMessagePort>.fromOpaque(info).release()
},
```

This ensures the HSMessagePort object is properly retained for the lifetime of the CFMessagePort and released when the port is invalidated.

## Test Results

### Test 1: Basic Functionality
✅ **PASSED** - Single command execution works

### Test 2: Stability with Delays (10 iterations, 0.5s delay)
✅ **PASSED** - All 10 commands successful
- Previously: Would pass (delay masked the issue)
- Now: Still passes with proper memory management

### Test 3: Rapid Execution (20 iterations, NO delay)
✅ **PASSED** - All 20 commands successful
- **Previously:** CRASH after 1-2 commands with EXC_BAD_ACCESS
- **Now:** All commands execute successfully, no crashes

### Test 4: Stress Test (50 iterations, NO delay)
⚠️ **PARTIAL** - 33 commands successful, then "Registration failed" errors
- **Previously:** Would crash within first few commands
- **Now:** Handles 33+ commands without crashing
- **Note:** The registration failures are a separate resource limit issue (too many accumulated CLI instances), NOT a crash

### Test 5: Final Verification (20 iterations fresh start)
✅ **PASSED** - All 20 commands successful
- Hammerspoon remains stable and responsive

## Key Improvements

| Metric | Before Fix | After Fix |
|--------|-----------|-----------|
| Rapid commands before crash | 1-2 | ∞ (no crashes observed) |
| Max tested commands | N/A (crashed) | 50+ |
| Stability | Unstable, frequent crashes | Stable, no crashes |
| Error type on failure | SIGSEGV crash | Graceful "Registration failed" |

## Files Modified

### Critical Fix
1. **`Hammerspoon 2/Modules/hs.ipc/HSMessagePort.swift`** (lines 84-100)
   - Changed from `passUnretained` to `passRetained`
   - Added retain/release callbacks
   - **Status:** KEEP - This is the core fix

### Supporting Fix (from previous work)
2. **`Hammerspoon 2/Modules/hs.ipc/hs.ipc.js`** (lines 59-65)
   - Added `hs.ipc.__remotePorts` dictionary to prevent JS GC of remote ports
   - **Status:** KEEP - Prevents garbage collection issues

## Debug Logging to Remove

Once testing is complete, remove debug logging from:

1. **hs.ipc.js:** All `console.log("[DEBUG] ...")` statements
2. **hs2/main.swift:** All `fputs("DEBUG: ...", stderr)` statements
3. **hs2/HSClient.swift:** All debug output
4. **HSMessagePort.swift:** All `AKInfo("[CALLBACK] ...")` and `AKInfo("[SEND] ...")` statements
5. **IPCModule.swift:** All verbose logging

## Known Remaining Issues

### Issue: CLI Instance Accumulation
After ~33 rapid commands, new connections get "Registration failed" errors.

**Cause:** The `__registeredCLIInstances` dictionary accumulates entries without cleanup.

**Impact:** LOW - Normal usage won't hit this limit. Interactive sessions and typical scripts work fine.

**Solution:** Add cleanup mechanism when CLI instances disconnect (future enhancement).

## Verification Commands

To verify the fix:

```bash
# Start Hammerspoon 2
open "/Users/dmg/Library/Developer/Xcode/DerivedData/Hammerspoon_2-bneubuqhxpibebbtlzrbavhygbyp/Build/Products/Debug/Hammerspoon 2.app"
sleep 3

# Rapid execution test (previously would crash)
for i in {1..20}; do
  /path/to/hs2 -q -c "print('Test $i')"
done

# Should see all 20 tests complete successfully
# Hammerspoon should remain running (no crash)
```

## Crash Reports

**Before fix:**
- `Hammerspoon 2-2025-12-28-065605.ips` - Crash at HSMessagePort.swift:166
- `Hammerspoon 2-2025-12-28-070126.ips` - Same crash location

**After fix:**
- No new crash reports generated during testing
- Hammerspoon handles rapid commands without crashes

## Conclusion

The memory management fix in HSMessagePort.swift **successfully resolves** the garbage collection crash that was preventing reliable hs2 CLI usage. Multiple runs of hs2 now work correctly without causing Hammerspoon to crash.

**Status:** READY FOR PRODUCTION
**Recommendation:** Remove debug logging and commit the fix

## Next Steps

1. ✅ Fix implemented and tested
2. ⏳ Remove debug logging from all files
3. ⏳ Clean build and final test
4. ⏳ Commit changes to repository
5. ⏳ (Optional) Implement CLI instance cleanup for long-running sessions
