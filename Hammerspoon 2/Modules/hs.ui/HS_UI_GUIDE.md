# hs.ui Module

A unified UI module for Hammerspoon v2 that combines canvas drawing and dialog functionality with a modern, SwiftUI-inspired API.

## Features

- **Builder Pattern API**: Fluent, chainable method calls for creating UI elements
- **Basic Shapes**: Rectangle, Circle with fill/stroke support
- **Text Elements**: Styled text with font and color options
- **Layout Containers**: VStack, HStack, ZStack for organizing elements
- **Dialogs**: Simple alerts and button dialogs with callbacks
- **Percentage Frames**: Support for both absolute and percentage-based dimensions

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
- `.text(content)` - Add a text element

#### Layout Containers
- `.vstack()` - Begin a vertical stack container
- `.hstack()` - Begin a horizontal stack container
- `.zstack()` - Begin an overlapping stack container
- `.end()` - End the current container

#### Shape Modifiers
- `.fill(color)` - Set fill color (hex string or HSColor)
- `.stroke(color)` - Set stroke color
- `.strokeWidth(width)` - Set stroke width in points
- `.cornerRadius(radius)` - Set corner radius for rectangles
- `.frame({w, h})` - Set element size (supports "50%" or numbers)
- `.opacity(value)` - Set opacity (0.0 to 1.0)

#### Text Modifiers
- `.font(font)` - Set font (HSFont object)
- `.foregroundColor(color)` - Set text color

#### Layout Modifiers
- `.padding(points)` - Add padding around container
- `.spacing(points)` - Set spacing between container children

#### Window Methods
- `.backgroundColor(color)` - Set window background color
- `.show()` - Display the window
- `.hide()` - Hide the window
- `.close()` - Close and destroy the window

### hs.ui.alert(message)

Create a simple alert that auto-dismisses.

**Parameters:**
- `message` - The text to display

**Returns:** HSUIAlert object

**Methods:**
- `.font(font)` - Set the font (HSFont)
- `.duration(seconds)` - Set display duration (default: 3)
- `.position({x, y})` - Set position (optional)
- `.show()` - Display the alert
- `.close()` - Close the alert early

### hs.ui.dialog(message)

Create a dialog with buttons.

**Parameters:**
- `message` - The main message text

**Returns:** HSUIDialog object

**Methods:**
- `.informativeText(text)` - Add secondary informative text
- `.buttons(array)` - Set button labels (default: ["OK"])
- `.style(style)` - Set dialog style (currently not implemented)
- `.onButton(callback)` - Set callback function(buttonIndex)
- `.show()` - Display the dialog
- `.close()` - Close the dialog

### HSColor

Color creation utilities (available globally).

**Static Methods:**
- `HSColor.rgb(r, g, b, a)` - Create from RGB values (0.0-1.0)
- `HSColor.hex(hexString)` - Create from hex string ("#FF0000")
- `HSColor.named(name)` - Create from name ("red", "blue", etc.)

### HSFont

Font creation utilities (available globally).

See `HSFont` documentation for full API. Common methods:
- `HSFont.title()`, `HSFont.body()`, `HSFont.headline()`
- `HSFont.system(size)`, `HSFont.system(size, weight)`
- `HSFont.custom(name, size)`

## Frame Syntax

Frames support both absolute and percentage values:

```javascript
.frame({w: 200, h: 100})        // Absolute pixels
.frame({w: "50%", h: "75%"})    // Percentage of container
.frame({w: "100%", h: "fill"})  // Fill available space
```

## Color Syntax

Colors can be specified as:
- Hex strings: `"#FF0000"`, `"#FF0000FF"` (with alpha)
- HSColor objects: `HSColor.rgb(1, 0, 0, 1)`
- Named colors: `HSColor.named("red")`

## Architecture Notes

- Windows use NSWindow with NSHostingView containing SwiftUI views
- All elements are rendered via SwiftUI for native appearance
- Dialogs are non-blocking and use callbacks
- Windows maintain strong references until closed

## Future Enhancements

Planned features for future versions:
- Image support
- Input dialogs (text prompts)
- File picker dialogs
- Animation support
- Event handlers (onClick, onHover)
- Custom drawing paths
- Window dragging/resizing
- Accessibility support
