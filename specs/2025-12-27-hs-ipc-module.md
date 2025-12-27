# Feature: hs.ipc Module and hs2 Command-Line Tool

**Revision**: 2025-12-27 - Verified and simplified for v1.0 implementation
**Status**: READY FOR IMPLEMENTATION (verified 2025-12-27)
- Removed: Settings UI, CLI E2E tests, Legacy V1 protocol support, UserDefaults configuration (colors/history)
- Simplified: Tab completion (minimal), integration tests (basic only), REPL (no persistence)
- Updated: JavaScript execution context (Option B - Shared with Scoping), thread safety (@MainActor)
- Threading: Use @MainActor, direct JS invocation (no async dispatch)
- Bundle ID: Extract dynamically via Bundle.main.bundleIdentifier
- REPL: Use libedit (BSD licensed, not GNU readline)

## Chore Description

Implement the `hs.ipc` module for inter-process communication (IPC) between Hammerspoon 2 and external processes, along with a command-line tool named `hs2` that enables users to execute JavaScript code, interact with Hammerspoon 2 from shell scripts, and access an interactive REPL from the terminal.

This feature provides:

1. **hs.ipc Module**: A Swift/JavaScript module that creates and manages CFMessagePort-based IPC channels for bidirectional communication
2. **hs2 CLI Tool**: A standalone command-line executable that connects to Hammerspoon 2 via IPC to execute code, retrieve results, and provide an interactive JavaScript REPL
3. **Protocol Implementation**: Message-based protocol supporting command execution, output streaming, error handling, console mirroring, and tab completion
4. **Installation Management**: Functions to install/uninstall the CLI tool system-wide via symlinks

The implementation must maintain functional parity with the original Hammerspoon's `hs.ipc` and `hs` CLI tool, adapted for JavaScript instead of Lua.

### Ground Truth Reference

The original Hammerspoon implementation (located in `hs_repo_old/extensions/ipc/`) serves as the authoritative reference for behavior:

- **IPC Module**: `hs_repo_old/extensions/ipc/libipc.m` and `hs_repo_old/extensions/ipc/ipc.lua`
- **CLI Tool**: `hs_repo_old/extensions/ipc/cli/hs.m` and `hs_repo_old/extensions/ipc/cli/hs.man`

The original uses Lua as the scripting language; Hammerspoon 2 uses JavaScript. All Lua-specific behavior should be translated to JavaScript equivalents while maintaining the same IPC protocol and command-line interface.

## Relevant Files

### Existing Files to Modify

- **`Hammerspoon 2/Engine/ModuleRoot.swift`**
  - Add `@objc var ipc: HSIPCModule { get }` property to `ModuleRootAPI` protocol
  - Add lazy loading implementation for the IPC module in `ModuleRoot` class
  - Registers the module with the JavaScript `hs` namespace

- **`Hammerspoon 2/Engine/HSModuleAPI.swift`**
  - No modifications required (protocol already exists)
  - HSIPCModule will conform to this protocol

- **`Hammerspoon 2/Engine/JSEngine.swift`**
  - No modifications required for v1.0
  - IPC will use shared JavaScript context (Option B: Shared with Scoping)
  - Instance-specific `_cli` and `print` injected via function parameters

- **`Hammerspoon 2.xcodeproj/project.pbxproj`** (Xcode project file)
  - Add new source files to the project
  - Create a new command-line tool target for `hs2`
  - Configure build settings, linking, and dependencies

### New Files

#### Module Implementation (Swift)

- **`Hammerspoon 2/Modules/hs.ipc/IPCModule.swift`**
  - Defines `HSIPCModuleAPI` protocol (JSExport) with public API
  - Implements `HSIPCModule` class conforming to `HSModuleAPI`
  - Module-level functions:
    - `localPort(name, callback)` → Creates server message port
    - `remotePort(name)` → Creates client connection to remote port
    - `cliInstall([path], [silent])` → Install hs2 symlinks
    - `cliUninstall([path], [silent])` → Remove hs2 symlinks
    - `cliStatus([path], [silent])` → Check installation status
  - Manages default "Hammerspoon2" port
  - Handles shutdown cleanup
  - Note: CLI color/history configuration deferred to v2.0

- **`Hammerspoon 2/Modules/hs.ipc/HSMessagePort.swift`**
  - Defines `HSMessagePortAPI` protocol (JSExport) for message port objects
  - Implements `HSMessagePort` class wrapping CFMessagePort
  - Properties:
    - `name` → Port name string
    - `isValid` → Boolean validity check
    - `isRemote` → Boolean local vs remote distinction
  - Methods:
    - `sendMessage(data, msgID, [timeout], [oneWay])` → Send IPC message
    - `delete()` → Cleanup and invalidate port
  - Manages CFMessagePortRef lifecycle
  - Handles callback invocation from Swift to JavaScript
  - Implements CFMessagePort callback bridge

- **`Hammerspoon 2/Modules/hs.ipc/IPCProtocol.swift`**
  - Defines message ID constants as Swift enum:
    ```swift
    enum IPCMessageID: Int32 {
        case register = 100
        case unregister = 200
        case command = 500
        case query = 501
        case error = -1
        case output = 1
        case returnValue = 2
        case console = 3
    }
    ```
  - Protocol version constant: `"2.0"`
  - Message encoding format: `"instanceID\0payload"` for COMMAND/REGISTER/QUERY, plain payload for others
  - Helper functions for message encoding/decoding
  - Instance ID parsing and validation

- **`Hammerspoon 2/Modules/hs.ipc/hs.ipc.js`**
  - JavaScript companion file loaded with the module
  - Implements default message handler:
    - REGISTER (100): Parse instance ID and arguments, create instance object with isolated `_cli` and `print`
    - UNREGISTER (200): Cleanup instance
    - COMMAND (500): Execute code with instance-specific context (Option B: Function parameter injection)
    - QUERY (501): Execute code with query semantics
  - Manages registered CLI instances dictionary:
    ```javascript
    hs.ipc.__registeredCLIInstances = {};
    hs.ipc.__defaultHandler = function(port, msgID, data) { ... };
    ```
  - Execution pattern (Option B - Shared Context with Scoping):
    ```javascript
    // Instance-specific objects injected as function parameters
    let fn = new Function('_cli', 'print', code);
    result = fn(instance._cli, instance.print);
    // Global scope shared, _cli and print isolated per instance
    ```
  - Implements `print()` replacement for console mirroring to all connected CLIs
  - Creates default port: `hs.ipc.__default = hs.ipc.localPort("Hammerspoon2", hs.ipc.__defaultHandler)`
  - Helper functions for message parsing and response formatting

#### Command-Line Tool (Swift)

- **`hs2/main.swift`**
  - Entry point for hs2 command-line tool
  - Parses command-line arguments:
    - `-A` : Auto-launch Hammerspoon 2 if not running
    - `-a` : Exit with error if Hammerspoon 2 not running
    - `-i` : Force interactive mode
    - `-s` : Read from stdin
    - `-c code` : Execute code (can be repeated)
    - `-m name` : Connect to custom message port name (default: "Hammerspoon2")
    - `-n` : Disable colors
    - `-N` : Force colors
    - `-C` : Enable console mirroring
    - `-q` : Quiet mode (suppress output except errors)
    - `-t seconds` : Set timeout (default: 4.0)
    - `-h` : Display help
    - `--` : Stop parsing, treat remaining as custom arguments
    - `file` : Execute file contents
  - Detects pipe input (`!isatty(STDIN_FILENO)`)
  - Manages auto-launch workflow with user alerts
  - Delegates to `HSClient` for IPC operations
  - Handles exit codes (POSIX standard):
    - `EX_OK (0)`: Success
    - `EX_USAGE (64)`: Invalid arguments
    - `EX_DATAERR (65)`: JavaScript error in non-interactive mode
    - `EX_NOINPUT (66)`: Error reading stdin/file
    - `EX_UNAVAILABLE (69)`: Hammerspoon 2 not reachable
    - `EX_TEMPFAIL (75)`: Temporary failure during startup

- **`hs2/HSClient.swift`**
  - Thread subclass managing IPC client lifecycle
  - Properties:
    - `localPort`: CFMessagePortRef for receiving messages
    - `remotePort`: CFMessagePortRef for sending to Hammerspoon 2
    - `remoteName`: Target port name (default: "Hammerspoon2")
    - `localName`: UUID for this CLI instance
    - `sendTimeout`/`recvTimeout`: CFTimeInterval values
    - `colorBanner`, `colorInput`, `colorOutput`, `colorError`: ANSI escape codes
    - `useColors`: Boolean
    - `autoReconnect`: Boolean (for interactive mode)
    - `exitCode`: Int
  - Methods:
    - `main()`: Thread entry point, establishes connection
    - `registerWithRemote()`: Sends REGISTER message with instance ID and flags
    - `unregisterWithRemote()`: Sends UNREGISTER message
    - `executeCommand(_:)`: Sends COMMAND/QUERY message
    - `sendToRemote(_:msgID:wantResponse:error:)`: Low-level message sending
    - `localPortCallback()`: Static C function for CFMessagePort callback
  - Manages CFRunLoop for bidirectional communication
  - Routes received messages to stdout/stderr with color coding
  - **Thread Safety**: All CFMessagePort operations run on dedicated thread, callbacks marshalled to main thread for JavaScript execution

- **`hs2/HSInteractiveREPL.swift`**
  - Interactive REPL implementation using libedit
  - Properties:
    - `client`: Reference to HSClient
    - `historyFilePath`: URL to `~/.config/Hammerspoon2/.cli.history`
    - `historyLimit`: Max entries (from UserDefaults)
    - `saveHistory`: Persistence flag (from UserDefaults)
  - Methods:
    - `run()`: Main REPL loop
    - `setupReadline()`: Configure readline with tab completion
    - `loadHistory()`: Read history from file
    - `saveHistory()`: Write history to file
    - `completionFunction(_:state:)`: Tab completion callback
  - Tab completion via `hs.completionsForInputString()` query to Hammerspoon 2
  - Command history with persistent storage
  - Readline integration: `libedit`

- **`hs2/Resources/hs2.1`** (man page)
  - Manual page documentation for hs2 command
  - Based on `hs_repo_old/extensions/ipc/cli/hs.man`
  - Updated for Hammerspoon 2 and JavaScript
  - Sections:
    - NAME
    - SYNOPSIS
    - DESCRIPTION
    - OPTIONS
    - EXAMPLES
    - FILES
    - EXIT STATUS
    - SEE ALSO
    - AUTHORS

#### Supporting Files

- **`Hammerspoon 2/Modules/hs.ipc/Info.plist`** (if needed for resources)
  - Bundle metadata for IPC module

- **`Hammerspoon 2/Utilities/CFMessagePortExtensions.swift`**
  - Swift extensions for CFMessagePort convenience
  - Error type for CFMessagePort errors
  - Helper functions for timeout handling

#### Test Files

- **`Hammerspoon 2Tests/IntegrationTests/HSIPCIntegrationTests.swift`**
  - Test local and remote port creation
  - Test message sending/receiving
  - Test callback invocation
  - Test port validity and lifecycle
  - Test error conditions (timeout, invalid port, etc.)

- **`Hammerspoon 2Tests/IntegrationTests/HSIPCHS2CLITests.swift`**
  - Test CLI installation/uninstallation
  - Test CLI status checking
  - Test color configuration
  - Test history settings
  - Integration tests with actual hs2 binary (if feasible in test environment)

## Step by Step Tasks

### Step 1: Create IPC Module Foundation

- Create directory `Hammerspoon 2/Modules/hs.ipc/`
- Create `IPCProtocol.swift` defining message IDs and protocol constants
- Define `IPCMessageID` enum with message types (removed: `legacyCheck`, `legacy`):
  ```swift
  enum IPCMessageID: Int32 {
      case register = 100
      case unregister = 200
      case command = 500
      case query = 501
      case error = -1
      case output = 1
      case returnValue = 2
      case console = 3
  }
  ```
- Add protocol version constant `IPCProtocolVersion = "2.0"`
- Document message encoding format:
  - REGISTER/COMMAND/QUERY: `"instanceID\0payload"` (null-delimited)
  - Other messages: Plain payload
  - Use UTF-8 encoding throughout
- Create helper functions for message encoding/decoding:
  - `encodeMessage(instanceID: String?, payload: String) -> Data`
  - `decodeMessage(data: Data) -> (instanceID: String?, payload: String)`
- Add unit tests for protocol encoding/decoding

### Step 2: Implement Message Port Wrapper

- Create `HSMessagePort.swift`
- **Mark class with `@MainActor`** to ensure all operations run on main thread (required for JavaScriptCore)
- **Threading Model**: Port created on main thread, callbacks execute on main thread, direct JavaScript invocation (no async dispatch needed)
- Define `HSMessagePortAPI` protocol conforming to `JSExport`:
  - `@objc var name: String { get }`
  - `@objc var isValid: Bool { get }`
  - `@objc var isRemote: Bool { get }`
  - `@objc func sendMessage(_ data: JSValue, _ msgID: NSNumber, _ timeout: NSNumber?, _ oneWay: Bool) -> JSValue`
  - `@objc func delete()`
- Implement `HSMessagePort` class conforming to `HSTypeAPI` and `HSMessagePortAPI`
- Add properties:
  - `messagePort: CFMessagePortRef?`
  - `callbackRef: JSValue?` (JavaScript function)
  - `selfRef: JSValue?` (for keeping port alive)
  - `runLoopSource: CFRunLoopSourceRef?`
- Implement initializers:
  - `init(localPortName: String, callback: JSValue)` for server ports
  - `init(remotePortName: String)` for client ports
  - Create ports on main thread and add to `CFRunLoopGetMain()`
- Implement CFMessagePort callback bridge:
  - Static C function `messagePortCallback(_:_:_:_:) -> CFDataRef?`
  - **Direct JavaScript callback invocation** (already on main thread due to @MainActor and CFRunLoopGetMain())
  - Converts CFDataRef to JSValue and invokes JavaScript callback
  - Returns response as CFDataRef
  - Note: No DispatchQueue.main.async needed - port created on main thread with @MainActor ensures callbacks execute on main thread
- Add recursive call depth protection (max 5 levels)
- Implement `sendMessage()` with CFMessagePortSendRequest
- Handle timeout conversion and error reporting
- Implement `delete()` for cleanup:
  - Invalidate message port
  - Remove from run loop
  - Release CFMessagePortRef
- Add `deinit` with logging

### Step 3: Implement IPC Module

- Create `IPCModule.swift`
- Define `HSIPCModuleAPI` protocol conforming to `JSExport`:
  - `@objc func localPort(_ name: String, _ callback: JSValue) -> HSMessagePort`
  - `@objc func remotePort(_ name: String) -> HSMessagePort`
  - `@objc func cliInstall(_ path: String?, _ silent: Bool) -> Bool`
  - `@objc func cliUninstall(_ path: String?, _ silent: Bool) -> Bool`
  - `@objc func cliStatus(_ path: String?, _ silent: Bool) -> Bool`
  - Note: cliColors, cliSaveHistory, cliSaveHistorySize deferred to v2.0
- Implement `HSIPCModule` class conforming to `HSModuleAPI` and `HSIPCModuleAPI`
- Add property: `var name = "hs.ipc"`
- Implement `localPort()`:
  - Create HSMessagePort with local port
  - Add to main run loop
  - Return port object
- Implement `remotePort()`:
  - Create HSMessagePort with remote port
  - Return port object
- Implement CLI installation functions:
  - `cliInstall()`: Create symlinks in specified path (default `/usr/local`)
    - Symlink for binary: `/usr/local/bin/hs2` → `{bundle}/Contents/Frameworks/hs2/hs2`
    - Symlink for man page: `/usr/local/share/man/man1/hs2.1` → `{bundle}/Contents/Resources/man/hs2.1`
    - Check for existing files and prompt/error appropriately
    - Use `FileManager.createSymbolicLink()`
    - Log results unless silent mode
  - `cliUninstall()`: Remove symlinks
    - Check if symlinks point to current bundle
    - Remove only if valid
    - Log results unless silent mode
  - `cliStatus()`: Check installation
    - Verify symlinks exist and point to current bundle
    - Return Boolean status
    - Log results unless silent mode
- Implement `shutdown()`:
  - Cleanup any active ports (if tracked)
  - No default port cleanup needed (handled by JavaScript layer)
- Add error handling with `HammerspoonError`
- **Mark class with `@MainActor`** for thread safety

### Step 4: Create JavaScript Protocol Handler

- Create `Hammerspoon 2/Modules/hs.ipc/hs.ipc.js`
- Define message ID constants (must match IPCProtocol.swift):
  ```javascript
  const MSG_ID = {
    REGISTER: 100,
    UNREGISTER: 200,
    COMMAND: 500,
    QUERY: 501,
    ERROR: -1,
    OUTPUT: 1,
    RETURN: 2,
    CONSOLE: 3
  };
  ```
- Define internal structures:
  ```javascript
  hs.ipc.__registeredCLIInstances = {};
  hs.ipc.__originalPrint = print;
  ```
- Implement default message handler `hs.ipc.__defaultHandler(port, msgID, data)`:
  - Extract message ID and payload from data
  - **REGISTER (msgID=100)**:
    - Parse `instanceID` and JSON arguments from payload (format: `"instanceID\0{...json...}"`)
    - Parse flags: `quiet`, `console`
    - Create instance object with isolated `_cli` and `print` (Option B: Shared Context with Scoping):
      ```javascript
      hs.ipc.__registeredCLIInstances[instanceID] = {
        _cli: {
          remote: hs.ipc.remotePort(instanceID),
          quietMode: quiet,
          console: console,
          args: scriptArguments // Custom arguments from CLI
        },
        print: function(...args) {
          if (this._cli.quietMode) return;
          let output = args.map(a => String(a)).join('\t') + '\n';
          this._cli.remote.sendMessage(output, MSG_ID.OUTPUT);
        }
      };
      ```
    - Return `"ok"` response
  - **UNREGISTER (msgID=200)**:
    - Parse instanceID from data
    - Delete instance from `__registeredCLIInstances`
    - Call `delete()` on remote port
    - No response needed (one-way message)
  - **COMMAND (msgID=500) / QUERY (msgID=501)**:
    - Parse instanceID and code from data (format: `"instanceID\0code"`)
    - Retrieve instance object
    - Execute code using Option B pattern (Function parameter injection):
      ```javascript
      let instance = hs.ipc.__registeredCLIInstances[instanceID];

      // Try with return first
      try {
        let fn = new Function('_cli', 'print', 'return ' + code);
        result = fn(instance._cli, instance.print);
      } catch (e1) {
        // Try without return
        try {
          let fn = new Function('_cli', 'print', code);
          result = fn(instance._cli, instance.print);
        } catch (e2) {
          // Send error response
          instance._cli.remote.sendMessage(String(e2) + '\n', MSG_ID.ERROR);
          return "error";
        }
      }
      ```
    - Format result for transmission:
      - Success: Send result with `MSG_ID.RETURN` (2) if COMMAND, return as string if QUERY
      - Error: Send error message with `MSG_ID.ERROR` (-1)
    - For COMMAND: Return "ok" or "error" status
    - For QUERY: Return result directly
- Implement print() replacement for console mirroring:
  - `hs.ipc.print = function(...args)`:
    - Call original print
    - For each registered CLI instance with console mirroring enabled:
      - Format output string
      - Send via `instance._cli.remote.sendMessage(output, MSG_ID.CONSOLE)`
- Create default port:
  ```javascript
  hs.ipc.__default = hs.ipc.localPort("Hammerspoon2", hs.ipc.__defaultHandler);
  ```
- Replace global print:
  ```javascript
  print = hs.ipc.print;
  ```

### Step 5: Integrate IPC Module into Hammerspoon 2

- Modify `Hammerspoon 2/Engine/ModuleRoot.swift`:
  - Add to `ModuleRootAPI` protocol:
    ```swift
    @objc var ipc: HSIPCModule { get }
    ```
  - Add to `ModuleRoot` class:
    ```swift
    @objc var ipc: HSIPCModule {
        get { getOrCreate(name: "ipc", type: HSIPCModule.self) }
    }
    ```
- **No SettingsManager modifications needed** - IPC module uses direct UserDefaults access
- Add new files to Xcode project:
  - Create group `hs.ipc` under `Modules`
  - Add all Swift files
  - Add `hs.ipc.js` to bundle resources
- Build and verify module loads without errors

### Step 6: Implement hs2 Command-Line Tool

- Create new command-line tool target in Xcode:
  - Target name: `hs2`
  - Product name: `hs2`
  - Type: Command Line Tool
  - Language: Swift
  - Link against: `CoreFoundation.framework`, `AppKit.framework`
  - Note: libedit provided by macOS automatically (no explicit linker flag needed)
  - If linker errors occur, may need `-ledit` flag
- Create directory `hs2/` for source files
- Create `hs2/main.swift`:
  - Import Foundation, CoreFoundation, AppKit
  - Define exit code constants:
    ```swift
    let EX_OK: Int32 = 0
    let EX_USAGE: Int32 = 64
    let EX_DATAERR: Int32 = 65
    let EX_NOINPUT: Int32 = 66
    let EX_UNAVAILABLE: Int32 = 69
    let EX_TEMPFAIL: Int32 = 75
    ```
  - Parse command-line arguments using `CommandLine.arguments`
  - Implement argument parser:
    - `-A`: Set `autoLaunch = true`
    - `-a`: Set `exitIfNotRunning = true`
    - `-i`: Set `interactive = true`
    - `-s`: Set `readStdin = true`
    - `-c code`: Add code to `commandsToExecute` array
    - `-m name`: Set `portName = name`
    - `-n`: Set `useColors = false`
    - `-N`: Set `useColors = true`
    - `-C`: Set `consoleMirroring = true`
    - `-P`: Set `legacyMode = true`
    - `-q`: Set `quietMode = true`
    - `-t seconds`: Parse and set `timeout = Double(seconds)`
    - `-h`: Display help and exit
    - `--`: Stop parsing, store remaining in `customArgs`
    - Non-option: Set `fileName = arg`
  - Detect stdin pipe: `readStdin = !isatty(STDIN_FILENO)`
  - Determine interactive mode: `interactive = !readStdin && isatty(STDOUT_FILENO) && commandsToExecute.isEmpty && fileName == nil`
  - Check if Hammerspoon 2 is running:
    - Use `NSRunningApplication.runningApplications(withBundleIdentifier:)`
    - Bundle ID: Extract from parent app's bundle using `Bundle.main.bundleIdentifier!`
    - Note: hs2 is embedded in app bundle, so Bundle.main refers to Hammerspoon 2.app
    - If not running and `exitIfNotRunning`, exit with `EX_TEMPFAIL`
    - If not running and not `autoLaunch`, show alert:
      ```swift
      let alert = NSAlert()
      alert.messageText = "Hammerspoon 2 is not running"
      alert.informativeText = "Would you like to launch it?"
      alert.addButton(withTitle: "Launch")
      alert.addButton(withTitle: "Cancel")
      if alert.runModal() == .alertFirstButtonReturn {
          autoLaunch = true
      } else {
          exit(EX_UNAVAILABLE)
      }
      ```
    - If `autoLaunch`, launch Hammerspoon 2:
      ```swift
      let bundleID = Bundle.main.bundleIdentifier!
      NSWorkspace.shared.launchApplication(
          withBundleIdentifier: bundleID,
          options: .withoutActivation,
          additionalEventParamDescriptor: nil,
          launchIdentifier: nil
      )
      ```
    - Wait up to 10 seconds for IPC port to become available:
      ```swift
      var attempts = 0
      while attempts < 10 {
          let testPort = CFMessagePortCreateRemote(nil, portName as CFString)
          if testPort != nil {
              CFRelease(testPort!)
              break
          }
          sleep(1)
          attempts += 1
      }
      ```
  - Create `HSClient` instance
  - Configure client with parsed options
  - Start client thread
  - Execute commands based on mode:
    - If `readStdin`: Read lines from stdin and execute
    - If `fileName`: Read file contents and execute
    - If `commandsToExecute.count > 0`: Execute each command
    - If `interactive`: Create and run `HSInteractiveREPL`
  - Wait for client thread to complete
  - Exit with `client.exitCode`

### Step 7: Implement HSClient

- Create `hs2/HSClient.swift`
- Define `HSClient` class extending `Thread`:
  - Properties (as documented in "Relevant Files" section)
  - Add initializer:
    ```swift
    init(remoteName: String, timeout: TimeInterval, useColors: Bool, ...) {
        self.remoteName = remoteName
        self.localName = UUID().uuidString
        // ... initialize other properties
        super.init()
    }
    ```
  - Implement `main()`:
    - Create autorelease pool
    - Create remote port: `CFMessagePortCreateRemote(nil, remoteName as CFString)`
    - Check for errors, set `exitCode = EX_UNAVAILABLE` if failed
    - Create local port: `CFMessagePortCreateLocal(nil, localName as CFString, localPortCallback, &context, &error)`
    - Check for errors, set `exitCode = EX_UNAVAILABLE` if failed
    - Add local port to run loop:
      ```swift
      let runLoopSource = CFMessagePortCreateRunLoopSource(nil, localPort, 0)
      CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
      ```
    - Call `registerWithRemote()`
    - Run event loop: `CFRunLoopRun()`
  - Implement `registerWithRemote()`:
    - Construct registration message:
      ```swift
      let args = [
          "quiet": quietMode,
          "console": consoleMirroring,
          "customArgs": customArgs
      ]
      let json = try JSONSerialization.data(withJSONObject: args)
      let message = "\(localName)\0\(String(data: json, encoding: .utf8)!)"
      ```
    - Send with msgID=100
    - Verify response is "ok"
  - Implement `unregisterWithRemote()`:
    - Send localName with msgID=200
    - No response expected
  - Implement `executeCommand(_ command: String) -> Bool`:
    - Construct command message: `"\(localName)\0\(command)"`
    - Send with msgID=500
    - Verify response is "ok" and return true
    - Return false on error, set `exitCode`
  - Implement `sendToRemote(_:msgID:wantResponse:) -> Data?`:
    - Create message data
    - For COMMAND/QUERY, prepend instance ID
    - Call `CFMessagePortSendRequest()` with timeouts
    - Handle errors, return data or nil
  - Implement static `localPortCallback()`:
    - Extract CFDataRef, convert to Data
    - Get HSClient instance from info pointer
    - Route message based on msgID:
      - MSGID_OUTPUT (1) / MSGID_RETURN (2) / MSGID_CONSOLE (3): stdout with colorOutput
      - MSGID_ERROR (-1): stderr with colorError
    - Write to appropriate stream with color codes
    - Return acknowledgment CFDataRef
  - Add `stopRunLoop()` method:
    ```swift
    CFRunLoopStop(CFRunLoopGetCurrent())
    ```
  - Call from `deinit` or when done

### Step 8: Implement Interactive REPL

- Create `hs2/HSInteractiveREPL.swift`
- Import Darwin (for readline functions)
- Define `HSInteractiveREPL` class:
  - Properties:
    - `client: HSClient`
    - `historyFilePath: URL` (hardcoded to `~/.config/Hammerspoon2/.cli.history`)
  - Initializer:
    ```swift
    init(client: HSClient) {
        self.client = client
        // v1.0: Hardcode history location (persistence deferred to v2.0)
        let configDir = URL(fileURLWithPath: NSString("~/.config/Hammerspoon2").expandingTildeInPath)
        self.historyFilePath = configDir.appendingPathComponent(".cli.history")
    }
    ```
  - Note: History works in-session only (not persisted across sessions in v1.0)
  - Implement `run()`:
    - Call `setupReadline()`
    - Print banner with `colorBanner`
    - Main loop:
      ```swift
      while client.exitCode == EX_OK {
          print(client.colorInput, terminator: "")
          guard let input = readline("> ") else {
              // Ctrl-D pressed
              break
          }
          let line = String(cString: input)
          free(input)

          if !line.isEmpty {
              add_history(line)  // In-memory history only for v1.0
              _ = client.executeCommand(line)
          }
      }
      ```
    - Note: No history persistence in v1.0 (loadHistory/saveHistory deferred to v2.0)
  - Implement `setupReadline()`:
    - Set completion function:
      ```swift
      rl_attempted_completion_function = completionFunction
      rl_completion_append_character = 0  // No space after completion
      ```
    - Note: Use libedit (BSD licensed) via `#include <editline/readline.h>`
  - Implement completion bridge:
    - Create static/global storage for completion state
    - Implement C-compatible callback function:
      ```swift
      func completionFunction(_ text: UnsafePointer<CChar>?,
                             _ start: Int32,
                             _ end: Int32) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? {
          rl_attempted_completion_over = 1
          return rl_completion_matches(text, completionGenerator)
      }

      func completionGenerator(_ text: UnsafePointer<CChar>?,
                               _ state: Int32) -> UnsafeMutablePointer<CChar>? {
          // On first call (state==0), query Hammerspoon for completions
          // Store results in static variable
          // On subsequent calls, return next match
          // Return nil when exhausted
      }
      ```
    - Query Hammerspoon 2:
      ```javascript
      hs.completionsForInputString("\(String(cString: text))")
      ```
    - Parse JSON array response
    - Return matches one by one using `strdup()`

### Step 9: Implement completionsForInputString in Hammerspoon 2 (Minimal)

- Create JavaScript function in `engine.js` or hs.ipc.js
- **Minimal implementation for v1.0** - only complete `hs.*` module names:
  ```javascript
  hs.completionsForInputString = function(inputString) {
    if (inputString.startsWith("hs.")) {
      // Return hs.* module names
      let prefix = "hs.";
      let modules = Object.keys(hs).filter(k => k !== "__proto__");
      let completions = modules.map(m => prefix + m);
      return completions.filter(c => c.startsWith(inputString));
    }
    return [];
  };
  ```
- **Defer to v2.0**: Deep property completion, method completion, global namespace completion
- **Enhancement candidates** (not for v1.0):
  - Complete object properties and methods
  - Complete global variables
  - Complete function parameters
  - Handle deep nesting (e.g., `hs.timer.doAfter`)
  - Use prototype chain inspection

### Step 10: Create Man Page

- Create `hs2/Resources/hs2.1` (roff format)
- Base on `hs_repo_old/extensions/ipc/cli/hs.man`
- Update for Hammerspoon 2 and JavaScript:
  - Change references from Lua to JavaScript
  - Update examples to use JavaScript syntax
  - Update file paths (`~/.config/Hammerspoon2/`)
  - Update bundle identifier
- Sections to include:
  - NAME: `hs2 - Hammerspoon 2 command line interface`
  - SYNOPSIS: Usage patterns
  - DESCRIPTION: Overview of functionality
  - OPTIONS: All command-line flags with descriptions
  - EXAMPLES: Common usage scenarios
  - FILES: Configuration and history file locations
  - EXIT STATUS: Explanation of exit codes
  - SEE ALSO: Related commands
  - AUTHORS: Attribution
- Configure Xcode to install man page in bundle:
  - Add to "Copy Bundle Resources" build phase
  - Place in `Contents/Resources/man/`

### Step 11: Configure Xcode Build Settings

- Update main app target:
  - Add hs2 tool target as dependency
  - Configure build phases to copy hs2 binary:
    - Add "Copy Files" build phase
    - Destination: Frameworks
    - Subpath: `hs2`
    - Copy `hs2` binary from product directory
  - Copy man page to Resources:
    - Add to "Copy Bundle Resources"
    - Ensure `hs2.1` is in `Contents/Resources/man/`
- Update hs2 tool target:
  - Set deployment target to match main app (macOS 15.0 or configured version)
  - Add required frameworks:
    - CoreFoundation.framework
    - AppKit.framework
  - Note: libedit (editline) provided by macOS, no explicit linker flag typically needed
  - Set product name: `hs2`
  - Configure signing and hardening:
    - Enable hardened runtime
    - Enable signing with same certificate as main app
    - Add entitlements if needed
- Verify build configuration:
  - Ensure hs2 binary is codesigned
  - Ensure binary has correct install path
  - Test that symlink creation works

### Step 12: Write Integration Tests (Basic)

- Create `Hammerspoon 2Tests/IntegrationTests/HSIPCIntegrationTests.swift`
- Import XCTest and test framework
- **Basic smoke tests only** (defer comprehensive tests to v2.0):
  - `testModuleLoads()`:
    - Verify `hs.ipc` module loads without errors
    - Verify module has expected properties (`localPort`, `remotePort`, `cliInstall`, etc.)
  - `testLocalPortCreation()`:
    - Create local port via JavaScript
    - Verify port is valid
    - Verify name is correct
    - Call delete() and verify cleanup
  - `testMessageRoundtrip()`:
    - Create local port with simple callback
    - Create remote port to same name
    - Send test message
    - Verify callback receives message
    - Verify response returned
  - `testCLIInstallation()`:
    - Call cliInstall with `/tmp/hs2test` path
    - Verify symlinks created
    - Call cliUninstall
    - Verify symlinks removed
    - Use temporary directory, cleanup in tearDown
- Use `JSTestHarness` for JavaScript evaluation
- Keep tests simple - verify basic functionality works
- **Deferred to v2.0**: Edge cases, error conditions, concurrent CLIs, protocol handler details

### Step 13: Update Documentation

- Update `CLAUDE.md` to document hs.ipc module:
  - Add to "Implemented Modules" section
  - Describe message port API
  - Describe CLI installation functions
  - Describe configuration functions
  - Provide usage examples
- Update `CLAUDE.md` to document hs2 CLI:
  - Add to "User Configuration Guide" section
  - Document all command-line flags
  - Provide examples:
    - Simple command execution
    - Interactive REPL usage
    - Script file execution
    - Piping input
    - Using with shell scripts
  - Document tab completion
  - Document history persistence
- Create `docs/IPC.md` with detailed documentation:
  - Protocol specification
  - Message format details
  - Security considerations
  - Performance characteristics
  - Troubleshooting guide
- Update README if exists with hs2 installation instructions

### Step 14: Build and Validate

- Build entire project in Xcode
- Fix any compilation errors
- Fix any warnings
- Run validation commands (see below)
- Test manually:
  - Launch Hammerspoon 2
  - Open Console, verify no IPC errors
  - Test hs.ipc.localPort() from REPL
  - Test hs.ipc.remotePort() from REPL
  - Install hs2 CLI: `hs.ipc.cliInstall()`
  - Test hs2 from terminal: `hs2 -c "console.log('test')"`
  - Test hs2 interactive mode: `hs2 -i`
  - Test tab completion in REPL
  - Test history persistence
  - Verify colors work correctly
  - Test uninstall: `hs.ipc.cliUninstall()`

## Validation Commands

Execute every command to validate the chore is complete with zero regressions.

```bash
# Build the project
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug build

# Run unit tests
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug test

# Verify hs2 binary is built
ls -lh "build/Debug/Hammerspoon 2.app/Contents/Frameworks/hs2/hs2"

# Verify man page is included
ls -lh "build/Debug/Hammerspoon 2.app/Contents/Resources/man/hs2.1"

# Launch Hammerspoon 2 app (keep running for subsequent tests)
open "build/Debug/Hammerspoon 2.app"

# Test IPC module is loaded
# (Execute in Hammerspoon 2 Console)
hs.ipc.localPort("test", function(port, msgID, data) { return "pong"; })

# Test CLI installation
# (Execute in Hammerspoon 2 Console)
hs.ipc.cliInstall("/tmp/hs2test", true)

# Verify symlinks created
ls -lh /tmp/hs2test/bin/hs2
ls -lh /tmp/hs2test/share/man/man1/hs2.1

# Test basic CLI execution
/tmp/hs2test/bin/hs2 -c "1 + 1"
# Expected output: 2

# Test CLI error handling
/tmp/hs2test/bin/hs2 -c "throw new Error('test error')"
# Expected: Error message on stderr, exit code 65

# Test CLI help
/tmp/hs2test/bin/hs2 -h
# Expected: Help text

# Test interactive mode (manual test, exit with Ctrl-D)
/tmp/hs2test/bin/hs2 -i
# Expected: REPL prompt, tab completion working, in-session history (up arrow)

# Test stdin input
echo "console.log('hello')" | /tmp/hs2test/bin/hs2 -s
# Expected output: hello

# Test quiet mode
/tmp/hs2test/bin/hs2 -q -c "console.log('should not appear')"
# Expected: No output

# Test console mirroring (requires manual verification in Console window)
/tmp/hs2test/bin/hs2 -C -c "console.log('mirrored')"
# Expected: Output appears both in terminal and Console window

# Note: Color and history persistence tests deferred to v2.0

# Test CLI uninstallation
# (Execute in Hammerspoon 2 Console)
hs.ipc.cliUninstall("/tmp/hs2test", true)

# Verify symlinks removed
ls /tmp/hs2test/bin/hs2 2>&1 | grep "No such file"

# Run integration tests
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug test -only-testing:Hammerspoon_2Tests/HSIPCIntegrationTests

# Check for memory leaks (run app under Instruments)
# Manual: Xcode → Product → Profile → Leaks template → Run

# Verify no errors in Console.app
# Manual: Open Console.app, filter for "Hammerspoon", verify no IPC errors

# Clean up test installation
rm -rf /tmp/hs2test
```

## Document changes

### Update CLAUDE.md

Add new section under "Implemented Modules":

````markdown
### hs.ipc

**File**: `Hammerspoon 2/Modules/hs.ipc/IPCModule.swift`

Inter-process communication module enabling external processes to communicate with Hammerspoon 2 via CFMessagePort.

**Key Functions**:
- `localPort(name, callback)` - Create server message port
- `remotePort(name)` - Connect to remote port
- `cliInstall([path], [silent])` - Install hs2 command-line tool
- `cliUninstall([path], [silent])` - Remove hs2 symlinks
- `cliStatus([path], [silent])` - Check installation status

**Note**: CLI color configuration and history persistence functions deferred to v2.0

**Message Port Objects** (HSMessagePort):
- `name` - Port name string
- `isValid` - Port validity check
- `isRemote` - Local vs remote distinction
- `sendMessage(data, msgID, [timeout], [oneWay])` - Send IPC message
- `delete()` - Cleanup port

**Example**:
```javascript
// Create server port
const port = hs.ipc.localPort("MyService", function(port, msgID, data) {
    console.log("Received:", data);
    return "Response";
});

// From another process or CLI
const remote = hs.ipc.remotePort("MyService");
remote.sendMessage("Hello", 0);
```

**Default Port**: `Hammerspoon2` - Handles CLI communication protocol
````

Add new section under "User Configuration Guide":

````markdown
### hs2 Command-Line Tool

The `hs2` CLI tool enables terminal access to Hammerspoon 2 for automation, scripting, and interactive development.

**Installation**:
```javascript
// In Hammerspoon 2 Console
hs.ipc.cliInstall("/usr/local");
```

**Usage Examples**:
```bash
# Execute single command
hs2 -c "hs.alert.show('Hello from terminal')"

# Interactive REPL
hs2 -i

# Execute JavaScript file
hs2 ~/scripts/automation.js

# Pipe input
echo "console.log(hs.application.frontmostApplication().title())" | hs2 -s

# With timeout
hs2 -t 10 -c "longRunningOperation()"

# Quiet mode (errors only)
hs2 -q -c "backgroundTask()"

# Console mirroring (see Hammerspoon console output in terminal)
hs2 -C

# As shebang script
#!/usr/local/bin/hs2
console.log("Running from file");
hs.application.launchOrFocus("Safari");
```

**Options**:
- `-A` - Auto-launch Hammerspoon 2 if not running
- `-a` - Exit with error if Hammerspoon 2 not running
- `-i` - Force interactive mode
- `-s` - Read from stdin
- `-c code` - Execute code (can be repeated)
- `-m name` - Connect to custom port (default: "Hammerspoon2")
- `-n` - Disable colors
- `-N` - Force colors
- `-C` - Enable console mirroring
- `-q` - Quiet mode
- `-t seconds` - Set timeout (default: 4.0)
- `-h` - Display help

**Tab Completion**: Available in interactive mode, completes against `hs.*` namespace (minimal in v1.0).

**Command History**: In-session history via up/down arrows (persistence deferred to v2.0).
````

### Create docs/IPC.md

Create comprehensive IPC protocol documentation including message format specifications, security considerations, and troubleshooting guide.

## Git log

```
Implement hs.ipc module and hs2 command-line tool

Add comprehensive IPC support to Hammerspoon 2 enabling external process
communication via CFMessagePort and providing a full-featured CLI tool.

New Components:
- hs.ipc module (Swift/JavaScript) for message port management
- HSMessagePort class wrapping CFMessagePort with JavaScript bridge
- IPCProtocol defining message IDs and protocol version 2.0
- JavaScript protocol handler for REGISTER/COMMAND/QUERY messages
- hs2 command-line tool (Swift) with full argument parsing
- HSClient class managing IPC client lifecycle and communication
- HSInteractiveREPL class providing libedit-based REPL with tab
  completion and in-session history
- Man page documentation for hs2 tool

Module Features:
- Create local (server) and remote (client) message ports
- Bidirectional communication with callback support
- CLI installation/uninstallation via symlinks
- Isolated execution environments per CLI instance
- Console output mirroring support
- Note: Color/history configuration deferred to v2.0

CLI Features:
- Execute JavaScript code from command line (-c flag)
- Interactive REPL mode with tab completion (-i flag)
- File execution support
- Stdin piping support (-s flag)
- Auto-launch Hammerspoon 2 if not running (-A flag)
- Configurable timeout and quiet mode
- libedit integration with in-session command history
- POSIX-compliant exit codes
- Bundle ID extracted dynamically (no hardcoding)

Testing:
- Integration tests for message port operations
- Protocol handler tests
- CLI installation/configuration tests
- End-to-end CLI execution tests

Documentation:
- Updated CLAUDE.md with hs.ipc module documentation
- Updated CLAUDE.md with hs2 CLI usage guide
- Created comprehensive IPC.md protocol specification
- Added hs2.1 man page

This implementation provides core IPC functionality from original Hammerspoon's
hs.ipc/hs tool, adapted for JavaScript and Hammerspoon 2 architecture.

v1.0 Scope Changes:
- Core IPC and CLI functionality implemented
- UserDefaults configuration (colors, history persistence) deferred to v2.0
- libedit used instead of GNU readline (BSD licensing)
- Bundle ID extracted dynamically (no hardcoding)
- Threading model: @MainActor with direct JS invocation

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

## Notes

### Security Considerations

1. **CFMessagePort is local-only**: Communication is restricted to the same machine, no network exposure
2. **Port names are global**: Any process on the system can connect to a named port - this is by design for CLI access but users should be aware
3. **Code execution**: The IPC protocol allows arbitrary JavaScript execution - this is intentional but should be documented as a security consideration
4. **Sandboxing compatibility**: CFMessagePort works within App Sandbox but may require specific entitlements. Test thoroughly if app is sandboxed.

### Performance Considerations

1. **CFMessagePort is synchronous**: Sending with response blocks until timeout or reply received. Use appropriate timeouts.
2. **Message size limits**: CFMessagePort has practical limits (~1MB). For large data, consider chunking or alternative approaches.
3. **Main thread requirement**: CFMessagePort callbacks execute on the thread that created the port. Ensure thread safety.
4. **Recursive call protection**: Protocol handler limits recursion to 5 levels to prevent stack overflow.

### Compatibility Notes

1. **Legacy mode (V1)**: Removed in v1.0 (deferred to v2.0 if needed)
2. **Port naming**: Changed from "Hammerspoon" to "Hammerspoon2" to avoid conflicts if original Hammerspoon is installed
3. **Bundle identifier**: Extracted dynamically via `Bundle.main.bundleIdentifier!` (no hardcoding)
4. **Binary naming**: Using "hs2" instead of "hs" to distinguish from original Hammerspoon CLI
5. **Configuration**: UserDefaults-based colors/history deferred to v2.0 for simplicity

### Testing Challenges

1. **IPC requires running app**: Integration tests need Hammerspoon 2 running with active message port
2. **Thread coordination**: Tests must handle asynchronous message port communication
3. **File system operations**: CLI install/uninstall tests should use temporary directories
4. **Interactive mode testing**: REPL tests are limited; may require manual validation

### Future Enhancements (Out of Scope)

1. **Unix domain sockets**: Alternative transport for compatibility with sandboxed environments
2. **Remote IPC**: Network-based communication (requires security considerations)
3. **Multi-instance support**: Handle multiple Hammerspoon 2 instances with unique ports
4. **IPC introspection**: API to enumerate connected CLI instances
5. **Streaming API**: Support for large data transfers or progressive results
6. **Binary protocol**: More efficient encoding than UTF-8 strings

### JavaScript vs Lua Differences

1. **Error handling**: JavaScript uses try/catch, Lua uses pcall - adapt error response format accordingly
2. **Global namespace**: JavaScript has different globals (`console` vs Lua's `print` semantics)
3. **Module loading**: JavaScript uses different patterns than Lua's `require()`
4. **Completion algorithm**: Must use JavaScript reflection instead of Lua metatable inspection
5. **JSON encoding**: Use native `JSON.stringify()` instead of `hs.json.encode()`

### libedit Integration (DECISION: Use libedit)

1. **Choice**: Using libedit (BSD licensed) instead of GNU Readline (GPL)
2. **Availability**: macOS provides libedit with readline compatibility layer at `/usr/include/editline/readline.h`
3. **Linking**: Typically no explicit linker flag needed - provided by system
4. **Header**: Use `#include <editline/readline.h>` for readline-compatible API
5. **API compatibility**: Most readline functions available (readline, add_history, etc.)
6. **License**: BSD license avoids GPL concerns for distribution

### CFMessagePort Edge Cases

1. **Port name conflicts**: If port name already in use, creation fails - handle gracefully
2. **Invalidated ports**: Remote port can become invalid if server exits - detect and report
3. **Timeout edge cases**: Very small timeouts (<0.1s) may be unreliable
4. **Context pointer lifetime**: Ensure context structure outlives CFMessagePort
5. **CFRunLoop modes**: Use `.defaultMode` for consistency unless specific needs require different mode

### Acceptance Criteria Summary

The implementation is complete when:

1. ✅ Module loads without errors and is accessible via `hs.ipc` in JavaScript
2. ✅ Local ports can be created and receive messages with callback invocation
3. ✅ Remote ports can connect and send messages to local ports
4. ✅ Default "Hammerspoon2" port handles REGISTER/COMMAND/UNREGISTER protocol
5. ✅ hs2 CLI tool builds and launches successfully
6. ✅ hs2 can execute simple commands: `hs2 -c "1+1"` returns "2"
7. ✅ hs2 interactive mode provides REPL with prompt and code execution
8. ✅ Tab completion queries Hammerspoon and returns relevant completions
9. ✅ Command history works in-session (up/down arrows)
10. ✅ CLI installation creates functional symlinks
11. ✅ CLI uninstallation removes symlinks cleanly
12. ✅ Error messages are clear and actionable
13. ✅ Exit codes conform to POSIX standards
14. ✅ All integration tests pass
15. ✅ No memory leaks detected under Instruments
16. ✅ Documentation is complete and accurate
17. ✅ Bundle ID extracted dynamically (no hardcoded values)
18. ✅ libedit integration working (BSD licensed)

Note: Color configuration and history persistence deferred to v2.0

