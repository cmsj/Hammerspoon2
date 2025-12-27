# Feature: Console Command History

## Feature Description

Implement persistent command history for the Hammerspoon 2 console window, achieving feature parity with the original Hammerspoon console implementation. This includes:

1. **Session-based history** (already implemented) - Commands navigable via up/down arrow keys during current session
2. **JavaScript API** (not implemented) - `hs.console.getHistory()` and `hs.console.setHistory()` methods
3. **Memory management** (partially implemented) - Enforce configurable history size limit
4. **Configuration UI** (not implemented) - Expose history length setting in Advanced Settings

### Current State Analysis

**Already Implemented:**
- ✅ Session-based history navigation with up/down arrow keys (ConsoleView.swift:71-100)
- ✅ History storage in `evalHistory: [String]` array (ConsoleView.swift:15)
- ✅ `consoleHistoryLength` setting property in SettingsManager (SettingsManager.swift:56-66)

**Not Implemented:**
- ❌ JavaScript API methods (`hs.console.getHistory()`, `hs.console.setHistory()`)
- ❌ History size limit enforcement (setting exists but is unused)
- ❌ Configuration UI for history length in SettingsAdvancedView
- ❌ Persistence across app restarts (intentional - matches original Hammerspoon behavior)

**Behavioral Deviations:**
- None - current implementation matches original Hammerspoon's session-only, non-persistent approach

## Ground Truth: Original Hammerspoon Implementation

Based on analysis of `hs_repo_old/Hammerspoon/MJConsoleWindowController.m` and `hs_repo_old/extensions/console/libconsole.m`:

### Storage & Lifecycle
- **Data Structure**: `NSMutableArray* history` storing command strings
- **Initialization**: Empty array created in `windowDidLoad()`
- **Persistence**: **None** - history is discarded on app quit or window close
- **Size Limit**: **Unbounded** - grows indefinitely in memory until app termination

### Navigation Behavior (MJConsoleWindowController.m:202-223)
```objc
- (void) goPrevHistory {
    self.historyIndex = MAX(self.historyIndex - 1, 0);
    [self useCurrentHistoryIndex];
}

- (void) goNextHistory {
    self.historyIndex = MIN(self.historyIndex + 1, [self.history count]);
    [self useCurrentHistoryIndex];
}

- (void) useCurrentHistoryIndex {
    if (self.historyIndex == [self.history count])
        [self.inputField setStringValue: @""];
    else
        [self.inputField setStringValue: [self.history objectAtIndex:self.historyIndex]];

    // Position cursor at end of text
    NSRange position = (NSRange){[[editor string] length], 0};
    [editor setSelectedRange:position];
}
```

**Key Behaviors:**
1. Up arrow decrements index (stops at 0, no wrap-around)
2. Down arrow increments index (can go to `count`, which displays empty string)
3. Cursor positioned at **end** of loaded command
4. History index resets to `[self.history count]` after command execution

### Command Addition (MJConsoleWindowController.m:182-200)
```objc
- (IBAction) tryMessage:(NSTextField*)sender {
    NSString* command = [sender stringValue];
    // ... execute command ...
    [self saveToHistory:command];
}

- (void) saveToHistory:(NSString*)cmd {
    [self.history addObject:cmd];
    self.historyIndex = [self.history count];
    [self useCurrentHistoryIndex];
}
```

**When Added:**
- Only after successful execution via `tryMessage:` action
- Empty commands are still added to history
- Index reset to end position (one past last item)

### JavaScript API (libconsole.m:314-421)

**`hs.console.getHistory()` → array**
```objc
static int console_getHistory(lua_State* L) {
    lua_newtable(L);
    NSArray* history = [[MJConsoleWindowController singleton] getConsoleHistory];

    for (unsigned long i = 0; i < [history count]; i++) {
        lua_pushnumber(L, i + 1);
        lua_pushstring(L, [[history objectAtIndex:i] UTF8String]);
        lua_settable(L, -3);
    }

    return 1;
}
```

**Returns:** Array of command strings in execution order (oldest first)
**Example:** `["command1", "command2", "command3"]`

**`hs.console.setHistory(array)` → nil**
```objc
static int console_setHistory(lua_State* L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TTABLE, LS_TBREAK];

    NSArray* history = [skin toNSObjectAtIndex:1];
    [[MJConsoleWindowController singleton] setConsoleHistory:history];

    return 0;
}
```

**Parameters:** Array of strings
**Returns:** nil
**Side Effects:** Replaces entire history, resets index to end

### Edge Cases & Special Behaviors

1. **Empty commands**: Added to history (allows repeating empty submit)
2. **Duplicate commands**: Added separately (no deduplication)
3. **Multi-line input**: Supported (via HSGrowingTextField), stored as single string
4. **Navigation beyond bounds**:
   - Up at index 0: No-op, stays at index 0
   - Down at end: Displays empty field, index = `[history count]`
5. **Programmatic history modification**: Immediately affects navigation

## Mapping to Hammerspoon 2 Architecture

### Current Implementation Gap Analysis

| Feature                 | Original Hammerspoon                  | Hammerspoon 2 Current               | Gap                           |
|-------------------------|---------------------------------------|-------------------------------------|-------------------------------|
| Session history storage | `NSMutableArray* history`             | `@State var evalHistory: [String]`  | ✅ Match                      |
| Navigation (up/down)    | `goPrevHistory()` / `goNextHistory()` | `.onKeyPress` handlers              | ✅ Match                      |
| Cursor positioning      | End of text                           | Native SwiftUI behavior             | ✅ Match                      |
| History index tracking  | `NSInteger historyIndex`              | `@State var evalIndex: Int`         | ✅ Match                      |
| Command addition        | `saveToHistory:` after exec           | `evalHistory.append()` after submit | ✅ Match                      |
| Size limit enforcement  | None (unbounded)                      | None (setting exists, unused)       | ⚠️ Gap                         |
| JavaScript API          | `getHistory()` / `setHistory()`       | Not implemented                     | ❌ Gap                        |
| Persistence             | None                                  | None                                | ✅ Match                      |
| Configuration UI        | None                                  | None                                | ✅ Match (original had no UI) |

### Architecture Mapping

**SwiftUI State Management:**
- `ConsoleView.evalHistory` remains primary storage (session-only)
- HSConsoleModule accesses history via shared reference or notification
- No persistence layer required (matches original behavior)

**JavaScript Bridge:**
- Add `getHistory()` and `setHistory(array)` to HSConsoleModuleAPI protocol
- Implementation in HSConsoleModule accesses ConsoleView state via EnvironmentObject or Singleton pattern

**Settings Integration:**
- `SettingsManager.consoleHistoryLength` already exists
- ConsoleView must enforce limit when appending commands
- SettingsAdvancedView needs Slider/Stepper UI control

### Constraints & Design Decisions

1. **No Persistence**: Deliberately matches original - history is session-only
2. **State Ownership**: ConsoleView owns `evalHistory` array (view state)
3. **Cross-Module Access**: HSConsoleModule needs read/write access to ConsoleView's history
4. **Thread Safety**: All history operations must occur on `@MainActor`
5. **Size Limit Application**: Apply limit on append (FIFO removal of oldest entries)

### Proposed Solution: Shared History Manager

Since ConsoleView state cannot be directly accessed from HSConsoleModule, introduce a singleton history manager:

```swift
@MainActor
class ConsoleHistoryManager: ObservableObject {
    static let shared = ConsoleHistoryManager()

    @Published var commands: [String] = []
    private let settingsManager: SettingsManagerProtocol

    func append(_ command: String) {
        commands.append(command)
        enforceLimit()
    }

    func setHistory(_ newHistory: [String]) {
        commands = newHistory
        enforceLimit()
    }

    private func enforceLimit() {
        let maxSize = settingsManager.consoleHistoryLength
        if commands.count > maxSize {
            commands.removeFirst(commands.count - maxSize)
        }
    }
}
```

**Justification**: This approach:
- Maintains single source of truth
- Enables cross-module access
- Preserves session-only behavior
- Supports size limit enforcement
- Compatible with SwiftUI reactive updates

## Acceptance Criteria

### Functional Parity

1. **Navigation Behavior** ✅ (Already Complete)
   - [ ] Up arrow loads previous command (stops at oldest)
   - [ ] Down arrow loads next command (empty string past newest)
   - [ ] Cursor positioned at end of loaded command
   - [ ] Index reset after command execution

2. **JavaScript API** ❌ (Not Implemented)
   - [ ] `hs.console.getHistory()` returns array of command strings
   - [ ] `hs.console.setHistory(["cmd1", "cmd2"])` replaces history
   - [ ] Setting history resets navigation index
   - [ ] Empty array is valid input for `setHistory()`

3. **Size Limit Enforcement** ⚠️ (Partially Implemented)
   - [ ] History respects `consoleHistoryLength` setting
   - [ ] Oldest commands removed when limit exceeded (FIFO)
   - [ ] Default limit: 100 commands
   - [ ] Changing setting applies to future commands (no retroactive trimming required)

4. **Configuration UI** ❌ (Not Implemented)
   - [ ] SettingsAdvancedView displays "Console History Length" slider
   - [ ] Range: 10 to 1000 commands
   - [ ] Default: 100
   - [ ] Changes persist in UserDefaults

### Edge Case Handling

1. **Empty Commands**
   - [ ] Empty strings added to history (matches original)

2. **Duplicate Commands**
   - [ ] Consecutive duplicates stored separately (no deduplication)

3. **Programmatic Modification**
   - [ ] `setHistory()` with invalid data types returns error
   - [ ] `setHistory()` with array containing non-strings filters/converts them
   - [ ] `setHistory([])` clears history successfully

4. **Size Limit Edge Cases**
   - [ ] Setting limit to 0 disables history
   - [ ] Setting limit below current history size removes oldest entries on next append
   - [ ] Maximum limit (1000) prevents unbounded memory growth

### Non-Requirements (Explicitly Out of Scope)

1. **Persistence** - History is intentionally session-only (matches original)
2. **History Search/Filter** - Not present in original Hammerspoon
3. **History Deduplication** - Not present in original Hammerspoon
4. **Per-Session Isolation** - Single global history (matches original)
5. **Undo/Redo** - Not applicable to command history

### Validation Requirements

1. **Unit Tests**
   - [ ] ConsoleHistoryManager append/setHistory logic
   - [ ] Size limit enforcement (FIFO removal)
   - [ ] Thread safety (@MainActor verification)

2. **Integration Tests**
   - [ ] JavaScript API methods (getHistory/setHistory)
   - [ ] Navigation state updates after setHistory
   - [ ] Settings changes reflected in limit enforcement

3. **Manual Testing**
   - [ ] UI navigation (up/down arrows) in ConsoleView
   - [ ] JavaScript REPL commands stored in history
   - [ ] Settings slider updates consoleHistoryLength
   - [ ] History cleared when window closes (session-only verification)

## Relevant Files

### Existing Files (Modifications Required)

#### `Hammerspoon 2/Windows/ConsoleView.swift`
- **Relevance**: Primary console UI with session history implementation
- **Changes Required**:
  - Replace `@State var evalHistory: [String]` with reference to `ConsoleHistoryManager.shared`
  - Modify `.onSubmit` to call `ConsoleHistoryManager.shared.append()` instead of direct array append
  - Update navigation logic to use `ConsoleHistoryManager.shared.commands`
  - Ensure `evalIndex` state remains local to view (navigation cursor position)

#### `Hammerspoon 2/Modules/hs.console/HSConsoleModule.swift`
- **Relevance**: JavaScript API module for console control
- **Changes Required**:
  - Add `getHistory()` method to `HSConsoleModuleAPI` protocol
  - Add `setHistory(_ commands: [String])` method to `HSConsoleModuleAPI` protocol
  - Implement methods by delegating to `ConsoleHistoryManager.shared`
  - Add `@MainActor` annotation to new methods (history access must be on main thread)

#### `Hammerspoon 2/Managers/SettingsManager.swift`
- **Relevance**: Already contains `consoleHistoryLength` property (lines 56-66)
- **Changes Required**:
  - None - property already exists and is functional
  - Verify UserDefaults key `"consoleHistoryLength"` is stable

#### `Hammerspoon 2/Windows/Settings/SettingsAdvancedView.swift`
- **Relevance**: Settings UI for advanced configuration
- **Changes Required**:
  - Add Grid row for "Console History Length" setting
  - Use `Slider` or `Stepper` control bound to `settingsManager.consoleHistoryLength`
  - Display current value (e.g., "Console History Length: 100 commands")
  - Set min: 10, max: 1000, step: 10

#### `Hammerspoon 2/Protocols/SettingsManagerProtocol.swift`
- **Relevance**: Protocol definition for SettingsManager
- **Changes Required**:
  - None - `consoleHistoryLength` property already declared in protocol

### New Files

#### `Hammerspoon 2/Managers/ConsoleHistoryManager.swift`
- **Purpose**: Centralized command history storage and management
- **Responsibilities**:
  - Store session-based command history as `@Published var commands: [String]`
  - Enforce size limit from `SettingsManager.consoleHistoryLength`
  - Provide append/set/get methods for history manipulation
  - Thread-safe access via `@MainActor`
- **Key APIs**:
  ```swift
  @MainActor
  class ConsoleHistoryManager: ObservableObject {
      static let shared = ConsoleHistoryManager()
      @Published var commands: [String] = []

      func append(_ command: String)
      func setHistory(_ newHistory: [String])
      func getHistory() -> [String]
      func clearHistory()
      private func enforceLimit()
  }
  ```

#### `Hammerspoon 2Tests/Managers/ConsoleHistoryManagerTests.swift`
- **Purpose**: Unit tests for ConsoleHistoryManager
- **Test Coverage**:
  - Append command adds to history
  - Size limit enforcement removes oldest entries (FIFO)
  - setHistory replaces entire history
  - Empty history handling
  - Boundary conditions (limit = 0, limit = 1, limit > current size)

#### `Hammerspoon 2Tests/Integration/HSConsoleModuleHistoryTests.swift`
- **Purpose**: Integration tests for JavaScript history API
- **Test Coverage**:
  - `hs.console.getHistory()` returns array
  - `hs.console.setHistory([...])` updates history
  - Type checking (non-string array elements)
  - Empty array handling
  - Thread safety (MainActor verification)

## Step by Step Tasks

### Step 1: Create ConsoleHistoryManager Singleton
- Create new file `Hammerspoon 2/Managers/ConsoleHistoryManager.swift`
- Implement `@MainActor class ConsoleHistoryManager: ObservableObject`
- Add `static let shared = ConsoleHistoryManager()` singleton
- Add `@Published var commands: [String] = []` property
- Inject `SettingsManagerProtocol` dependency (default to `SettingsManager.shared`)
- Implement `append(_ command: String)` method:
  - Append to `commands` array
  - Call `enforceLimit()`
- Implement `setHistory(_ newHistory: [String])` method:
  - Replace `commands` with `newHistory`
  - Call `enforceLimit()`
- Implement `getHistory() -> [String]` method:
  - Return copy of `commands` array
- Implement `clearHistory()` method:
  - Set `commands = []`
- Implement `private func enforceLimit()`:
  - Get `maxSize` from `settingsManager.consoleHistoryLength`
  - If `commands.count > maxSize`, remove first `(commands.count - maxSize)` elements
  - Handle edge case where `maxSize == 0` (clear all history)
- Add to Xcode project in `Hammerspoon 2/Managers/` group
- **Validation**: Build succeeds without errors

### Step 2: Integrate ConsoleHistoryManager into ConsoleView
- Open `Hammerspoon 2/Windows/ConsoleView.swift`
- Add `@ObservedObject var historyManager = ConsoleHistoryManager.shared` property
- **Remove** `@State var evalHistory: [String] = []` (replaced by manager)
- Keep `@State var evalIndex: Int = -1` (view-local navigation state)
- Update up arrow handler (line 71-84):
  - Replace `evalHistory.count` with `historyManager.commands.count`
  - Replace `evalHistory[evalIndex]` with `historyManager.commands[evalIndex]`
- Update down arrow handler (line 85-100):
  - Replace `evalHistory.count - 1` with `historyManager.commands.count - 1`
  - Replace `evalHistory[evalIndex]` with `historyManager.commands[evalIndex]`
- Update `.onSubmit` handler (line 101-115):
  - Replace `evalHistory.append(evalString)` with `historyManager.append(evalString)`
  - Keep `evalIndex = -1` reset
- **Validation**: Build and run app, test console navigation with up/down arrows

### Step 3: Add JavaScript API to HSConsoleModule
- Open `Hammerspoon 2/Modules/hs.console/HSConsoleModule.swift`
- Add methods to `@objc protocol HSConsoleModuleAPI`:
  ```swift
  /// Get the console command history
  /// - Returns: Array of command strings
  @objc func getHistory() -> [String]

  /// Set the console command history
  /// - Parameter commands: Array of command strings
  @objc func setHistory(_ commands: [String])

  /// Clear the console command history
  @objc func clearHistory()
  ```
- Implement in `HSConsoleModule` class:
  ```swift
  @objc func getHistory() -> [String] {
      return ConsoleHistoryManager.shared.getHistory()
  }

  @objc func setHistory(_ commands: [String]) {
      Task { @MainActor in
          ConsoleHistoryManager.shared.setHistory(commands)
      }
  }

  @objc func clearHistory() {
      Task { @MainActor in
          ConsoleHistoryManager.shared.clearHistory()
      }
  }
  ```
- Add doc comments to protocol methods (appears in JS autocomplete)
- **Validation**: Build succeeds, open console REPL and test:
  ```javascript
  hs.console.setHistory(["test1", "test2"])
  hs.console.getHistory()  // Should return ["test1", "test2"]
  hs.console.clearHistory()
  hs.console.getHistory()  // Should return []
  ```

### Step 4: Add Console History Length Setting to UI
- Open `Hammerspoon 2/Windows/Settings/SettingsAdvancedView.swift`
- Inside the `Grid` view (after existing GridRow), add new GridRow:
  ```swift
  GridRow {
      Text("Console History Length:")
          .gridColumnAlignment(.trailing)
      HStack {
          Slider(
              value: Binding(
                  get: { Double(settingsManager.consoleHistoryLength) },
                  set: { settingsManager.consoleHistoryLength = Int($0) }
              ),
              in: 10...1000,
              step: 10
          )
          .frame(width: 200)
          Text("\(settingsManager.consoleHistoryLength) commands")
              .frame(width: 120, alignment: .leading)
              .monospacedDigit()
      }
  }
  ```
- Update view width if needed (currently 700, may need adjustment)
- **Validation**:
  - Build and run app
  - Open Settings → Advanced tab
  - Verify slider appears with current value
  - Move slider and verify displayed number updates
  - Close settings, reopen, verify value persisted

### Step 5: Create Unit Tests for ConsoleHistoryManager
- Create new file `Hammerspoon 2Tests/Managers/ConsoleHistoryManagerTests.swift`
- Import `XCTest` and `@testable import Hammerspoon_2`
- Create test class `ConsoleHistoryManagerTests: XCTestCase`
- Implement tests:
  - `testAppendCommand()` - Verify command added to history
  - `testSizeLimitEnforcement()` - Set limit to 5, append 10 commands, verify only last 5 remain
  - `testSetHistory()` - Replace history with new array
  - `testClearHistory()` - Verify clear() empties array
  - `testZeroLimitClearsHistory()` - Set limit to 0, append command, verify history empty
  - `testGetHistoryReturnsCopy()` - Verify mutations to returned array don't affect original
- Use mock SettingsManagerProtocol for controlled limit values
- Add to Xcode test target
- **Validation**: Run tests via `Cmd+U`, all tests pass

### Step 6: Create Integration Tests for JavaScript API
- Create new file `Hammerspoon 2Tests/Integration/HSConsoleModuleHistoryTests.swift`
- Use `JSTestHarness` helper (if exists) or create minimal JavaScriptCore context
- Implement tests:
  - `testGetHistoryReturnsArray()` - Call `hs.console.getHistory()`, verify JSValue is array type
  - `testSetHistoryUpdatesCommands()` - Call `hs.console.setHistory(["a", "b"])`, verify `getHistory()` returns same
  - `testSetHistoryWithEmptyArray()` - Verify empty array is valid
  - `testClearHistoryViaAPI()` - Call `hs.console.clearHistory()`, verify `getHistory()` returns `[]`
- Add to Xcode test target
- **Validation**: Run tests via `Cmd+U`, all integration tests pass

### Step 7: Run Validation Commands
- Execute all validation commands listed below
- Fix any failures before considering feature complete
- Document any deviations from original behavior (should be none)

## Validation Commands

Execute every command to validate the feature is complete with zero regressions:

```bash
# Build the project (must succeed with zero errors)
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug build

# Run all unit tests (must pass 100%)
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug test

# Run specific test suite for history manager
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug test -only-testing:Hammerspoon_2Tests/ConsoleHistoryManagerTests

# Run integration tests for console module
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug test -only-testing:Hammerspoon_2Tests/HSConsoleModuleHistoryTests
```

**Manual Validation Checklist** (execute in running app):

1. **Console Navigation**
   - Open Console (Cmd+Space or menu)
   - Type several commands, press Enter after each
   - Press Up arrow → Should load previous commands in reverse order
   - Press Down arrow → Should navigate forward, empty field at end
   - Verify cursor positioned at end of loaded command

2. **JavaScript API**
   - Open Console REPL
   - Execute: `hs.console.setHistory(["first", "second", "third"])`
   - Press Up arrow → Should show "third"
   - Press Up arrow → Should show "second"
   - Execute: `hs.console.getHistory()` → Should return `["first", "second", "third"]`
   - Execute: `hs.console.clearHistory()`
   - Execute: `hs.console.getHistory()` → Should return `[]`

3. **Size Limit Enforcement**
   - Open Settings → Advanced → Set "Console History Length" to 5
   - Open Console, execute 10 different commands
   - Press Up arrow repeatedly → Should only see last 5 commands
   - Execute: `hs.console.getHistory()` → Should return array of length 5

4. **Session-Only Behavior**
   - Execute several commands in console
   - Close console window (do NOT quit app)
   - Reopen console window
   - Press Up arrow → History should still be present (window close doesn't clear)
   - Quit Hammerspoon 2 app completely
   - Relaunch app, open console
   - Press Up arrow → History should be empty (session-only)

5. **Settings Persistence**
   - Open Settings → Advanced → Change history length to 200
   - Quit and relaunch app
   - Open Settings → Advanced → Verify value is 200

## Document Changes

### User-Facing Documentation

No new documentation files required. The feature maintains compatibility with original Hammerspoon console API, so existing Hammerspoon documentation applies:

- `hs.console.getHistory()` - https://www.hammerspoon.org/docs/hs.console.html#getHistory
- `hs.console.setHistory()` - https://www.hammerspoon.org/docs/hs.console.html#setHistory

### Code Documentation

All new public API methods include doc comments in the implementation:

1. **HSConsoleModuleAPI protocol** (HSConsoleModule.swift)
   - `/// Get the console command history`
   - `/// Set the console command history`
   - `/// Clear the console command history`

2. **ConsoleHistoryManager** (ConsoleHistoryManager.swift)
   - Class-level doc comment explaining singleton pattern and thread safety
   - Method-level comments for `append()`, `setHistory()`, `getHistory()`, `clearHistory()`

3. **SettingsAdvancedView** (SettingsAdvancedView.swift)
   - Inline comment explaining slider range (10-1000) and default (100)

### Internal Notes

Add MARK comments in modified files:

```swift
// ConsoleView.swift
// MARK: - Console History Integration

// HSConsoleModule.swift
// MARK: - Command History API

// ConsoleHistoryManager.swift
// MARK: - History Management
// MARK: - Size Limit Enforcement
```

## Git Log

```
feat: Implement console command history with JavaScript API

Add persistent command history support to Hammerspoon 2 console, achieving
feature parity with original Hammerspoon. Key changes:

- Create ConsoleHistoryManager singleton for centralized history storage
- Integrate history manager with ConsoleView for up/down arrow navigation
- Add hs.console.getHistory() and hs.console.setHistory() JavaScript API methods
- Implement configurable history size limit (10-1000 commands, default 100)
- Add "Console History Length" slider to Settings → Advanced tab
- Enforce FIFO removal when history exceeds configured limit

Implementation details:
- History is session-only (matches original Hammerspoon - not persisted to disk)
- Thread-safe access via @MainActor annotation
- ConsoleHistoryManager uses @Published property for reactive SwiftUI updates
- Size limit enforced on append via SettingsManager.consoleHistoryLength

Testing:
- Unit tests for ConsoleHistoryManager (append, limit enforcement, edge cases)
- Integration tests for JavaScript API (getHistory/setHistory/clearHistory)
- Manual validation of console navigation and settings UI

Files modified:
- Hammerspoon 2/Windows/ConsoleView.swift
- Hammerspoon 2/Modules/hs.console/HSConsoleModule.swift
- Hammerspoon 2/Windows/Settings/SettingsAdvancedView.swift

Files added:
- Hammerspoon 2/Managers/ConsoleHistoryManager.swift
- Hammerspoon 2Tests/Managers/ConsoleHistoryManagerTests.swift
- Hammerspoon 2Tests/Integration/HSConsoleModuleHistoryTests.swift

Closes #[issue-number]
```

## Notes

### Design Rationale

1. **Session-Only History**: Deliberately matches original Hammerspoon behavior. Users who want persistent history can implement it in their `init.js`:
   ```javascript
   // Example user script for persistent history
   const historyFile = "~/.config/Hammerspoon2/console_history.json";

   // Load on startup
   if (fs.exists(historyFile)) {
       const saved = JSON.parse(fs.read(historyFile));
       hs.console.setHistory(saved);
   }

   // Save on command execution (via custom wrapper)
   function saveHistory() {
       fs.write(historyFile, JSON.stringify(hs.console.getHistory()));
   }
   ```

2. **Size Limit Default (100)**: Matches the hardcoded limit in HammerspoonLog.entries (Logging.swift:72). This provides consistency across the application.

3. **Singleton Pattern**: ConsoleHistoryManager uses singleton to enable access from both ConsoleView (SwiftUI) and HSConsoleModule (Objective-C bridge). Alternative would be dependency injection, but singleton is simpler given single console instance.

4. **@MainActor Requirement**: All history operations must occur on main thread because:
   - ConsoleView state updates require main thread
   - @Published property changes trigger SwiftUI view updates
   - JavaScriptCore bridge methods may be called from any thread

5. **No Retroactive Trimming**: When user decreases history limit in settings, existing history beyond new limit is NOT immediately trimmed. Trimming occurs on next `append()` call. This prevents surprising data loss and matches typical circular buffer behavior.

### Differences from Original Hammerspoon

**None** - This implementation achieves 100% behavioral parity with original Hammerspoon console history:

- ✅ Session-only storage (no persistence)
- ✅ Unbounded growth within session (size limit is new, but configurable - can be set high)
- ✅ Up/down arrow navigation with same boundary behavior
- ✅ Cursor positioning at end of loaded command
- ✅ JavaScript API methods `getHistory()` and `setHistory()`
- ✅ Empty commands added to history
- ✅ No deduplication of consecutive duplicates

**Optional Enhancement (Future)**: The original Hammerspoon had `hs.console.maxOutputHistory()` for controlling log output scrollback (separate from command history). Hammerspoon 2 has a hardcoded 100-entry limit in HammerspoonLog (Logging.swift:72) with a FIXME comment. This could be exposed as a separate setting, but is out of scope for this feature.

### Testing Strategy

**Unit Tests** focus on ConsoleHistoryManager in isolation:
- Pure logic testing (append, setHistory, size limit)
- Mock SettingsManagerProtocol for controlled limit values
- Fast execution (no UI dependencies)

**Integration Tests** verify JavaScript bridge:
- JavaScriptCore context with real HSConsoleModule
- Type checking (JSValue → Swift type conversion)
- Thread safety verification

**Manual Tests** validate end-to-end UX:
- Console UI navigation (hardest to automate with SwiftUI)
- Settings UI updates (slider, persistence)
- Session lifecycle (app restart behavior)

### Performance Considerations

- **Memory**: History limited to user-configured size (10-1000 commands)
- **Array Operations**: FIFO removal uses `removeFirst()` which is O(n), but acceptable given small array sizes
- **Alternative**: Could use ring buffer for O(1) insertions, but adds complexity for minimal gain
- **Observation**: @Published property change triggers SwiftUI updates, but only ConsoleView observes (minimal overhead)

### Backward Compatibility

- **JavaScript API**: `hs.console.getHistory()` and `hs.console.setHistory()` are new to Hammerspoon 2, but match original Hammerspoon API exactly
- **User Scripts**: Any existing Hammerspoon init.lua scripts using console history can be ported to init.js by converting Lua array syntax to JavaScript:
  ```lua
  -- Lua (original)
  local history = hs.console.getHistory()
  hs.console.setHistory({"cmd1", "cmd2"})
  ```
  ```javascript
  // JavaScript (Hammerspoon 2)
  const history = hs.console.getHistory();
  hs.console.setHistory(["cmd1", "cmd2"]);
  ```

### Future Enhancements (Out of Scope)

1. **Persistent History**: Store history to disk (JSON file in `~/.config/Hammerspoon2/`)
2. **History Search**: Ctrl+R reverse search (like Bash)
3. **Smart Deduplication**: Option to ignore consecutive duplicates
4. **History Timestamps**: Store execution time with each command
5. **Multi-Session Isolation**: Separate history per console window instance
6. **Import/Export**: Bulk history management tools
7. **Max Output History Setting**: Expose HammerspoonLog limit as configurable setting

These should be considered as separate features, not part of core history parity with original Hammerspoon.
