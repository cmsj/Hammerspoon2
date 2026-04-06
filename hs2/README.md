# hs2 - Hammerspoon 2 Command-Line Tool

The `hs2` command-line tool provides terminal access to a running Hammerspoon 2 instance via IPC (Inter-Process Communication).

## Overview

`hs2` uses CFMessagePort for bidirectional communication with Hammerspoon 2, enabling:
- Remote code execution from the terminal
- Interactive REPL mode
- Script automation
- Console output mirroring

## Architecture

### IPC Protocol

Communication between `hs2` (client) and Hammerspoon 2 (server) uses a CFMessagePort-based protocol:

1. **Client Initialization**
   - Creates unique UUID-based local port for receiving messages
   - Connects to server's "Hammerspoon2" port
   - Sends REGISTER message with configuration

2. **Server Registration** (`hs.ipc.js`)
   - Creates remote port to connect back to client's UUID
   - Stores port in `__remotePorts` to prevent garbage collection
   - Stores instance data in `__registeredCLIInstances`

3. **Command Execution**
   - Client sends COMMAND message with code
   - Server executes code with instance-specific context
   - Results/errors sent back via client's port

4. **Cleanup**
   - Client sends UNREGISTER message on exit
   - Server deletes remote port and instance data
   - Client invalidates local port

### Memory Management

**Critical Implementation Detail**: The server uses `Unmanaged.passUnretained()` with retain/release callbacks for CFMessagePort contexts to prevent premature deallocation while ensuring proper cleanup.

**Resource Leak Fix (2025-12-28)**: The UNREGISTER handler now properly cleans up both `__registeredCLIInstances` AND `__remotePorts` to prevent accumulation of dead port objects.

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

- **Exit code 0**: All commands executed successfully
- **Exit code 65 (EX_DATAERR)**: JavaScript evaluation error (all commands still execute in multi-command mode)
- **Exit code 69 (EX_UNAVAILABLE)**: Cannot connect to Hammerspoon

JavaScript errors are also reported on stderr.

## Known Limitations

### Message Port Limits

macOS imposes system limits on the number of message ports a process can create (~32-64 ports). Rapid-fire invocations of hs2 can hit these limits.

**Symptoms**:
- "Registration failed" errors after ~30-40 rapid invocations
- Temporary until Hammerspoon 2 is restarted

**Mitigation**:
- Tests use 0.2s delays between invocations (realistic usage)
- Normal usage patterns (human-driven commands, scripts with reasonable delays) won't hit limits
- If automation requires many rapid invocations, add small delays (50-200ms) between calls

**Not a Bug**: This is expected behavior given macOS kernel limits. The cleanup code is correct; the ports simply take time to be reclaimed by the kernel.

## Testing

Comprehensive test infrastructure in `scripts/test-hs2.sh`:
- Basic functionality tests
- Error handling tests
- Test fixtures (JavaScript files)
- Stress tests (20 sequential commands with delays)

Run tests:
```bash
export BUILD_DIR="/path/to/build/products"
./scripts/test-hs2.sh
```

See `Hammerspoon 2Tests/HS2-TESTING-GUIDE.md` for complete testing documentation.

### Example: Window Listing Script

A practical example demonstrating the hs.window API:

```javascript
// test-window.js - List all windows with details
print("=== Testing hs.window API ===");
print("");

// Try focused window
var focused = hs.window.focusedWindow();
print("Focused window: " + (focused ? focused.title : "none"));
print("");

// Get all windows
var windows = hs.window.allWindows();
print("Total windows: " + windows.length);
print("");

// Show first 5 windows
for (var i = 0; i < Math.min(5, windows.length); i++) {
    var win = windows[i];
    print("Window " + (i+1) + ":");
    print("  Title: " + win.title);
    print("  App: " + win.application.title);
    var frame = win.frame;
    print("  Position: (" + Math.round(frame.x) + ", " + Math.round(frame.y) + ")");
    print("  Size: " + Math.round(frame.w) + "x" + Math.round(frame.h));
    print("");
}
```

Run it:
```bash
hs2 test-window.js
```

**Note**: Window properties (`title`, `application`, `frame`) are accessed as properties, not methods.

## Implementation Files

- `hs2/main.swift` - Entry point, argument parsing
- `hs2/HSClient.swift` - IPC client thread, message port management
- `hs2/HSInteractiveREPL.swift` - Interactive mode implementation
- `Hammerspoon 2/Modules/hs.ipc/hs.ipc.js` - Server-side protocol handler
- `Hammerspoon 2/Modules/hs.ipc/HSMessagePort.swift` - CFMessagePort wrapper

## Debugging

Diagnostics and troubleshooting:
```bash
# IPC errors and JS exceptions are reported on stderr
hs2 -c "print('test')" 2>/tmp/hs2-errors.log

# Use -C to mirror Hammerspoon 2 console output to terminal
hs2 -C -c "console.log('debug info')"

# Server-side logging
# Open Hammerspoon 2 Console to see [IPC] messages
```

## Future Enhancements

Potential improvements:
- Connection pooling to reuse ports
- Port cleanup scheduling to force kernel reclamation
- Alternative IPC mechanisms (XPC, sockets) for high-volume usage
- Command history persistence (currently in-session only)
- Enhanced tab completion

## Related Documentation

- `Hammerspoon 2Tests/HS2-TESTING-GUIDE.md` - Complete testing guide
- `docs/IPC.md` - IPC module documentation
- `claude.md` - Developer guide (includes hs.ipc section)
