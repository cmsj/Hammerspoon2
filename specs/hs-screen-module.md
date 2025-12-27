# Feature: hs.screen Module

## Chore Description

Implement a complete `hs.screen` module for Hammerspoon 2 that provides comprehensive screen/monitor management capabilities. This module will enable JavaScript user scripts to discover, query, and manipulate connected displays including resolution management, brightness control, gamma correction, screen arrangement, rotation, mirroring, and change monitoring.

The implementation must achieve **functional parity** with the original Hammerspoon `hs.screen` module (implemented in `hs_repo_old/extensions/screen/`), adapted to Hammerspoon 2's Swift-based architecture with JavaScriptCore bridging.

### Current State

**Status**: The `hs.screen` module **does not exist** in Hammerspoon 2.

**Evidence**:
- No `hs.screen` module registered in `ModuleRoot.swift`
- No `/Hammerspoon 2/Modules/hs.screen/` directory exists
- NSScreen is only used ad-hoc in 3 files for basic positioning:
  - `AlertModule.swift` - uses `NSScreen.main` for alert positioning
  - `HSWindow.swift` - uses `NSScreen.main` for window centering
  - `WindowModule.swift` - uses `NSScreen.screens` for filtering windows by screen index

**Partial Implementation**: The module `hs.window` has a single screen-related method:
- `windowsOnScreen(_ screenIndex: Int)` - filters windows by screen index (0 = main screen)

This is insufficient for screen management and will be superseded by proper screen object support.

### Ground Truth: Original Hammerspoon Implementation

The original Hammerspoon `hs.screen` module consists of:

**Core Implementation** (`hs_repo_old/extensions/screen/`):
1. **libscreen.m** (~1470 lines Objective-C)
   - Bridges NSScreen to Lua userdata
   - Implements 40+ screen-related functions
   - Uses CoreGraphics private APIs for advanced features (rotation, mode setting, gamma)
   - Integrates with IOKit for brightness control
   - Uses DisplayServices framework for brightness on newer macOS

2. **screen.lua** (~427 lines Lua)
   - Higher-level convenience functions built on C primitives
   - Screen finding/filtering logic
   - Coordinate system transformations
   - Screen positioning algorithms (toEast, toWest, toNorth, toSouth)
   - Unit rect conversions

3. **libscreen_watcher.m** (~245 lines Objective-C)
   - Monitors screen configuration changes
   - Provides `hs.screen.watcher` for detecting display events

**Key Behavioral Characteristics**:

1. **Coordinate System**:
   - Origin (0,0) is at top-left of **primary screen** (screen containing menu bar)
   - Screens to the left/above primary have negative coordinates
   - All coordinates are in "points" (not pixels) to handle HiDPI/Retina displays
   - Primary screen determined by `[NSScreen screens][0]` (main display)

2. **Screen Identity**:
   - Each screen has a unique `CGDirectDisplayID` (integer)
   - UUIDs available via `CGDisplayCreateUUIDFromDisplayID`
   - Screen names from IOKit display info dictionary
   - Screens persist across disconnection/reconnection by UUID

3. **Frame Types**:
   - `fullFrame()`: Entire screen including menu bar and dock
   - `frame()`: Visible area excluding menu bar and dock (from `visibleFrame`)
   - Y-coordinates inverted: macOS uses bottom-left origin, Hammerspoon uses top-left

4. **Display Modes**:
   - Private CGS APIs used: `CGSGetNumberOfDisplayModes`, `CGSGetDisplayModeDescriptionOfLength`, `CGSConfigureDisplayMode`
   - Modes identified by: width, height, scale (1x/2x), refresh rate (Hz), bit depth
   - HiDPI modes report "points" dimensions (e.g., 1440x900@2x = 2880x1800 pixels)

5. **Brightness Control**:
   - Preferred API: `CoreDisplay_Display_SetUserBrightness` (semi-private, better Night Shift integration)
   - Fallback: `DisplayServicesSetBrightness` from DisplayServices.framework
   - Legacy: IOKit `IODisplaySetFloatParameter` with `kIODisplayBrightnessKey`
   - Returns nil for displays without brightness control (external monitors)

6. **Gamma Management**:
   - Stores original gamma tables on module load via `CGGetDisplayTransferByTable`
   - Custom gamma via `CGSetDisplayTransferByTable`
   - Gamma persists via display reconfiguration callback
   - Restoration via `CGDisplayRestoreColorSyncSettings`

7. **Screen Arrangement**:
   - Setting primary screen moves all displays to maintain relative positions
   - `setOrigin(x, y)` uses `CGConfigureDisplayOrigin`
   - Mirroring via `CGConfigureDisplayMirrorOfDisplay`

## Relevant Files

### Existing Files to Reference

- **Hammerspoon 2/Engine/ModuleRoot.swift**
  - Module registration point - add `@objc var screen: HSScreenModule { get }` property
  - Register in `ModuleRootAPI` protocol
  - Implement lazy loading via `getOrCreate(name: "screen", type: HSScreenModule.self)`

- **Hammerspoon 2/Protocols/HSModuleAPI.swift**
  - Base protocol all modules implement
  - Defines `name`, `init()`, `shutdown()` requirements

- **Hammerspoon 2/Protocols/HSTypeAPI.swift**
  - Base protocol for types exposed to JavaScript
  - Defines `typeName` property requirement

- **Hammerspoon 2/Engine/Types/HSRect.swift, HSPoint.swift, HSSize.swift**
  - Existing geometric types for frame/position representation
  - Used for screen frame, position, and size properties

- **Hammerspoon 2/Modules/hs.window/WindowModule.swift**
  - Example module implementation pattern
  - Shows MainActor usage, shutdown pattern, JSExport protocol structure

- **Hammerspoon 2/Modules/hs.window/HSWindow.swift**
  - Example object type implementation
  - Pattern for wrapping native objects (UIElement) in exportable class

- **Hammerspoon 2/Modules/hs.application/ApplicationModule.swift**
  - Example of watcher implementation pattern
  - Shows event callback registration and cleanup

- **Hammerspoon 2/Utilities/AKLog.swift**
  - Logging functions: `AKTrace()`, `AKInfo()`, `AKError()`

- **hs_repo_old/extensions/screen/libscreen.m**
  - Reference implementation for all native screen operations
  - CoreGraphics API usage patterns
  - Private API declarations and usage

- **hs_repo_old/extensions/screen/screen.lua**
  - Reference for higher-level screen logic
  - Algorithms for screen finding, positioning, direction calculation

- **hs_repo_old/extensions/screen/libscreen_watcher.m**
  - Reference for screen change notification handling

- **hs_repo_old/extensions/screen/test_screen.lua**
  - Comprehensive test cases showing expected behavior
  - Edge cases and usage patterns

### New Files

#### Hammerspoon 2/Modules/hs.screen/ScreenModule.swift
- Main module implementation conforming to `HSModuleAPI`
- `HSScreenModuleAPI` protocol extending `JSExport` with module-level functions:
  - `allScreens()` → `[HSScreen]`
  - `mainScreen()` → `HSScreen?` (screen with focused window)
  - `primaryScreen()` → `HSScreen?` (screen at index 0, contains menu bar)
  - `find(_ hint: Any)` → `HSScreen?` (find by ID, name, UUID, position, resolution, rect)
  - `screenPositions()` → `[String: [String: Double]]` (screen positions as dictionary)
  - `restoreGamma()` (restore all screens to default gamma)
  - `accessibilitySettings()` → `[String: Bool]` (get accessibility display settings)
  - `getForceToGray()` / `setForceToGray(_ enabled: Bool)` (grayscale mode)
  - `getInvertedPolarity()` / `setInvertedPolarity(_ enabled: Bool)` (invert colors)
  - `strictScreenInDirection: Bool` (class variable for direction finding)
- `HSScreenModule` class implementing API
- Private helper methods for gamma management, display reconfiguration callbacks
- Maintain dictionaries of original and current gamma tables
- Display reconfiguration callback registration

#### Hammerspoon 2/Modules/hs.screen/HSScreen.swift
- Screen object conforming to `HSTypeAPI`
- `HSScreenAPI` protocol extending `JSExport` with screen instance methods:
  - `id()` → `Int` (CGDirectDisplayID)
  - `name()` → `String?` (localized display name)
  - `uuid()` → `String?` (UUID string)
  - `position()` → `HSPoint?` (position relative to primary)
  - `fullFrame()` → `HSRect?` (entire screen including menu/dock)
  - `frame()` → `HSRect?` (visible area excluding menu/dock)
  - `currentMode()` → `[String: Any]?` (current display mode info)
  - `availableModes()` → `[String: [String: Any]]` (all available modes)
  - `setMode(_ width: Int, _ height: Int, _ scale: Double, _ freq: Int, _ depth: Int)` → `Bool`
  - `getBrightness()` → `Double?` (0.0 to 1.0, nil if unsupported)
  - `setBrightness(_ level: Double)` → `HSScreen?` (returns self for chaining)
  - `getGamma()` → `[String: [String: Double]]?` (whitepoint/blackpoint tables)
  - `setGamma(_ whitepoint: [String: Double], _ blackpoint: [String: Double])` → `Bool`
  - `rotate(_ degrees: Int?)` → `Any` (get/set rotation: 0, 90, 180, 270)
  - `setPrimary()` → `Bool` (make this screen the primary)
  - `setOrigin(_ x: Int, _ y: Int)` → `Bool` (set screen position)
  - `next()` → `HSScreen?` (next screen in array)
  - `previous()` → `HSScreen?` (previous screen in array)
  - `toEast(_ from: HSPoint?, _ strict: Bool)` → `HSScreen?`
  - `toWest(_ from: HSPoint?, _ strict: Bool)` → `HSScreen?`
  - `toNorth(_ from: HSPoint?, _ strict: Bool)` → `HSScreen?`
  - `toSouth(_ from: HSPoint?, _ strict: Bool)` → `HSScreen?`
  - `fromUnitRect(_ unitRect: HSRect)` → `HSRect?` (convert unit rect to absolute)
  - `toUnitRect(_ rect: HSRect)` → `HSRect?` (convert absolute rect to unit)
  - `localToAbsolute(_ geom: Any)` → `Any` (local coords → absolute coords)
  - `absoluteToLocal(_ geom: Any)` → `Any` (absolute coords → local coords)
  - `snapshot(_ rect: HSRect?)` → `Any?` (capture screen image, requires hs.image)
  - `desktopImageURL(_ url: String?)` → `Any` (get/set desktop background)
  - `getInfo()` → `[String: Any]?` (IOKit display info)
  - `mirrorOf(_ screen: HSScreen, _ permanent: Bool)` → `Bool` (mirror another screen)
  - `mirrorStop(_ permanent: Bool)` → `Bool` (stop mirroring)
- Wraps `NSScreen` instance
- Caches `CGDirectDisplayID` for CoreGraphics operations
- Handles coordinate system conversions (NSScreen uses bottom-left, we use top-left)

#### Hammerspoon 2/Modules/hs.screen/ScreenWatcher.swift
- Watcher object for screen change notifications
- `HSScreenWatcherAPI` protocol extending `JSExport`:
  - `init(_ callback: JSValue)` (constructor)
  - `start()` → `HSScreenWatcher` (begin watching)
  - `stop()` → `HSScreenWatcher` (stop watching)
- `HSScreenWatcher` class
- Observes `NSApplication.didChangeScreenParametersNotification`
- Optional: observes `NSWorkspaceActiveDisplayDidChangeNotification` (undocumented)
- Invokes JavaScript callback on screen events
- Cleanup on stop/deinit

#### Hammerspoon 2/Modules/hs.screen/hs.screen.js
- JavaScript convenience layer (optional)
- Helper functions for common operations:
  - `hs.screen(hint)` - shorthand for `hs.screen.find(hint)`
  - Screen positioning helpers
  - Integration with EventEmitter if needed

## Step by Step Tasks

### 1. Create Module Directory and Base Structure

- Create directory `/Hammerspoon 2/Modules/hs.screen/`
- Create `ScreenModule.swift` with module skeleton:
  - Import Foundation, JavaScriptCore, AppKit, CoreGraphics
  - Define `HSScreenModuleAPI` protocol inheriting from `JSExport`
  - Implement `HSScreenModule` class conforming to `HSModuleAPI` and `HSScreenModuleAPI`
  - Mark class with `@MainActor` for AppKit thread safety
  - Implement required `name`, `init()`, `shutdown()` methods
  - Add placeholder `deinit` with logging
- Add module to Xcode project in `Hammerspoon 2/Modules/hs.screen/` group

### 2. Implement Screen Object Type

- Create `HSScreen.swift` with screen object:
  - Define `HSScreenAPI` protocol inheriting from `HSTypeAPI` and `JSExport`
  - Implement `HSScreen` class wrapping `NSScreen`
  - Store `NSScreen` reference and cached `CGDirectDisplayID`
  - Implement `typeName` property returning "HSScreen"
  - Add `deinit` with logging
- Implement basic identity methods:
  - `id()` - return CGDirectDisplayID from screen's device description
  - `name()` - return localized name (use `screen.localizedName` on macOS 10.15+, fallback to IOKit)
  - `uuid()` - use `CGDisplayCreateUUIDFromDisplayID` and `CFUUIDCreateString`
- Add to Xcode project

### 3. Implement Core Discovery Functions

- In `ScreenModule.swift`, implement:
  - `allScreens()` - map `NSScreen.screens` to `[HSScreen]` array
  - `mainScreen()` - wrap `NSScreen.main` (screen with key window)
  - `primaryScreen()` - wrap `NSScreen.screens[0]` (screen with menu bar at top-left)
- Handle empty screen array gracefully (return nil/empty as appropriate)

### 4. Implement Frame and Geometry Methods

- In `HSScreen.swift`, implement:
  - `fullFrame()` - return `HSRect` from NSScreen frame
    - Get screen frame via `screen.frame`
    - Convert Y coordinate (NSScreen is bottom-left origin, we use top-left)
    - Formula: `y_hs = primaryScreen.frame.height - screen.frame.height - y_ns`
    - Return `HSRect` with converted coordinates
  - `frame()` - return `HSRect` from NSScreen visible frame
    - Use `screen.visibleFrame` (excludes menu bar and dock)
    - Apply same Y-coordinate conversion
    - Return `HSRect` with converted coordinates
  - `position()` - calculate screen position relative to primary
    - Call module-level `screenPositions()` helper
    - Find this screen in the dictionary
    - Return `HSPoint` with x, y coordinates
- Implement coordinate conversion helpers:
  - `fromUnitRect(_ unitRect: HSRect)` - convert unit rect (0-1) to absolute coordinates
    - Use screen's `frame()` as reference
    - Formula: `absolute = frame.origin + (unitRect * frame.size)`
  - `toUnitRect(_ rect: HSRect)` - convert absolute rect to unit coordinates
    - Use screen's `frame()` as reference
    - Formula: `unit = (rect - frame.origin) / frame.size`
  - `localToAbsolute(_ geom: Any)` - add screen's fullFrame origin to point/rect
  - `absoluteToLocal(_ geom: Any)` - subtract screen's fullFrame origin from point/rect

### 5. Implement Screen Positioning and Navigation

- In `ScreenModule.swift`, implement:
  - `screenPositions()` - calculate relative positions of all screens
    - Port algorithm from `screen.lua:screenPositions()`
    - Start with primary screen at {x:0, y:0}
    - Recursively find neighbors in each direction (East/West/North/South)
    - Use screen frame intersection to determine adjacency
    - Return dictionary mapping screen ID to position
- In `HSScreen.swift`, implement:
  - `next()` - get next screen in `allScreens()` array, wrapping to first
  - `previous()` - get previous screen in `allScreens()` array, wrapping to last
  - Private helper `firstScreenInDirection(numRotations, fromPoint, strict, allScreens)`
    - Port from `screen.lua:first_screen_in_direction`
    - Use angle-based scoring: `score = distance / cos(angle/2)`
    - Filter by perpendicular overlap if `strict` or module's `strictScreenInDirection`
    - Return closest screen in specified direction
  - `toEast(from, strict)` - call helper with rotation 0
  - `toWest(from, strict)` - call helper with rotation 2 (180°)
  - `toNorth(from, strict)` - call helper with rotation 1 (90° CCW)
  - `toSouth(from, strict)` - call helper with rotation 3 (270° CCW)
- Add `strictScreenInDirection` as static variable on module (default: false)

### 6. Implement Find Function

- In `ScreenModule.swift`, implement:
  - `find(_ hint: Any)` - flexible screen finding
    - Accept JSValue and extract underlying Swift value
    - If hint is HSScreen, return it unchanged
    - If hint is Int/Double, find by display ID
    - If hint is String:
      - Try UUID match first (`screen.uuid() == hint`)
      - Try case-insensitive substring match on name
    - If hint is HSPoint (or dict/array convertible to point):
      - Look up in `screenPositions()` dictionary
    - If hint is HSSize (or dict/array convertible to size):
      - Find screen with matching `fullFrame().size`
    - If hint is HSRect (or dict/array convertible to rect):
      - Find screen with largest intersection area
      - If no intersection, find closest screen by center-to-center distance
    - Return first match, or nil if not found
- Handle type conversions robustly (check JSValue type before extraction)

### 7. Implement Display Mode Management

- In `HSScreen.swift`, implement display mode functions using CoreGraphics private APIs:
  - Declare private C functions at top of file:
    ```swift
    @_silgen_name("CGSGetCurrentDisplayMode")
    func CGSGetCurrentDisplayMode(_ display: CGDirectDisplayID, _ modeNum: UnsafeMutablePointer<Int32>) -> Void

    @_silgen_name("CGSGetNumberOfDisplayModes")
    func CGSGetNumberOfDisplayModes(_ display: CGDirectDisplayID, _ count: UnsafeMutablePointer<Int32>) -> Void

    @_silgen_name("CGSGetDisplayModeDescriptionOfLength")
    func CGSGetDisplayModeDescriptionOfLength(_ display: CGDirectDisplayID, _ index: Int32, _ mode: UnsafeMutablePointer<CGSDisplayMode>, _ length: Int32) -> Void

    @_silgen_name("CGSConfigureDisplayMode")
    func CGSConfigureDisplayMode(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ modeNum: Int32) -> Void
    ```
  - Define `CGSDisplayMode` struct (matches original):
    ```swift
    struct CGSDisplayMode {
        var modeNumber: UInt32
        var flags: UInt32
        var width: UInt32
        var height: UInt32
        var depth: UInt32
        var unknown: (UInt8, ..., UInt8) // 170 bytes
        var freq: UInt16
        var more_unknown: (UInt8, ..., UInt8) // 16 bytes
        var density: Float
    }
    ```
  - `currentMode()` - return current display mode
    - Get CGDirectDisplayID
    - Call `CGSGetCurrentDisplayMode` to get mode number
    - Call `CGSGetDisplayModeDescriptionOfLength` to get mode details
    - Return dict with keys: `w`, `h`, `scale`, `freq`, `depth`, `desc`
  - `availableModes()` - return all supported modes
    - Call `CGSGetNumberOfDisplayModes` to get count
    - Iterate calling `CGSGetDisplayModeDescriptionOfLength` for each index
    - Build dictionary keyed by mode description string (e.g., "1920x1080@2x 60Hz 32bpp")
    - Each value is dict with keys: `w`, `h`, `scale`, `freq`, `depth`
  - `setMode(width, height, scale, freq, depth)` - change display mode
    - Iterate through available modes to find exact match
    - If found, use `CGBeginDisplayConfiguration`, `CGSConfigureDisplayMode`, `CGCompleteDisplayConfiguration`
    - Use `kCGConfigurePermanently` flag
    - Return true on success, false on failure

### 8. Implement Brightness Control

- In `HSScreen.swift`, implement brightness methods with fallback chain:
  - Declare private C functions:
    ```swift
    @_silgen_name("CoreDisplay_Display_GetUserBrightness")
    func CoreDisplay_Display_GetUserBrightness(_ display: CGDirectDisplayID) -> Double

    @_silgen_name("CoreDisplay_Display_SetUserBrightness")
    func CoreDisplay_Display_SetUserBrightness(_ display: CGDirectDisplayID, _ brightness: Double) -> Void

    @_silgen_name("DisplayServicesGetBrightness")
    func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

    @_silgen_name("DisplayServicesSetBrightness")
    func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32
    ```
  - `getBrightness()` - get current brightness
    - Try `CoreDisplay_Display_GetUserBrightness` first (preferred, better Night Shift support)
    - If not available, try `DisplayServicesGetBrightness`
    - If not available, try IOKit `IODisplayGetFloatParameter` with `kIODisplayBrightnessKey`
    - Return Double between 0.0 and 1.0, or nil if unsupported
  - `setBrightness(_ level: Double)` - set brightness
    - Clamp level to 0.0...1.0 range
    - Try same fallback chain as getter
    - Return self for method chaining
- Add weak import attributes for safety:
  ```swift
  #if canImport(DisplayServices)
  // DisplayServices functions
  #endif
  ```

### 9. Implement Gamma Correction

- In `ScreenModule.swift`, add gamma management infrastructure:
  - Add instance variables:
    ```swift
    private var originalGammas: [CGDirectDisplayID: GammaTable] = [:]
    private var currentGammas: [CGDirectDisplayID: GammaTable] = [:]
    ```
  - Define `GammaTable` struct:
    ```swift
    struct GammaTable {
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]
    }
    ```
  - In `init()`, call `getAllInitialScreenGammas()` to store original gamma tables
  - Implement `getAllInitialScreenGammas()`:
    - Get all active displays via `CGGetActiveDisplayList`
    - For each display, call `storeInitialScreenGamma(displayID)`
  - Implement `storeInitialScreenGamma(_ displayID: CGDirectDisplayID)`:
    - Get gamma capacity via `CGDisplayGammaTableCapacity`
    - Allocate arrays for red/green/blue tables
    - Call `CGGetDisplayTransferByTable` to fetch current gamma
    - Store in `originalGammas` dictionary
  - Register display reconfiguration callback:
    - Call `CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)`
    - Implement callback to handle display add/remove/reconfigure events
    - On add: store initial gamma
    - On remove: delete stored gammas
    - On reconfigure: re-apply current gamma after 3 second delay
  - `restoreGamma()` - restore all screens to default
    - Call `CGDisplayRestoreColorSyncSettings()`
    - Clear `currentGammas` dictionary
  - In `shutdown()`:
    - Call `CGDisplayRemoveReconfigurationCallback`
    - Call `restoreGamma()`
- In `HSScreen.swift`, implement screen-specific gamma:
  - `getGamma()` - get current gamma tables
    - Call `CGGetDisplayTransferByTable` for this screen's display ID
    - Return dict with `whitepoint` and `blackpoint` keys
    - Each contains dict with `red`, `green`, `blue` keys (values 0.0 to 1.0)
  - `setGamma(whitepoint, blackpoint)` - set custom gamma
    - Fetch original gamma from module's `originalGammas` dictionary
    - For each sample point, calculate: `new = blackpoint + (whitepoint - blackpoint) * original`
    - Call `CGSetDisplayTransferByTable` with computed tables
    - Store in module's `currentGammas` dictionary
    - Return true on success, false on failure

### 10. Implement Screen Arrangement Functions

- In `HSScreen.swift`, implement:
  - `setPrimary()` - make this screen the primary (contain menu bar at 0,0)
    - If already primary, return true (no-op)
    - Calculate delta to move this screen to origin: `deltaX = -frame.x`, `deltaY = -frame.y`
    - Get all online displays via `CGGetOnlineDisplayList`
    - Begin display configuration: `CGBeginDisplayConfiguration`
    - For each display, call `CGConfigureDisplayOrigin` with adjusted position
    - Complete configuration: `CGCompleteDisplayConfiguration(config, kCGConfigureForSession)`
    - Return true on success, false on error
  - `setOrigin(x, y)` - set screen position in global coordinate space
    - Begin display configuration
    - Call `CGConfigureDisplayOrigin(config, displayID, x, y)`
    - Complete configuration with `kCGConfigurePermanently`
    - Return true on success, false on error
  - `rotate(_ degrees: Int?)` - get or set screen rotation
    - If `degrees` is nil, return current rotation via `CGDisplayRotation`
    - If `degrees` provided, must be 0, 90, 180, or 270
    - Map to IOKit constants: `kIOScaleRotate0`, `kIOScaleRotate90`, etc.
    - Get IO service port: `CGDisplayIOServicePort` (deprecated but necessary)
    - Set options: `kIOFBSetTransform | (rotation << 16)`
    - Call `IOServiceRequestProbe(service, options)`
    - Return true on success, false on error
  - `mirrorOf(screen, permanent)` - mirror another screen
    - Get source and target display IDs
    - Begin display configuration
    - Call `CGConfigureDisplayMirrorOfDisplay(config, targetID, sourceID)`
    - Complete with `kCGConfigurePermanently` or `kCGConfigureForSession` based on `permanent`
    - Return true on success
  - `mirrorStop(permanent)` - stop mirroring
    - Begin display configuration
    - Call `CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)`
    - Complete configuration
    - Return true on success

### 11. Implement Advanced Features

- In `ScreenModule.swift`, implement global display settings:
  - Declare private C functions:
    ```swift
    @_silgen_name("CGDisplayUsesForceToGray")
    func CGDisplayUsesForceToGray() -> Bool

    @_silgen_name("CGDisplayForceToGray")
    func CGDisplayForceToGray(_ forceToGray: Bool) -> Void

    @_silgen_name("CGDisplayUsesInvertedPolarity")
    func CGDisplayUsesInvertedPolarity() -> Bool

    @_silgen_name("CGDisplaySetInvertedPolarity")
    func CGDisplaySetInvertedPolarity(_ invertedPolarity: Bool) -> Void
    ```
  - `getForceToGray()` - check if grayscale mode enabled
  - `setForceToGray(_ enabled: Bool)` - toggle grayscale mode
  - `getInvertedPolarity()` - check if colors inverted
  - `setInvertedPolarity(_ enabled: Bool)` - toggle color inversion
  - `accessibilitySettings()` - get display accessibility settings
    - Use `NSWorkspace.shared` to check settings
    - Return dict with keys: `ReduceMotion`, `ReduceTransparency`, `IncreaseContrast`, `InvertColors`, `DifferentiateWithoutColor`
    - Each value is Bool
    - Note: some properties require macOS 10.12+ (check availability)
- In `HSScreen.swift`, implement:
  - `getInfo()` - get IOKit display information
    - Get IO service port: `CGDisplayIOServicePort`
    - Call `IODisplayCreateInfoDictionary(service, kIODisplayOnlyPreferredName)`
    - Return dictionary as-is (contains manufacturer info, serial, etc.)
  - `desktopImageURL(_ url: String?)` - get/set desktop background
    - If `url` is nil, return current URL via `NSWorkspace.shared.desktopImageURL(for: screen)`
    - If `url` provided:
      - Convert string to `URL`
      - Call `NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:], error: &error)`
      - Return self for chaining
  - `snapshot(_ rect: HSRect?)` - capture screen image
    - Get display ID
    - If `rect` is nil, use entire screen frame
    - Otherwise, convert HSRect to CGRect
    - Call `CGDisplayCreateImageForRect(displayID, rect)`
    - Convert CGImage to NSImage
    - Return as hs.image object (requires hs.image module integration)
    - NOTE: This method returns `Any?` to avoid direct dependency on hs.image module

### 12. Implement Screen Watcher

- Create `ScreenWatcher.swift`:
  - Define `HSScreenWatcherAPI` protocol:
    - `start()` → `HSScreenWatcher`
    - `stop()` → `HSScreenWatcher`
  - Implement `HSScreenWatcher` class:
    - Store JSValue callback reference
    - Store running state boolean
    - `init(_ callback: JSValue)` - store callback
    - `start()` - register for notifications:
      - `NSApplication.didChangeScreenParametersNotification` (screen layout changes)
      - Optionally: `NSWorkspaceActiveDisplayDidChangeNotification` (active screen changes, undocumented API)
    - `stop()` - unregister notifications
    - Notification handler: invoke JavaScript callback when fired
    - `deinit` - ensure stopped and callback released
  - Add to Xcode project
- In `ScreenModule.swift`:
  - Add to API protocol: `@objc func watcher(_ callback: JSValue) -> HSScreenWatcher`
  - Implement: `func watcher(_ callback: JSValue) -> HSScreenWatcher`
    - Create and return new `HSScreenWatcher` instance

### 13. Register Module in ModuleRoot

- Edit `Hammerspoon 2/Engine/ModuleRoot.swift`:
  - Add to `ModuleRootAPI` protocol:
    ```swift
    @objc var screen: HSScreenModule { get }
    ```
  - Add to `ModuleRoot` class:
    ```swift
    @objc var screen: HSScreenModule {
        get { getOrCreate(name: "screen", type: HSScreenModule.self) }
    }
    ```

### 14. Add JavaScript Convenience Layer (Optional)

- Create `hs.screen.js` in module directory:
  - Add shorthand: `hs.screen = (function(base) { ... })(hs.screen);`
  - Implement call operator: Allow `hs.screen(hint)` as alias for `hs.screen.find(hint)`
  - Export any helper functions if needed
- Ensure file is included in Xcode project's "Copy Bundle Resources" build phase

### 15. Testing and Validation

- Run validation commands to ensure zero regressions
- Test each API function individually
- Verify coordinate system conversions
- Test multi-monitor scenarios
- Test brightness on supported displays
- Test gamma changes and restoration
- Test screen arrangement modifications
- Test screen watchers
- Verify cleanup in shutdown

### 16. Run Validation Commands

Execute every validation command listed below to confirm implementation is complete with zero regressions.

## Validation Commands

Execute every command to validate the chore is complete with zero regressions.

```bash
# Build the project to ensure no compilation errors
cd /Users/dmg/git.w/hs2/Hammerspoon2
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug clean build

# Run unit tests if they exist
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" -configuration Debug test

# Manual testing via REPL (after launching app):
# Test 1: Module loads
# > hs.screen
# Expected: [object HSScreenModule]

# Test 2: Get all screens
# > hs.screen.allScreens()
# Expected: Array of HSScreen objects

# Test 3: Get primary screen
# > var primary = hs.screen.primaryScreen()
# > primary.id()
# Expected: Number (display ID)

# Test 4: Get screen name
# > primary.name()
# Expected: String (e.g., "Built-in Retina Display")

# Test 5: Get screen frames
# > primary.fullFrame()
# Expected: HSRect object with x, y, w, h properties
# > primary.frame()
# Expected: HSRect object (smaller than fullFrame if menu bar/dock present)

# Test 6: Find screen by ID
# > var id = primary.id()
# > hs.screen.find(id)
# Expected: Same screen object

# Test 7: Find screen by name substring
# > hs.screen.find("Built")
# Expected: Screen object or nil

# Test 8: Get current mode
# > primary.currentMode()
# Expected: Object with w, h, scale, freq, depth properties

# Test 9: Get available modes
# > primary.availableModes()
# Expected: Object with mode strings as keys

# Test 10: Get/set brightness (if supported)
# > var brightness = primary.getBrightness()
# > primary.setBrightness(0.5)
# > primary.getBrightness()
# Expected: 0.5 (approximately)

# Test 11: Screen positions
# > hs.screen.screenPositions()
# Expected: Dictionary mapping screens to {x, y} positions

# Test 12: Navigation
# > primary.next()
# Expected: HSScreen object (wraps if single screen)
# > primary.toEast()
# Expected: HSScreen object or nil

# Test 13: Coordinate conversions
# > var unitRect = primary.toUnitRect(primary.frame())
# Expected: HSRect with x=0, y=0, w=1, h=1
# > primary.fromUnitRect(unitRect)
# Expected: Original frame

# Test 14: Gamma (verify get works, don't modify)
# > primary.getGamma()
# Expected: Object with whitepoint and blackpoint

# Test 15: Screen watcher
# > var watcher = hs.screen.watcher(function() { console.log("Screen changed!"); })
# > watcher.start()
# Expected: Watcher object
# > watcher.stop()
# Expected: Watcher object

# Test 16: Accessibility settings
# > hs.screen.accessibilitySettings()
# Expected: Object with boolean properties

# Test 17: Verify no crashes on shutdown
# > hs.reload()
# Expected: Clean shutdown and reload
```

## Document changes

Update documentation to reflect the new hs.screen module:

1. **Add module documentation** to any existing API reference:
   - Document all module-level functions with parameters, return types, and examples
   - Document all screen object methods with usage examples
   - Document screen watcher with callback signature and event types
   - Include notes about coordinate system (top-left origin at primary screen)
   - Include notes about "points" vs "pixels" for Retina displays
   - Include warnings about gamma modification (can make screen unreadable)
   - Include warnings about rotation (may not be supported on all displays)

2. **Update CLAUDE.md** (project LLM developer guide):
   - Add `hs.screen` to the "Implemented Modules" section
   - Include key implementation details:
     - CoreGraphics private API usage
     - Coordinate system transformations
     - Gamma management infrastructure
     - Brightness fallback chain
     - Screen watcher notification types
   - Add file references to "Key File Reference" section

3. **Create example configurations** showing common use cases:
   - Multi-monitor window management using screen positions
   - Brightness scheduling (dim at night)
   - Screen arrangement on laptop dock/undock
   - Detecting external monitor connection

## Git log

```
Implement hs.screen module for display management

Add comprehensive screen/monitor management module to Hammerspoon 2,
achieving functional parity with original Hammerspoon's hs.screen.

Core components:
- ScreenModule.swift: Module-level functions for screen discovery, finding,
  and global settings (gamma restore, accessibility, force-to-gray, inverted
  polarity)
- HSScreen.swift: Screen object wrapping NSScreen with CoreGraphics/IOKit
  integration for advanced display control
- ScreenWatcher.swift: Monitor screen configuration change notifications

Key features:
- Screen discovery: allScreens(), mainScreen(), primaryScreen(), find()
- Geometry: fullFrame(), frame(), position(), coordinate conversions
- Display modes: currentMode(), availableModes(), setMode()
- Brightness: getBrightness(), setBrightness() with multi-tier fallback
- Gamma: getGamma(), setGamma(), restoreGamma() with persistence
- Arrangement: setPrimary(), setOrigin(), rotation, mirroring
- Navigation: next(), previous(), toEast/West/North/South()
- Snapshots: snapshot() for screen capture
- Watchers: Monitor screen add/remove/reconfigure events

Implementation notes:
- Uses CoreGraphics private APIs (CGS*) for display mode management
- Uses DisplayServices/CoreDisplay private APIs for brightness control
- Implements gamma persistence across display reconfiguration
- Handles macOS coordinate system conversion (bottom-left → top-left)
- Supports both "points" and "pixels" for Retina display compatibility
- Thread-safe with @MainActor for AppKit integration

Closes #[issue number if applicable]
```

## Notes

### Critical Implementation Considerations

1. **Private API Usage**:
   - This module relies heavily on CoreGraphics private APIs (CGS* functions, CoreDisplay* functions)
   - These APIs are undocumented and may change between macOS versions
   - Use `@_silgen_name` for symbol linking instead of direct imports
   - Consider weak import attributes for graceful degradation
   - Test thoroughly on target macOS versions (Sequoia+)

2. **Coordinate System Complexity**:
   - NSScreen uses bottom-left origin, Hammerspoon uses top-left
   - Y-coordinate conversion formula: `y_hs = primaryScreenHeight - frameHeight - y_ns`
   - All public APIs must return top-left coordinates
   - Internal NSScreen operations use bottom-left
   - Be consistent in conversion points

3. **Gamma Management Lifecycle**:
   - Original gamma tables MUST be stored on module load
   - Display reconfiguration callback MUST re-apply custom gamma after delays
   - Shutdown MUST restore original gamma to avoid leaving screens modified
   - Use 3-second delay when re-applying after reconfiguration (OS needs settling time)

4. **Thread Safety**:
   - Mark module with `@MainActor` - AppKit/CoreGraphics require main thread
   - Ensure watcher callbacks dispatch to main queue if needed
   - JSValue callbacks should be invoked on main thread

5. **Error Handling**:
   - Many CoreGraphics functions return error codes - check them
   - Brightness functions return nil for unsupported displays (don't error)
   - Mode setting may fail even for "valid" modes - CoreGraphics is picky
   - Log errors using `AKError()` for debugging

6. **Memory Management**:
   - Gamma tables use malloc'd C arrays - must free them
   - CFTypes (UUID) must be released with CFRelease
   - Bridged NSObjects handled by ARC
   - Display reconfiguration callback must not retain self strongly

7. **Compatibility Notes**:
   - `screen.localizedName` requires macOS 10.15+, fallback to IOKit needed
   - `CGDisplayIOServicePort` is deprecated but still necessary for some operations
   - DisplayServices brightness functions may not be available on all systems
   - Night Shift integration requires CoreDisplay_Display_SetUserBrightness

8. **Testing Challenges**:
   - Single-monitor setups can't test multi-screen features
   - External monitors may not support brightness control
   - Rotation may not work on all displays
   - Gamma changes can make screen unusable if wrong values used
   - Display mode changes can cause temporary blackouts

9. **Optional Integration**:
   - `snapshot()` method depends on `hs.image` module existing
   - Return `Any?` to avoid hard dependency
   - Document that snapshot returns hs.image object if available

10. **JavaScript API Design**:
    - Follow existing patterns from hs.window, hs.application
    - Use HSRect/HSPoint/HSSize for consistency
    - Return self for chaining on setters (e.g., `setBrightness()`)
    - Return nil for not-found/unsupported rather than throwing

11. **Performance**:
    - Cache display IDs to avoid repeated dictionary lookups
    - Don't re-fetch all screens on every call
    - Screen position calculation is O(n²) but acceptable for typical screen counts
    - Gamma table operations can be slow - 3 second delay is intentional

12. **Deprecation Warnings**:
    - `CGDisplayIOServicePort` triggers deprecation warnings - suppress with `#pragma`
    - Use `@available` checks for macOS version-specific APIs
    - Document which methods may not work on older macOS versions
