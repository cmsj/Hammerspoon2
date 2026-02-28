# hs.ui Module

A unified UI module for Hammerspoon v2 that combines canvas drawing and dialog functionality with a modern, SwiftUI-inspired API.

## Features

- **Builder Pattern API**: Fluent, chainable method calls for creating UI elements
- **Basic Shapes**: Rectangle, Circle with fill/stroke support
- **Text Elements**: Styled text with font and color options
- **Images**: Display images from files or system icons
- **Layout Containers**: VStack, HStack, ZStack for organizing elements
- **Interaction Callbacks**: Per-element `.onClick()` and `.onHover()` handlers
- **Reactive Colors**: `HSColor` objects re-render the canvas when `.set()` is called
- **Reactive Text**: `hs.ui.string()` creates text content that updates live when `.set()` is called
- **Reactive Images**: `HSImage` objects re-render the canvas when `.set()` is called
- **Dialogs**: Alerts, button dialogs, text prompts, and file pickers

## Quick Start

### Simple Colored Window

```javascript
hs.ui.window({x: 100, y: 100, w: 200, h: 200})
    .rectangle()
        .fill("#FF0000")
        .frame({w: "100%", h: "100%"})
    .show();
```

### Multi-Element Dashboard

```javascript
hs.ui.window({x: 100, y: 100, w: 400, h: 300})
    .vstack()
        .spacing(20)
        .padding(20)
        .text("Dashboard")
            .font(HSFont.title())
            .foregroundColor("#FFFFFF")
        .rectangle()
            .fill("#4A90E2")
            .cornerRadius(10)
            .frame({w: "90%", h: 100})
        .hstack()
            .spacing(15)
            .circle()
                .fill("#FF6B6B")
                .frame({w: 50, h: 50})
            .text("Status: Active")
                .font(HSFont.body())
                .foregroundColor("#FFFFFF")
        .end()
    .end()
    .backgroundColor("#2C3E50")
    .show();
```

### Reactive Color on Hover

Create an `HSColor` object and pass it to `.fill()` (or `.stroke()` / `.foregroundColor()`). Calling `.set()` on it from any callback re-renders the canvas automatically.

```javascript
const btnColor = HSColor.hex("#4A90E2");

hs.ui.window({x: 100, y: 100, w: 160, h: 60})
    .rectangle()
        .fill(btnColor)
        .cornerRadius(8)
        .frame({w: "100%", h: "100%"})
        .onHover((isHovered) => {
            btnColor.set(isHovered ? "#E24A4A" : "#4A90E2");
        })
    .show();
```

### Reactive Text on Hover

Create a string with `hs.ui.string()` and pass it to `.text()`. Calling `.set()` on it updates the displayed text live.

```javascript
const label = hs.ui.string("Move your mouse here");

hs.ui.window({x: 100, y: 200, w: 220, h: 50})
    .text(label)
        .font(HSFont.body())
        .foregroundColor("#FFFFFF")
        .onHover((isHovered) => {
            label.set(isHovered ? "You're hovering!" : "Move your mouse here");
        })
    .show();
```

### Reactive Image on Click

Pass an `HSImage` to `.image()`. Calling `.set()` on it swaps the displayed image without rebuilding the window.

```javascript
const icon = HSImage.fromName("NSStatusAvailable");

hs.ui.window({x: 100, y: 300, w: 80, h: 80})
    .image(icon)
        .resizable()
        .aspectRatio("fit")
        .frame({w: 64, h: 64})
        .onClick(() => {
            const next = (icon.name() === "NSStatusAvailable")
                ? HSImage.fromName("NSStatusUnavailable")
                : HSImage.fromName("NSStatusAvailable");
            icon.set(next);
        })
    .show();
```

### Reactive Color and Text Together

A single `.onHover()` callback can update both a color and a text label:

```javascript
const cardColor = HSColor.hex("#3498DB");
const cardLabel = hs.ui.string("Hover the card");

hs.ui.window({x: 100, y: 100, w: 220, h: 120})
    .vstack()
        .spacing(12)
        .padding(16)
        .rectangle()
            .fill(cardColor)
            .cornerRadius(10)
            .frame({w: "100%", h: 60})
            .onHover((isHovered) => {
                cardColor.set(isHovered ? "#E74C3C" : "#3498DB");
                cardLabel.set(isHovered ? "You found it!" : "Hover the card");
            })
        .text(cardLabel)
            .font(HSFont.headline())
            .foregroundColor("#FFFFFF")
    .end()
    .backgroundColor("#1A252F")
    .show();
```

### Simple Alert

```javascript
hs.ui.alert("Operation complete!")
    .font(HSFont.headline())
    .duration(3)
    .show();
```

### Dialog with Callback

```javascript
hs.ui.dialog("Save changes?")
    .informativeText("Your document has unsaved changes.")
    .buttons(["Save", "Don't Save", "Cancel"])
    .onButton((index) => {
        if (index === 0) {
            print("Saving...");
        } else if (index === 1) {
            print("Discarding changes...");
        } else {
            print("Cancelled");
        }
    })
    .show();
```

## API Reference

### hs.ui.window(frame)

Create a new UI window.

**Parameters:**
- `frame` - Dictionary with `x`, `y`, `w`, `h` keys (numbers)

**Returns:** HSUIWindow object for method chaining

**Methods:**

#### Shape Constructors
- `.rectangle()` - Add a rectangle element
- `.circle()` - Add a circle element
- `.text(content)` - Add a text element; `content` may be a plain JS string or an `HSString` from `hs.ui.string()`
- `.image(value)` - Add an image element (HSImage or file path string)
- `.spacer()` - Add flexible space that expands to fill available room

#### Layout Containers
- `.vstack()` - Begin a vertical stack container
- `.hstack()` - Begin a horizontal stack container
- `.zstack()` - Begin an overlapping stack container
- `.end()` - End the current container

#### Shape Modifiers
- `.fill(color)` - Set fill color; `color` may be a hex string, `HSColor.rgb/hex/named()`, or a reactive `HSColor` object
- `.stroke(color)` - Set stroke color (same options as `.fill()`)
- `.strokeWidth(width)` - Set stroke width in points
- `.cornerRadius(radius)` - Set corner radius for rectangles
- `.frame({w, h})` - Set element size (supports `"50%"` strings or numbers)
- `.opacity(value)` - Set opacity (0.0 to 1.0)

#### Text Modifiers
- `.font(font)` - Set font (HSFont object)
- `.foregroundColor(color)` - Set text color; accepts the same values as `.fill()`

#### Image Modifiers
- `.resizable()` - Allow an image to scale with its frame
- `.aspectRatio(mode)` - `"fit"` or `"fill"` scaling mode

#### Interaction Callbacks
- `.onClick(callback)` - Called with no arguments when the element is clicked
- `.onHover(callback)` - Called with `true` when the cursor enters the element, `false` when it leaves

#### Layout Modifiers
- `.padding(points)` - Add padding around a container
- `.spacing(points)` - Set spacing between children in a stack

#### Window Methods
- `.backgroundColor(color)` - Set window background color
- `.show()` - Display the window
- `.hide()` - Hide the window
- `.close()` - Close and destroy the window

---

### hs.ui.string(initialValue)

Create a reactive string for use with `.text()`.

**Parameters:**
- `initialValue` - The starting string

**Returns:** `HSString` object

**Methods:**
- `.set(newValue)` - Update the string; any `.text()` element bound to this string re-renders immediately

---

### hs.ui.alert(message)

Create a simple alert that auto-dismisses.

**Parameters:**
- `message` - The text to display

**Returns:** HSUIAlert object

**Methods:**
- `.font(font)` - Set the font (HSFont)
- `.duration(seconds)` - Set display duration (default: 3)
- `.show()` - Display the alert
- `.close()` - Close the alert early

---

### hs.ui.dialog(message)

Create a dialog with buttons.

**Parameters:**
- `message` - The main message text

**Returns:** HSUIDialog object

**Methods:**
- `.informativeText(text)` - Add secondary informative text
- `.buttons(array)` - Set button labels (default: ["OK"])
- `.onButton(callback)` - Set callback `function(buttonIndex)`
- `.show()` - Display the dialog
- `.close()` - Close the dialog

---

### HSColor

Color creation utilities (available globally).

**Static Methods:**
- `HSColor.rgb(r, g, b, a)` - Create from RGB values (0.0–1.0)
- `HSColor.hex(hexString)` - Create from hex string (`"#FF0000"` or `"#FF0000FF"` with alpha)
- `HSColor.named(name)` - Create from name (`"red"`, `"blue"`, `"systemBlue"`, etc.)

**Instance Methods:**
- `.set(value)` - Update the color; any element whose `.fill()`, `.stroke()`, or `.foregroundColor()` was passed this object will re-render. `value` may be a hex string or another `HSColor`.

---

### HSImage

Image loading utilities (available globally).

**Static Methods:**
- `HSImage.fromPath(path)` - Load from a file path
- `HSImage.fromName(name)` - Load a system image (e.g. `"NSComputer"`, `"NSStatusAvailable"`)
- `HSImage.fromAppBundle(bundleID)` - Load an app's icon
- `HSImage.iconForFile(path)` - Get the Finder icon for a file
- `HSImage.fromURL(url)` - Load from a URL (returns a Promise)

**Instance Methods:**
- `.set(value)` - Replace the image; any `.image()` element bound to this object will re-render. `value` may be an `HSImage` object or a file path string.
- `.size()` / `.size(hsSize)` - Get or set the image size
- `.setSize(hsSize, absolute)` - Return a resized copy
- `.copyImage()` - Return a copy
- `.croppedCopy(rect)` - Return a cropped copy
- `.saveToFile(path)` - Save to disk
- `.template()` / `.template(bool)` - Get or set the template image flag

---

### HSFont

Font creation utilities (available globally).

Common methods:
- `HSFont.title()`, `HSFont.body()`, `HSFont.headline()`, `HSFont.caption()`
- `HSFont.largeTitle()`, `HSFont.subheadline()`, `HSFont.footnote()`
- `HSFont.system(size)`, `HSFont.system(size, weight)`
- `HSFont.custom(name, size)`

---

## Frame Syntax

Frames support both absolute and percentage values:

```javascript
.frame({w: 200, h: 100})        // Absolute pixels
.frame({w: "50%", h: "75%"})    // Percentage of container
.frame({w: "100%"})             // Width only
```

## Color Syntax

Colors can be specified as:
- Hex strings: `"#FF0000"`, `"#FF0000FF"` (with alpha)
- HSColor objects: `HSColor.rgb(1, 0, 0, 1)`, `HSColor.hex("#FF0000")`, `HSColor.named("red")`
- Reactive HSColor: store the `HSColor` in a variable and call `.set()` to update live

## Reactive Values

Both colors and text content can be made reactive:

| What changes | How to create | How to update |
|---|---|---|
| Fill / stroke / text color | `HSColor.hex(...)` | `myColor.set("#newHex")` |
| Text content | `hs.ui.string(...)` | `myString.set("new text")` |
| Image content | `HSImage.fromName(...)` etc. | `myImage.set(newHSImage)` |

When `.set()` is called, the canvas re-renders immediately and `toSwiftUI()` reads the updated value. There is no need to call `.show()` again.

## Architecture Notes

- Windows use NSWindow with NSHostingView containing SwiftUI views
- All elements are rendered via SwiftUI for native appearance
- Reactive values use a lightweight delegate pattern: `HSColor` and `HSString` hold a weak reference to their window; calling `.set()` increments a `@Published` version counter that SwiftUI observes
- Dialogs are non-blocking and use callbacks
- Windows maintain strong references until closed
