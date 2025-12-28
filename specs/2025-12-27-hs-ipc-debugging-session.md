# hs2 IPC Debugging Session - 2025-12-27

## Problem Statement

The hs2 CLI tool successfully connects to Hammerspoon 2 and sends commands, but:
1. Commands hang and never return
2. Output from print() never appears
3. Even simple expressions like `2 + 2` hang
4. No JavaScript execution logs are visible

## Testing Performed

### Test 1: Basic print command
```bash
hs2 -c 'print("hello world")'
```
**Result**: Command hangs indefinitely, no output

### Test 2: Simple expression
```bash
hs2 -c '2 + 2'
```
**Result**: Command hangs indefinitely, no output

### Test 3: Debug logging
- Added extensive debug logging to both Swift and JavaScript code
- Logging to /tmp/hs-ipc-debug.log from sendMessage()
- **Finding**: Log file was NEVER created, meaning sendMessage() was never called

## Key Findings

1. **Registration works**: The hs2 client successfully registers with Hammerspoon 2
2. **Command message sent**: The COMMAND message is successfully sent to server
3. **Server receives command**: The IPC handler receives the COMMAND (based on code flow)
4. **sendMessage never called**: The OUTPUT/RETURN messages are never sent back to client

## Hypothesis

The JavaScript code execution in the COMMAND handler is either:
1. Failing silently without calling print()
2. Not executing at all
3. Executing but the print() function is not the expected instance.print

## Code Architecture

### Message Flow (Expected)
1. Client sends MSGID_COMMAND with code
2. Server receives in `hs.ipc.__defaultHandler`
3. Handler parses instanceID and code
4. Handler retrieves instance from `hs.ipc.__registeredCLIInstances[instanceID]`
5. Handler creates Function with `_cli` and `print` parameters
6. Handler executes: `fn(instance._cli, instance.print)`
7. Code calls `print("hello world")`
8. instance.print() calls `instance._cli.remote.sendMessage(output, MSG_ID.OUTPUT, ...)`
9. Client receives OUTPUT message
10. Handler returns "ok"
11. Client receives "ok" and exits

### Actual Flow (Observed)
1-3. ✅ Working
4-6. ❓ Unknown (no logging visible)
7. ❌ Never happens (no sendMessage call)
8-11. ❌ Never reached

## Deadlock Analysis

Initially suspected a deadlock where:
- Client blocks waiting for COMMAND response
- Server sends OUTPUT during command execution
- Client can't receive OUTPUT while blocked
- Server times out waiting for OUTPUT ack

**Fix Applied**: Changed OUTPUT/RETURN messages to oneWay=true (no ack expected)
**Result**: Still hangs, so this wasn't the issue

## Debug Logging Added

### In hs.ipc.js
- `console.log("[DEBUG] Executing code for instance ...")`
- `console.log("[DEBUG] Instance print called for ...")`
- `console.log("[DEBUG] Sending message via remote port...")`

**Problem**: These logs only visible in Hammerspoon Console window, not accessible from command line

### In HSMessagePort.swift
- File logging to `/tmp/hs-ipc-debug.log`
- Logs every sendMessage() call with parameters
- Logs CFMessagePortSendRequest result codes

**Finding**: Log file never created = sendMessage() never called

### In HSClient.swift
- stderr logging when messages received
- Debug output for each message type
- Quiet mode detection

**Finding**: No debug output = callback never called

## Current Status

**Blocking Issue**: JavaScript code execution in COMMAND handler appears to not be working

**Next Steps Required**:
1. Verify JavaScript code execution is actually happening
2. Check if there are JavaScript errors during execution
3. Verify `instance.print` function is correctly defined
4. Check if the Function() constructor is working as expected
5. Access Hammerspoon Console window to see JavaScript debug logs

## Files Modified for Debugging

1. `/Users/dmg/.config/Hammerspoon2/init.js`
   - Added debug logging for IPC module loading
   - Added print() override with debug logging

2. `/Users/dmg/git.w/hs2/Hammerspoon2/Hammerspoon 2/Modules/hs.ipc/hs.ipc.js`
   - Changed OUTPUT/RETURN/ERROR messages to oneWay=true
   - Added extensive debug console.log() calls throughout

3. `/Users/dmg/git.w/hs2/Hammerspoon2/Hammerspoon 2/Modules/hs.ipc/HSMessagePort.swift`
   - Added file logging extension
   - Added logging to every step of sendMessage()

4. `/Users/dmg/git.w/hs2/Hammerspoon2/hs2/HSClient.swift`
   - Added stderr debug logging in callback
   - Added quiet mode detection logging

## Recommendations

### Immediate Actions
1. **Open Hammerspoon Console**: Check the JavaScript console.log debug output to see:
   - If "Executing code for instance..." appears
   - If "Instance print called..." appears
   - What error messages (if any) are shown

2. **Test in Console REPL**: Try executing code directly in Hammerspoon Console:
   ```javascript
   const testInstance = hs.ipc.__registeredCLIInstances[Object.keys(hs.ipc.__registeredCLIInstances)[0]];
   if (testInstance) {
       testInstance.print("TEST");
   }
   ```

3. **Verify IPC Handler**: In Console REPL:
   ```javascript
   // Check if default handler exists
   typeof hs.ipc.__defaultHandler

   // Check registered instances
   Object.keys(hs.ipc.__registeredCLIInstances)
   ```

### Potential Fixes

1. **If print() is not being called**: The issue is in code execution
   - Check for JavaScript syntax errors
   - Verify Function() constructor works with current JSContext

2. **If print() is being called but sendMessage fails**: The issue is in IPC
   - Check remote port creation
   - Verify port names match
   - Check for port invalidation

3. **If sendMessage succeeds but client doesn't receive**: The issue is in message delivery
   - Verify client run loop is running
   - Check for CFMessage Port issues
   - Verify callback is properly registered

## Technical Details

### CFMessagePort Error Codes
- `kCFMessagePortSuccess` (0): Success
- `kCFMessagePortSendTimeout` (-1): Send timed out
- `kCFMessagePortReceiveTimeout` (-2): Receive timed out
- `kCFMessagePortIsInvalid` (-3): Port is invalid
- `kCFMessagePortTransportError` (-4): Transport layer error
- `kCFMessagePortBecameInvalidError` (-5): Port became invalid during send

### Message IDs Used
```javascript
REGISTER: 100
UNREGISTER: 200
COMMAND: 500
QUERY: 501
OUTPUT: 1
RETURN: 2
CONSOLE: 3
ERROR: -1
```

## Conclusion

The IPC infrastructure appears sound (registration works, ports connect), but JavaScript code execution in the COMMAND handler is not producing expected results. The user needs to:

1. **Check the Hammerspoon Console** to see JavaScript debug logs
2. **Verify code execution** is happening
3. **Test instance.print()** directly in Console REPL

Once we can see the JavaScript debug logs, the root cause should become clear.
