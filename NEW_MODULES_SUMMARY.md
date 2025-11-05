# New Modules Implementation Summary

## Overview

I've implemented a two-layer architecture for macOS Accessibility API access:

1. **hs.ax** - Low-level Accessibility API wrapper
2. **hs.window** - High-level window management built on hs.ax

This provides both flexibility for advanced use cases and convenience for common window operations.

## Files Created

### hs.ax Module (Low-Level Accessibility API)

```
Modules/hs.ax/
├── AXModule.swift              # Main module implementation
├── AXElementObject.swift       # AXElement wrapper object
└── hs.ax.js                    # JavaScript enhancements
```

**Features:**
- Access system-wide accessibility elements
- Get elements by position or application
- Full attribute/action inspection and manipulation
- Element hierarchy navigation (parent/children)
- Permission checking and requesting

**Key APIs:**
- `hs.ax.systemWideElement()` - Get system-wide AX root
- `hs.ax.applicationElement(pid)` - Get app's AX element
- `hs.ax.elementAtPosition(x, y)` - Get element at screen position
- `hs.ax.isAccessibilityEnabled()` - Check permissions
- `hs.ax.requestAccessibility()` - Request permissions

**AXElement Object:**
- Properties: `role`, `subrole`, `title`, `value`, `position`, `size`, `frame`, `isFocused`, etc.
- Methods: `children()`, `parent`, `attributeNames()`, `actionNames()`, `performAction()`, etc.

### hs.window Module (High-Level Window Management)

```
Modules/hs.window/
├── WindowModule.swift          # Main module implementation
├── WindowObject.swift          # Window wrapper object
└── hs.window.js                # JavaScript enhancements
```

**Features:**
- Query windows (focused, all, visible, by app, by screen)
- Window state management (minimize, fullscreen, focus)
- Geometry manipulation (move, resize, frame)
- Convenience methods (center, tiling presets, grid)
- Access to underlying AX element for advanced operations

**Key APIs:**
- `hs.window.focusedWindow()` - Get focused window
- `hs.window.allWindows()` - Get all windows
- `hs.window.visibleWindows()` - Get visible windows only
- `hs.window.windowsForApp(pid)` - Get windows for specific app
- `hs.window.orderedWindows()` - Get windows in z-order

**Window Object:**
- Properties: `title`, `application`, `frame`, `position`, `size`, `isMinimized`, `isFullscreen`, etc.
- Methods: `focus()`, `minimize()`, `moveTo()`, `resize()`, `setFrame()`, `centerOnScreen()`, `close()`, etc.
- Advanced: `axElement()` - Get underlying AXElement for low-level access

**JavaScript Enhancements:**
- `hs.window.tiling.*` - Preset tiling positions (left, right, topLeft, etc.)
- `hs.window.grid.setGrid()` - Grid-based window positioning
- `hs.window.findByTitle()` - Find windows by title
- `hs.window.cycleWindows()` - Cycle through windows

### Documentation & Examples

```
Modules/
└── README.md                   # Module architecture documentation

examples/
└── window-management-example.js # Comprehensive usage examples
```

### Updated Core Files

```
Engine/
└── ModuleRoot.swift            # Updated to register new modules
```

## Architecture

The layered design allows for both flexibility and convenience:

```
User Script
    │
    ├─────────────────┬─────────────────┐
    │                 │                 │
    ▼                 ▼                 ▼
hs.window     hs.ax (direct)    Other modules
(high-level)  (low-level)       (future: menus, etc.)
    │                 │
    └────────┬────────┘
             │
             ▼
    macOS Accessibility API
```

## Integration Steps

### 1. Add Files to Xcode Project

1. Open `Hammerspoon 2.xcodeproj` in Xcode
2. Right-click on the "Modules" group
3. Select "Add Files to Hammerspoon 2..."
4. Add the following folders:
   - `Modules/hs.ax/` (all files)
   - `Modules/hs.window/` (all files)
5. Ensure "Copy items if needed" is **unchecked** (files are already in project)
6. Ensure "Create groups" is selected
7. Target membership: Check "Hammerspoon 2"

### 2. Add JavaScript Files to Bundle

The `.js` files need to be included in the app bundle:

1. In Xcode, select the `Hammerspoon 2` target
2. Go to "Build Phases"
3. Expand "Copy Bundle Resources"
4. Click "+" and add:
   - `hs.ax.js`
   - `hs.window.js`

### 3. Build and Test

```bash
# Build the project
⌘B in Xcode

# Or from command line:
xcodebuild -project "Hammerspoon 2.xcodeproj" -scheme "Hammerspoon 2" build
```

### 4. Test the Modules

Create a simple init.js file:

```javascript
// Test accessibility permissions
console.info("Accessibility enabled:", hs.ax.isAccessibilityEnabled());

// Test focused window
const win = hs.window.focusedWindow();
if (win) {
    console.info("Focused window:", win.title);
    console.info("  Frame:", JSON.stringify(win.frame));
    console.info("  App:", win.application.title);
}

// Test window listing
const windows = hs.window.allWindows();
console.info(`Total windows: ${windows.length}`);

// Test low-level AX API
const systemWide = hs.ax.systemWideElement();
if (systemWide) {
    console.info("System-wide element:", systemWide.role);
}
```

## Usage Examples

### Basic Window Management

```javascript
// Get and manipulate focused window
const win = hs.window.focusedWindow();
win.centerOnScreen();
win.resize(1000, 800);
win.focus();

// Tile windows
hs.window.tiling.left();   // Current window to left half
hs.window.tiling.right();  // Current window to right half
```

### Advanced: Low-Level AX Access

```javascript
// Get window's close button
const win = hs.window.focusedWindow();
const axWin = win.axElement();

// Find close button
const children = axWin.children();
const closeButton = children.find(el => el.role === "AXButton" && el.subrole === "AXCloseButton");

if (closeButton) {
    console.info("Close button found:", closeButton.title);
    // Could perform action: closeButton.performAction("AXPress");
}
```

### Grid Layout

```javascript
// Define a 3x3 grid
const grid = { rows: 3, cols: 3 };

// Place window in center cell
const centerCell = { row: 1, col: 1, rowSpan: 1, colSpan: 1 };
hs.window.grid.setGrid(null, grid, centerCell);

// Place window spanning top two cells
const topSpan = { row: 0, col: 0, rowSpan: 1, colSpan: 2 };
hs.window.grid.setGrid(null, grid, topSpan);
```

## Known Limitations

1. **Accessibility Permissions Required**: Both modules require accessibility permissions to function
2. **App Compatibility**: Some apps don't fully support the Accessibility API (rare)
3. **Performance**: Getting all windows can be slow with many apps open
4. **Screen Detection**: JavaScript helpers use hardcoded screen dimensions (needs NSScreen integration)

## Future Enhancements

1. **hs.screen Module**: Add screen detection for multi-monitor support
2. **Window Watchers**: Add event watchers for window creation/destruction/movement
3. **hs.menu Module**: Use hs.ax to provide menu bar automation
4. **hs.uielement Module**: Generic UI element module built on hs.ax
5. **Animation**: Add window animation support
6. **Spaces Integration**: Integrate with macOS Spaces/Desktops

## Testing Checklist

- [ ] Project builds without errors
- [ ] Modules load at startup
- [ ] `hs.ax` is accessible from console
- [ ] `hs.window` is accessible from console
- [ ] Accessibility permission prompt appears if needed
- [ ] Can get focused window
- [ ] Can list all windows
- [ ] Can move/resize windows
- [ ] JavaScript enhancements work (tiling, grid)
- [ ] Can access low-level AX elements
- [ ] Window cycling works
- [ ] Grid positioning works

## Troubleshooting

### "Module not found" Error

**Problem**: `hs.ax` or `hs.window` returns undefined

**Solutions**:
1. Check that files are added to Xcode project
2. Verify files are in "Copy Bundle Resources" build phase
3. Clean build folder (Product > Clean Build Folder)
4. Rebuild project

### "Accessibility permissions not granted" Error

**Problem**: Operations fail with permission error

**Solutions**:
1. Call `hs.ax.requestAccessibility()` to prompt user
2. Manually enable in System Preferences > Privacy & Security > Accessibility
3. Add Hammerspoon 2 to the list and toggle it on

### Windows Not Found

**Problem**: `hs.window.allWindows()` returns empty array

**Solutions**:
1. Verify accessibility permissions are granted
2. Check that apps with windows are actually running
3. Some apps (like menu bar apps) may not have windows

### Build Errors

**Problem**: Swift compilation errors

**Solutions**:
1. Verify all imports are available (AXSwift, AppKit, Foundation)
2. Check that `ModuleRoot.swift` was updated correctly
3. Ensure target is set to macOS (not iOS)

## Code Style Notes

The implementation follows the existing codebase conventions:

- **Naming**: `HS` prefix for JS-exposed types, `AK` prefix for logging
- **Error Handling**: Uses `AKError()`, `AKWarning()` for logging
- **Documentation**: Protocol methods have DocC-style comments
- **Structure**: Module/Object separation (like hs.application)
- **Threading**: `@MainActor` isolation where appropriate
- **JS Export**: `@objc protocol` conforming to `JSExport`

## Questions or Issues?

If you encounter any issues:

1. Check the console for error messages
2. Verify accessibility permissions
3. Try the `window-management-example.js` script
4. Review `Modules/README.md` for architecture details
5. Check `ARCHITECTURE_ANALYSIS.md` for implementation guidelines

---

**Next Steps**: Once integrated and tested, you can start building your window management workflows! The `examples/window-management-example.js` file provides a comprehensive starting point.
