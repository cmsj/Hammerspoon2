# Hammerspoon 2 IPC Protocol Documentation

## Overview

The Hammerspoon 2 IPC (Inter-Process Communication) system enables external processes to communicate with a running Hammerspoon 2 instance via CFMessagePort. This document provides comprehensive documentation of the protocol, API, and implementation details.

## Protocol Version

Current protocol version: **2.0**

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  External Process                   │
│                  (hs2 CLI, scripts)                 │
└──────────────────┬──────────────────────────────────┘
                   │ CFMessagePort IPC
                   │
┌──────────────────▼──────────────────────────────────┐
│            Hammerspoon 2 Main Process               │
│  ┌───────────────────────────────────────────────┐  │
│  │          hs.ipc Module (Swift)                │  │
│  │  • HSMessagePort wrapper                      │  │
│  │  • Port management                            │  │
│  │  • CLI installation                           │  │
│  └──────────────┬────────────────────────────────┘  │
│                 │                                    │
│  ┌──────────────▼────────────────────────────────┐  │
│  │       hs.ipc.js (JavaScript)                  │  │
│  │  • Protocol handler                           │  │
│  │  • Instance management                        │  │
│  │  • Code execution                             │  │
│  └──────────────┬────────────────────────────────┘  │
│                 │                                    │
│  ┌──────────────▼────────────────────────────────┐  │
│  │      JavaScript Engine (JavaScriptCore)       │  │
│  │  • User code execution                        │  │
│  │  • Module access                              │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Message Port System

### Port Names

- **Default Hammerspoon 2 Port**: `Hammerspoon2`
  - Created automatically when hs.ipc module loads
  - Handles CLI communication protocol
- **CLI Instance Ports**: UUID-based (e.g., `12345678-1234-1234-1234-123456789012`)
  - One per connected CLI instance
  - Used for bidirectional communication

### Port Types

#### Local (Server) Ports
- Created via `hs.ipc.localPort(name, callback)`
- Listen for incoming messages
- Invoke JavaScript callback on message receipt
- Can send responses back to caller

#### Remote (Client) Ports
- Created via `hs.ipc.remotePort(name)`
- Connect to existing local port
- Send messages without receiving
- Used for one-way communication

## IPC Protocol

### Message IDs

| ID   | Name       | Direction | Description                          |
|------|------------|-----------|--------------------------------------|
| 100  | REGISTER   | CLI → HS2 | Register new CLI instance            |
| 200  | UNREGISTER | CLI → HS2 | Unregister CLI instance              |
| 500  | COMMAND    | CLI → HS2 | Execute JavaScript code              |
| 501  | QUERY      | CLI → HS2 | Execute code and return value        |
| -1   | ERROR      | HS2 → CLI | Error message                        |
| 1    | OUTPUT     | HS2 → CLI | Standard output                      |
| 2    | RETURN     | HS2 → CLI | Return value from command            |
| 3    | CONSOLE    | HS2 → CLI | Console output (mirroring)           |

### Message Format

#### REGISTER (msgID=100)
**Request**:
```
instanceID\0{JSON}
```

Where JSON contains:
```json
{
  "quiet": boolean,
  "console": boolean,
  "customArgs": [string, ...]
}
```

**Response**:
```
"ok"
```

#### UNREGISTER (msgID=200)
**Request**:
```
instanceID
```

**Response**: None (one-way message)

#### COMMAND (msgID=500)
**Request**:
```
instanceID\0code
```

**Response**:
```
"ok" | "error"
```

Output sent via OUTPUT (1) and RETURN (2) messages.

#### QUERY (msgID=501)
**Request**:
```
instanceID\0code
```

**Response**:
```
result (as string)
```

Direct return value, no OUTPUT messages.

#### ERROR (msgID=-1)
**Sent from Hammerspoon 2 to CLI**:
```
error message\n
```

#### OUTPUT (msgID=1)
**Sent from Hammerspoon 2 to CLI**:
```
output text\n
```

#### RETURN (msgID=2)
**Sent from Hammerspoon 2 to CLI**:
```
return value\n
```

#### CONSOLE (msgID=3)
**Sent from Hammerspoon 2 to CLI** (if console mirroring enabled):
```
console output\n
```

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

## JavaScript Execution Context

### Instance Isolation

Each CLI connection gets an isolated execution environment with:

- **`_cli` object**: Instance-specific metadata
  ```javascript
  _cli = {
    remote: HSMessagePort,  // Port for communication back to CLI
    quietMode: boolean,     // Quiet mode flag
    console: boolean,       // Console mirroring flag
    args: [string, ...]     // Custom arguments from CLI
  }
  ```

- **`print()` function**: Instance-specific output
  ```javascript
  print(...args) {
    // Formats and sends to CLI via OUTPUT message
  }
  ```

### Shared Global Scope

All CLI instances share the same global JavaScript context:
- Access to all `hs.*` modules
- Access to global variables
- Modifications to globals affect all instances

### Code Execution Pattern

```javascript
// Execution uses Function constructor with parameters
let fn = new Function('_cli', 'print', code);
result = fn(instance._cli, instance.print);
```

This ensures `_cli` and `print` are scoped to the function, not global.

## CLI Tool (hs2)

### Command-Line Arguments

```bash
hs2 [options] [file] [-- arguments]
```

#### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-a arg` | Pass argument to script (appended to `_cli.args`) | - |
| `-i` | Force interactive mode (REPL) | Auto-detect |
| `-s` | Read from stdin | Auto-detect |
| `-c code` | Execute code (repeatable) | - |
| `-m name` | Connect to custom port | "Hammerspoon2" |
| `-n` | Disable colors | Auto-detect |
| `-N` | Force colors | Auto-detect |
| `-C` | Enable console mirroring | Disabled |
| `-q` | Quiet mode | Disabled |
| `-t seconds` | Set timeout | 4.0 |
| `-h` | Display help | - |
| `--` | Stop parsing, rest goes to `_cli.args` | - |

### Exit Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | EX_OK | Success (IPC communication succeeded, even if user code had errors) |
| 64 | EX_USAGE | Invalid arguments |
| 65 | EX_DATAERR | IPC protocol/communication error |
| 66 | EX_NOINPUT | Error reading stdin/file |
| 69 | EX_UNAVAILABLE | Hammerspoon 2 not reachable |
| 75 | EX_TEMPFAIL | Temporary failure (e.g., startup) |

### Interactive REPL

Features:
- Line editing via libedit (BSD licensed)
- In-session command history (up/down arrows)
- Tab completion for `hs.*` module names
- Color-coded output
- Single-line execution
- Exit with Ctrl-D

## API Reference

### hs.ipc Module

#### `hs.ipc.localPort(name, callback) → HSMessagePort | null`

Create a local (server) message port.

**Parameters**:
- `name` (string): Port name (must be unique system-wide)
- `callback` (function): `function(port, msgID, data) → response`

**Returns**: HSMessagePort object or null on failure

**Example**:
```javascript
const port = hs.ipc.localPort("MyService", function(port, msgID, data) {
    console.log("Received:", data);
    return "Response";
});
```

#### `hs.ipc.remotePort(name) → HSMessagePort | null`

Create a remote (client) message port connection.

**Parameters**:
- `name` (string): Port name to connect to

**Returns**: HSMessagePort object or null if port doesn't exist

**Example**:
```javascript
const remote = hs.ipc.remotePort("MyService");
remote.sendMessage("Hello", 0);
```

#### `hs.ipc.cliInstall([path], [silent]) → boolean`

Install hs2 CLI tool via symlinks.

**Parameters**:
- `path` (string, optional): Installation prefix (default: "/usr/local")
- `silent` (boolean, optional): Suppress log output (default: false)

**Returns**: true on success, false on failure

**Creates**:
- `{path}/bin/hs2` → Binary symlink
- `{path}/share/man/man1/hs2.1` → Man page symlink

**Example**:
```javascript
hs.ipc.cliInstall("/usr/local");
```

#### `hs.ipc.cliUninstall([path], [silent]) → boolean`

Remove hs2 CLI tool symlinks.

**Parameters**:
- `path` (string, optional): Installation prefix (default: "/usr/local")
- `silent` (boolean, optional): Suppress log output (default: false)

**Returns**: true on success, false on failure

**Example**:
```javascript
hs.ipc.cliUninstall("/usr/local");
```

#### `hs.ipc.cliStatus([path], [silent]) → boolean`

Check hs2 CLI tool installation status.

**Parameters**:
- `path` (string, optional): Installation prefix (default: "/usr/local")
- `silent` (boolean, optional): Suppress log output (default: false)

**Returns**: true if installed, false otherwise

**Example**:
```javascript
if (hs.ipc.cliStatus("/usr/local")) {
    console.log("hs2 is installed");
}
```

### HSMessagePort Object

#### Properties

- `name` (string, read-only): Port name
- `isValid` (boolean, read-only): Port validity
- `isRemote` (boolean, read-only): true for remote ports, false for local

#### Methods

##### `sendMessage(data, msgID, [timeout], [oneWay]) → response | boolean`

Send a message to the port.

**Parameters**:
- `data` (string): Message data
- `msgID` (number): Message ID
- `timeout` (number, optional): Timeout in seconds (default: 4.0)
- `oneWay` (boolean, optional): No response expected (default: false)

**Returns**: Response string (if oneWay=false) or boolean success

**Example**:
```javascript
const response = remote.sendMessage("request", 100, 2.0, false);
```

##### `delete()`

Invalidate and cleanup the port.

**Example**:
```javascript
port.delete();
```

## Security Considerations

### Local-Only Communication

CFMessagePort is **local-only** - no network exposure. Communication is restricted to processes on the same machine.

### Global Port Namespace

Port names are **system-wide**. Any process can:
- Connect to a named port
- Send messages to it

**Implications**:
- Do not rely on port names for authentication
- Do not expose sensitive operations via IPC without additional security
- Consider the local user as the trust boundary

### Code Execution

The IPC protocol allows **arbitrary JavaScript execution** in the Hammerspoon 2 context. This is intentional for CLI functionality but means:
- Any process that can connect to the port can execute code
- Code runs with full Hammerspoon 2 privileges
- No sandboxing or isolation from main app

**Mitigation**:
- Default port only accepts connections from local user
- Consider custom authentication for sensitive IPC services
- Use firewall/security software if concerned about local processes

### Sandboxing Compatibility

CFMessagePort works within App Sandbox but may require entitlements:
- `com.apple.security.temporary-exception.mach-lookup.global-name`
- Test thoroughly if app is sandboxed

## Performance Characteristics

### Synchronous Communication

CFMessagePort is **synchronous** - sending with response blocks until:
- Response received
- Timeout expired
- Port invalidated

**Recommendations**:
- Use appropriate timeouts for expected operation duration
- Consider one-way messages for fire-and-forget operations
- Avoid long-running operations in IPC handlers

### Message Size Limits

CFMessagePort has practical limits (~1MB). For large data:
- Chunk data into multiple messages
- Use alternative IPC mechanisms (pipes, sockets)
- Consider file-based exchange

### Thread Safety

**HSMessagePort**: Marked with `@MainActor` - all operations run on main thread (required for JavaScriptCore).

**CLI Tool**: Dedicated thread for CFMessagePort operations, callbacks marshaled to main thread for JavaScript execution.

## Troubleshooting

### Port Already in Use

**Error**: `Failed to create local message port`

**Cause**: Another process is using the port name.

**Solutions**:
- Choose a unique port name
- Check for other Hammerspoon 2 instances
- Use `lsof | grep CFMessagePort` (limited visibility)

### Connection Timeout

**Error**: `Could not connect to Hammerspoon 2`

**Causes**:
- Hammerspoon 2 not running
- IPC module not loaded
- Port name mismatch

**Solutions**:
- Verify Hammerspoon 2 is running: `ps aux | grep Hammerspoon`
- Check port name (default: "Hammerspoon2")
- Check Console.app for IPC errors

### Invalid Port

**Error**: Port becomes invalid during operation

**Causes**:
- Remote port closed/invalidated
- Hammerspoon 2 reloaded config
- JavaScript error in port callback

**Solutions**:
- Implement reconnection logic in client
- Check JavaScript console for errors
- Ensure callback doesn't throw exceptions

### JavaScript Errors

**Error**: Code execution fails in CLI

**Causes**:
- Syntax errors in code
- Undefined variables/functions
- Module not loaded

**Solutions**:
- Test code in Hammerspoon 2 Console first
- Use `-C` flag to see console output
- Check that required modules are loaded
- Use try/catch for error handling

## Known Issues and Limitations

### Resource Leak Fix (2025-12-28)

**Issue**: UNREGISTER messages were only cleaning up `__registeredCLIInstances` but not `__remotePorts`, causing accumulation of dead port objects and eventual "Registration failed" errors.

**Fix**: Updated `hs.ipc.js` UNREGISTER handler to properly clean up both storage objects:

```javascript
// Clean up remote port storage to prevent resource leak
if (hs.ipc.__remotePorts && hs.ipc.__remotePorts[instanceID]) {
    delete hs.ipc.__remotePorts[instanceID];
}
```

**Impact**: Previously, rapid-fire hs2 invocations would fail after ~30 commands. With the fix, cleanup is complete but macOS kernel limits still apply (see below).

### Message Port Limits

macOS imposes system limits on the number of message ports per process (~32-64 concurrent ports). Even with proper cleanup, rapid-fire invocations can hit these limits because kernel port reclamation isn't instantaneous.

**Symptoms**:
- "Registration failed" errors after ~35-40 rapid invocations (no delays)
- Error occurs when `CFMessagePortCreateLocal()` returns nil in client
- Temporary - ports are eventually reclaimed by kernel
- Restarting Hammerspoon 2 immediately clears all ports

**Root Cause**:
- Each hs2 invocation creates a UUID-based local port for bidirectional communication
- Port cleanup happens via `CFMessagePortInvalidate()` but kernel reclamation takes time
- Rapid invocations create ports faster than kernel can reclaim them

**Not a Bug**: This is expected behavior given macOS kernel constraints. The cleanup code is correct; the issue is timing between port creation and kernel reclamation.

**Mitigation Strategies**:

1. **Add Delays in Scripts** (Recommended):
   ```bash
   for i in {1..100}; do
       hs2 -c "doSomething()"
       sleep 0.2  # 200ms delay allows kernel cleanup
   done
   ```

2. **Batch Operations**:
   ```bash
   # Instead of multiple hs2 calls
   hs2 -c "for(i=0; i<100; i++) doSomething(i)"
   ```

3. **Use Files**:
   ```javascript
   // script.js
   for (let i = 0; i < 100; i++) {
       doSomething(i);
   }
   ```
   ```bash
   hs2 script.js  # Single invocation
   ```

4. **Interactive Mode**:
   ```bash
   hs2 -i  # REPL mode - single connection for many commands
   ```

**Test Infrastructure**: The test suite uses 0.2s delays between commands, which reflects realistic usage patterns and ensures reliable testing.

## Best Practices

### Port Naming

- Use reverse-domain notation: `com.mycompany.service`
- Include app/service name for clarity
- Avoid generic names like "IPC" or "Service"

### Error Handling

```javascript
hs.ipc.localPort("MyService", function(port, msgID, data) {
    try {
        // Handle message
        return "ok";
    } catch (e) {
        console.error("Error in IPC handler:", e);
        return "error: " + String(e);
    }
});
```

### Cleanup

```javascript
// Store reference
var myPort = hs.ipc.localPort("MyService", handler);

// Later, in shutdown or reload handler
if (myPort) {
    myPort.delete();
    myPort = null;
}
```

### CLI Integration

```bash
#!/bin/bash
# Example: Window management script

hs2 -c "
var win = hs.window.focusedWindow();
if (win) {
    var screen = win.screen().frame();
    win.setFrame({x: 0, y: 0, w: screen.w/2, h: screen.h});
}
"
```

## Future Enhancements (v2.0+)

Planned features not in v1.0:

- **Persistent History**: Save REPL history across sessions
- **Color Configuration**: UserDefaults-based color customization
- **Advanced Completion**: Deep property/method completion
- **Legacy V1 Protocol**: Compatibility with original Hammerspoon IPC
- **Authentication**: Optional authentication for IPC services
- **Streaming API**: Support for large data transfers
- **Network IPC**: Optional network-based communication
- **Multi-Instance**: Support for multiple Hammerspoon 2 instances

## JSExport GC and State Persistence

### The Problem

JavaScriptCore's garbage collector periodically reclaims and recreates JSExport proxy wrapper objects. When this happens, any JavaScript properties dynamically assigned to the proxy are lost. For example:

```javascript
// This DOES NOT survive GC:
hs.ipc.__registeredCLIInstances = {};   // lost when proxy wrapper is recreated
hs.ipc.__remotePorts = {};              // lost when proxy wrapper is recreated
```

This caused IPC registration loss after idle periods: the GC would reclaim the `hs.ipc` proxy, and all registered CLI instances would silently disappear. The next `hs2` command would get "instance not registered".

### Two Solutions

There are two valid approaches to making state survive JSExport proxy GC. Hammerspoon 2 uses both, in different modules.

#### Approach 1: Closure-scoped JS variables (used by hs.ipc)

Move state out of the JSExport proxy entirely, into module-level JavaScript variables:

```javascript
// hs.ipc.js — state lives in JS closure scope, NOT on the proxy
var __ipcRegisteredInstances = {};
var __ipcRemotePorts = {};
var __ipcDefaultHandler = function(port, msgID, data) {
    // accesses __ipcRegisteredInstances directly
};
```

The GC can reclaim and recreate the `hs.ipc` proxy freely — the closure-scoped variables are unaffected.

**When to use**: Complex state (nested objects, closures, port references) that would be awkward to model as `@objc` protocol properties.

#### Approach 2: JSExport protocol properties backed by Swift storage (used by hs.task)

Declare the properties in the `JSExport` protocol with `get set`, backed by Swift stored properties:

```swift
@objc protocol HSTaskModuleAPI: JSExport {
    @objc var runAsync: JSValue? { get set }   // declared in protocol
    @objc var shell: JSValue? { get set }
}

@objc class HSTaskModule: NSObject, HSTaskModuleAPI {
    @objc var runAsync: JSValue? = nil   // Swift-backed storage
    @objc var shell: JSValue? = nil
}
```

When JavaScript assigns `hs.task.runAsync = function() {...}`, JSC routes through the `@objc` setter, storing the `JSValue` in **Swift memory**. The GC can reclaim the JS wrapper — the Swift instance and its properties remain intact.

**When to use**: Storing JS functions or values that map naturally to `JSValue?` properties on the module.

### Comparison

| | Closure-scoped JS vars | JSExport protocol properties |
|---|---|---|
| **Where state lives** | JS global scope | Swift stored properties |
| **GC resilience** | Not on proxy at all | Swift memory, invisible to GC |
| **Protocol changes** | None | Properties added to JSExport protocol |
| **Thread safety** | N/A (JS is single-threaded) | Must handle actor isolation |
| **Best for** | Complex mutable state, dictionaries | JS functions, simple values |
| **Used by** | `hs.ipc` | `hs.task` |

### Auto-Reconnect

As a defense-in-depth measure, the `hs2` CLI also implements auto-reconnect. If a command gets "instance not registered" (e.g., due to an edge case or future regression), it transparently re-registers and retries:

```swift
// HSClient.swift
if responseStr.contains("instance not registered") {
    if registerWithRemote() {
        return executeCommand(command)  // retry after re-registering
    }
}
```

## References

- [CFMessagePort Documentation](https://developer.apple.com/documentation/corefoundation/cfmessageport)
- [libedit (editline) Documentation](https://www.thrysoee.dk/editline/)
- [Original Hammerspoon IPC](https://github.com/Hammerspoon/hammerspoon/tree/master/extensions/ipc)
- [JavaScriptCore Documentation](https://developer.apple.com/documentation/javascriptcore)
