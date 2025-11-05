# Hammerspoon 2 Modules

## Overview

Hammerspoon 2 uses a modular architecture where each module provides specific functionality through a JavaScript API. Modules can build on top of each other to provide layered abstractions.

## Module Architecture

### Core Modules

- **hs.appInfo** - Application metadata (version, build, etc.)
- **hs.application** - Application control and lifecycle monitoring
- **hs.console** - Console window control
- **hs.permissions** - System permission management
- **hs.timer** - Scheduled callbacks and timers
- **hs.hashing** - Encoding/decoding utilities

### Accessibility Modules

The accessibility modules provide a layered architecture for interacting with macOS UI elements:

```
┌─────────────────────────────────────┐
│        hs.window (High-Level)       │
│  Window-specific operations like    │
│  focus(), minimize(), tile(), etc.  │
└─────────────┬───────────────────────┘
              │ uses
              ▼
┌─────────────────────────────────────┐
│        hs.ax (Low-Level)            │
│  Generic Accessibility API access   │
│  for any UI element                 │
└─────────────────────────────────────┘
```

#### hs.ax - Accessibility API

The `hs.ax` module provides low-level access to the macOS Accessibility API. This allows you to interact with any UI element in any application, not just windows.

**Key Features:**
- Access to system-wide accessibility elements
- Query and manipulate any UI element by role, title, attributes
- Navigate element hierarchies (parent/child relationships)
- Perform actions on elements
- Inspect element properties and capabilities

**Use Cases:**
- Custom UI automation
- Accessing non-window UI elements (menus, buttons, toolbars)
- Advanced window management
- Assistive technology development
- UI testing and inspection

**Example:**

```javascript
// Get the system-wide accessibility root
const systemWide = hs.ax.systemWideElement();

// Get element at mouse position
const elementAtMouse = hs.ax.elementAtPosition(500, 300);
console.log(`Element role: ${elementAtMouse.role}`);
console.log(`Element title: ${elementAtMouse.title}`);

// Navigate hierarchy
const parent = elementAtMouse.parent;
const children = elementAtMouse.children();

// Find all buttons in an element
const buttons = hs.ax.findByRole("AXButton", elementAtMouse);

// Perform action on element
elementAtMouse.performAction("AXPress");

// Set attribute
elementAtMouse.setAttributeValue("AXFocused", true);
```

#### hs.window - Window Management

The `hs.window` module builds on top of `hs.ax` to provide high-level window management operations. It filters accessibility elements to only those with the "AXWindow" role and provides convenient methods for common window operations.

**Key Features:**
- Query windows (focused, all, visible, by app, by position)
- Window manipulation (move, resize, minimize, fullscreen)
- Window tiling and layouts
- Grid-based positioning
- Screen-aware operations

**Use Cases:**
- Window tiling and organization
- Keyboard-driven window management
- Custom window layouts
- Multi-monitor management
- Productivity automation

**Example:**

```javascript
// Get focused window
const win = hs.window.focusedWindow();

// Simple operations
win.focus();
win.minimize();
win.centerOnScreen();
win.moveTo(100, 100);
win.resize(800, 600);

// Tiling
hs.window.tiling.left(win);
hs.window.tiling.topRight(win);

// Grid-based layout
const grid = { rows: 2, cols: 3 };
const cell = { row: 0, col: 1, rowSpan: 1, colSpan: 2 };
hs.window.grid.setGrid(win, grid, cell);

// Access underlying AX element for advanced operations
const axElement = win.axElement();
console.log(`Available actions: ${axElement.actionNames()}`);
```

### Why Two Modules?

The separation of `hs.ax` and `hs.window` provides several benefits:

1. **Separation of Concerns**: Window management is just one use case of the Accessibility API
2. **Reusability**: The low-level AX API can be used for non-window UI automation
3. **Flexibility**: Users can choose the appropriate abstraction level
4. **Extensibility**: New high-level modules can be built on `hs.ax` (e.g., menu management, toolbar control)

### Example: Building on hs.ax

You could create additional high-level modules using the same pattern:

```javascript
// Hypothetical hs.menu module built on hs.ax
const menuBar = hs.ax.systemWideElement().children()
    .find(el => el.role === "AXMenuBar");

const fileMenu = menuBar.children()
    .find(el => el.title === "File");

fileMenu.performAction("AXPress");
```

## Module Structure

Each module follows a consistent structure:

```
Modules/hs.modulename/
├── ModuleNameModule.swift      # Main module implementation
│   ├── @objc protocol API      # JavaScript-visible API
│   └── @objc class Module      # Implementation
│
├── ModuleNameObject.swift      # Optional: Object types
│   ├── @objc protocol API      # Object's JS API
│   └── @objc class Object      # Object implementation
│
└── hs.modulename.js            # Optional: JS enhancements
    └── Convenience functions
```

### Creating a New Module

See `ARCHITECTURE_ANALYSIS.md` section on "Module Development" for detailed instructions.

## JavaScript Enhancements

Modules can include a `hs.modulename.js` file that adds convenience functions in JavaScript. This allows for:

- Simpler APIs for common operations
- JavaScript-native data structures
- Helper functions and utilities
- Event handling patterns

Example: `hs.window.js` adds tiling presets, grid management, and window finding helpers that would be cumbersome to implement in Swift.

## Permissions

Many modules require system permissions to function:

- **hs.ax** and **hs.window** require **Accessibility** permissions
- **hs.permissions** can check and request these permissions

Always check permissions before using privileged operations:

```javascript
if (!hs.ax.isAccessibilityEnabled()) {
    console.error("Accessibility required!");
    hs.ax.requestAccessibility();
}
```

## Best Practices

1. **Check Permissions First**: Always verify required permissions before operations
2. **Handle Errors Gracefully**: Many operations can fail; check return values
3. **Use High-Level APIs When Possible**: Start with `hs.window`, drop to `hs.ax` only when needed
4. **Respect Resource Limits**: Don't create excessive watchers or timers
5. **Clean Up**: Remove watchers and cancel timers when done

## Examples

See the `examples/` directory for complete working examples:

- `examples/window-management-example.js` - Comprehensive window management examples
- `examples/basic/` - Simple starter examples
- `examples/advanced/` - Advanced techniques

## Further Reading

- `ARCHITECTURE_ANALYSIS.md` - Complete architectural overview
- `docs/ModuleDevelopment.md` - Guide to creating new modules
- Apple's [Accessibility API Documentation](https://developer.apple.com/documentation/accessibility)
