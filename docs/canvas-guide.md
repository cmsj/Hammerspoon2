`hs.canvas` is a low-level, absolutely-positioned drawing surface — the tool to reach for
when you need a shape, an icon, or a piece of text pinned to an exact screen coordinate,
independent of any layout. It mirrors Hammerspoon 1's `hs.canvas` closely: a canvas is a
window, and its contents are a plain array of JavaScript objects (mirroring v1's Lua
tables) — rectangles, circles, arcs, text, images, even other canvases — each with a `type`
and whatever properties that type understands. There's no view hierarchy and no reactive
state; you build the array, hand it to `appendElements()`, and redraw by mutating it.

This is a different tool from `hs.ui`, which is a SwiftUI-based, flow-layout builder for
genuinely app-like interfaces (buttons, forms, stacks that reflow). Reach for `hs.canvas`
instead when you need absolute positioning independent of any layout; clipped or composited
shapes (the build/clip pipeline below); direct control of the window's level, Spaces
behavior, or click-through; or a shape vocabulary — arcs, gradients, blend modes, bezier
paths — that `hs.ui` doesn't have.

Because almost all of a canvas's configuration lives in these element dictionaries rather
than in method signatures, it doesn't lend itself to the same inline documentation the rest
of Hammerspoon 2 gets from JSExport doc comments — see the
[full `HSCanvas` method reference](HSCanvas.html) for everything that *is* a method (window
lifecycle, showing/hiding, mouse callbacks, element mutation, and so on). This guide covers
the other half: what an element dictionary can actually contain, then a series of worked
examples combining several of them.

## Coordinate systems — read this first

A canvas's **window position** (`hs.canvas.create({x, y, w, h})`, and any later `x`/`y` you
compare it against, e.g. from `hs.screen`) uses unflipped AppKit screen coordinates:
`y = 0` is the *bottom* of the screen, and `y` increases upward. This matches `hs.ui.window`.

But **element content** positioned *inside* a canvas — every `frame`, `center`, and
`coordinates` value you pass to `appendElements()` and friends — is drawn top-down:
`y = 0` is the *top* of the canvas, and `y` increases downward. These two coordinate senses
are independent of each other and easy to conflate, especially when a script computes an
element's position from the same screen geometry it used for the window's own placement. If
a shape appears vertically mirrored from where you expect, this mismatch is the first thing
to check.

Most numeric position/size values — `frame`, `center`, `radius`, and the `x`/`y` of each
`segments`/`points` coordinate — also accept a percentage string like `"50%"`, resolved
against the canvas's own size at render time, instead of a fixed number.

## The canvas object, briefly

Create one with `hs.canvas.create({x, y, w, h})`, add content with `.appendElements([...])`,
and make it visible with `.show()`:

```js
const c = hs.canvas.create({x: 100, y: 100, w: 300, h: 200})
c.appendElements([
    { type: "rectangle", action: "fill", fillColor: { red: 0.2, green: 0.5, blue: 0.9, alpha: 1 } },
])
c.show()
```

A canvas starts fully transparent — there's no window-level "background color", by design
(`hs.canvas` is meant for compositing shapes over whatever's beneath it, e.g. a screen
overlay). If you want an opaque background, draw one yourself as the first element: a
full-frame `rectangle` with `action: "fill"`.

Everything about *managing* a canvas once it exists — showing/hiding/destroying it, moving
or resizing its window, reading or mutating individual elements after the fact
(`setElementAttribute()`, `elementBounds()`, `minimumTextSize()`...), mouse and drag
callbacks, level/Spaces behavior, per-element and whole-canvas transforms — is a regular
method with its own doc comment, so it's already covered in the
[`HSCanvas` reference](HSCanvas.html). What isn't covered there is the shape of the element
dictionaries themselves — that's the rest of this guide.

## The element pipeline

Every element in the array `appendElements()` takes is processed in order, and every element
shares a few properties regardless of its `type`:

| Property | Type | Applies to | Notes |
|---|---|---|---|
| `type` | string | every element | required — see the [type reference](#element-type-reference) below |
| `action` | string | every element except `resetClip` | `"fill"`, `"stroke"`, `"strokeAndFill"` (default), `"build"`, `"clip"`, or `"skip"` — see [below](#the-action-pipeline-fill-stroke-build-clip-skip-resetclip) |
| `compositeRule` | string | every element except `resetClip` | a blend mode name for this element only — see [Blend modes](#blend-modes-compositerule) |
| `id` | any | every element | not read by rendering at all — your own bookkeeping value, delivered back by mouse-tracking callbacks and readable via `canvasElements()` |
| `trackMouseDown`, `trackMouseUp`, `trackMouseEnterExit`, `trackMouseMove` | boolean | every element | opts this element into mouse tracking — see [`HSCanvas.mouseCallback()`](HSCanvas.html) |
| `rotation` + `rotationPoint` | number (degrees) + `{x, y}` | every element | rotate about `rotationPoint`, or the element's own bounding-box center if omitted |
| `transformation` | `{m11, m12, m21, m22, tX, tY}` | every element | a raw affine matrix; takes precedence over `rotation` if both are set |
| `windingRule` | string | `rectangle`, `circle`, `oval`, `arc`, `ellipticalArc`, `segments`, `points` | `"nonZero"` (default) or `"evenOdd"` — only matters once `build` is combining more than one shape's path together, see below |

### The action pipeline: fill, stroke, build, clip, skip, resetClip

`action` defaults to `"strokeAndFill"`, and for most elements that's all you need. The other
four values exist for compositing shapes together:

- **`build`** doesn't draw anything. It appends its shape to a pending compound path that
  keeps growing until a non-`build` action (`fill`/`stroke`/`clip`) consumes it.
- **`clip`** intersects the current drawing region with its shape (combined with any pending
  `build` path), narrowing where *later* elements are allowed to draw. This accumulates
  against whatever's already clipped — it's not a fresh clip each time.
- **`resetClip`** (a `type` on its own, not an `action` — see the [reference](#resetclip)
  below) jumps back to the fully unclipped state from the top of the element list. It's not
  a stack pop: it discards *every* clip applied so far, not just the most recent one. It's
  also the one element that ignores `action`/`compositeRule`/`rotation`/`transformation`
  entirely, since there's nothing for them to apply to.
- **`skip`** hides the element completely — useful for toggling an element off with
  `setElementAttribute()` without removing it from the list.

Combining `build` + `clip` with `reversePath: true` on a `circle` (see the
[`circle` reference](#circle)) is how you punch a hole in a shape — the technique behind a
true rounded-corner mask, shown in full in [the first demo below](#a-rounded-screen-corner-overlay).
The same `build`-then-combine mechanism, with `windingRule: "evenOdd"` instead of `clip`,
turns two same-winding circles into a donut (a filled ring) instead of a solid disc — the
inner circle's *fill* is where you set `windingRule`, not the outer one's `build`.

### Colors

Every color-valued property (`fillColor`, `strokeColor`, `textColor`, and the two gradient
color lists below) takes a plain `{red, green, blue, alpha}` object, each component
`0.0`–`1.0` — **not** the `HSColor` reactive type `hs.ui` uses elsewhere in Hammerspoon 2.
Any component you omit defaults to `0`, **except `alpha`, which defaults to `1`** — so
`{ alpha: 1 }` alone means *opaque black*, not "no color." This is an easy trap (it once
produced a genuinely invisible test case during this module's own development), so it's
worth committing to memory.

### Blend modes (`compositeRule`)

`compositeRule` accepts any of: `normal`, `sourceOver`, `multiply`, `screen`, `overlay`,
`darken`, `lighten`, `colorDodge`, `colorBurn`, `softLight`, `hardLight`, `difference`,
`exclusion`, `hue`, `saturation`, `color`, `luminosity`, `clear`, `copy`, `sourceIn`,
`sourceOut`, `sourceAtop`, `destinationOver`, `destinationIn`, `destinationOut`,
`destinationAtop`, `xor`, `plusDarker`, `plusLighter`. The same names are exposed as
`hs.canvas.compositeTypes.<name>`, purely so you can reference them without typo risk:

```js
{ type: "circle", action: "fill", compositeRule: hs.canvas.compositeTypes.multiply, fillColor: { blue: 1, alpha: 1 } }
```

It applies to the one element that sets it — it doesn't leak onto the elements drawn after
it, even though earlier versions of this module had a bug where it briefly did.

### Gradients

Any element that takes `fillColor` can use a gradient instead:

| Property | Applies to | Notes |
|---|---|---|
| `fillGradient` | `"linear"` or `"radial"` | switches the fill from a solid color to a gradient |
| `fillGradientColors` | array of color dicts | at least two stops, evenly spaced |
| `fillGradientAngle` | `linear` only | degrees, default `0` |
| `fillGradientCenter` | `radial` only | `{x, y}`, defaults to the shape's own bounding-box center |

```js
{ type: "rectangle", action: "fill", fillGradient: "linear", fillGradientAngle: 45,
  fillGradientColors: [{ red: 1, alpha: 1 }, { blue: 1, alpha: 1 }] }
```

## Element type reference

### `rectangle`

| Property | Default | Notes |
|---|---|---|
| `frame` | the whole canvas | `{x, y, w, h}` |
| `roundedRectRadii` | none (square corners) | corner radius, applied to all four corners |

### `circle`

| Property | Default | Notes |
|---|---|---|
| `center` | the canvas's own center | `{x, y}` |
| `radius` | half the canvas's shorter side | |
| `reversePath` | `false` | reverses the path's winding direction — combine with `build` + `clip` to punch a hole (see [the action pipeline](#the-action-pipeline-fill-stroke-build-clip-skip-resetclip)) |

### `oval`

| Property | Default | Notes |
|---|---|---|
| `frame` | the whole canvas | `{x, y, w, h}` — the oval is inscribed in this rectangle |

### `arc`

| Property | Default | Notes |
|---|---|---|
| `center` | the canvas's own center | `{x, y}` |
| `radius` | half the canvas's shorter side | |
| `startAngle` | `0` | degrees |
| `endAngle` | `360` | degrees |
| `arcClockwise` | `false` | |
| `arcRadii` | `false` | when `true`, also draws the two radius lines from the center to the arc's endpoints — a "pie slice" outline instead of a bare curve |

### `ellipticalArc`

| Property | Default | Notes |
|---|---|---|
| `frame` | the whole canvas | `{x, y, w, h}` — unlike `arc`, the two axes can differ, giving a non-circular arc |
| `startAngle` | `0` | degrees |
| `endAngle` | `360` | degrees |
| `arcClockwise` | `false` | |

### `segments`

| Property | Default | Notes |
|---|---|---|
| `coordinates` | *(required)* | array of `{x, y}` points, connected in order |
| `closed` | `false` | connects the last point back to the first |

Any coordinate after the first can include `c1x`/`c1y`/`c2x`/`c2y` to curve *into* that point
from the previous one (a cubic Bézier) instead of drawing a straight line:

```js
{ type: "segments", action: "stroke", strokeColor: { alpha: 1 },
  coordinates: [
      { x: 0, y: 50 },
      { x: 100, y: 50, c1x: 30, c1y: 0, c2x: 70, c2y: 0 },  // curves upward between the two points
  ] }
```

### `points`

| Property | Default | Notes |
|---|---|---|
| `coordinates` | *(required)* | array of `{x, y}` — each becomes a filled dot, fixed at a 2pt radius (not configurable) |

### `text`

| Property | Default | Notes |
|---|---|---|
| `text` | *(required)* | the string to render; `\n` produces multiple lines |
| `frame` | the whole canvas | `{x, y, w, h}` — also a real clip boundary: text that doesn't fit is wrapped or truncated per `textLineBreak`, not left to silently overflow |
| `textSize` | `27.0` | |
| `textColor` | opaque black | |
| `textFont` | the system font | a custom font's PostScript name (not its display name), e.g. `"Menlo-Bold"`; an unresolvable name logs a warning and falls back to the system font. Overrides `textWeight`/`textDesign` entirely when set |
| `textWeight` | `regular` | one of `thin`, `ultraLight`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black`; ignored if `textFont` is set |
| `textDesign` | the system default | `monospaced`, `rounded`, or `serif`; ignored if `textFont` is set |
| `textItalic` | `false` | |
| `textAlignment` | `natural` | `left`, `right`, `center`, `justified`, or `natural`. `natural`/`justified` resolve against the text's own writing direction — for right-to-left scripts (Hebrew, Arabic, ...), that means flush with the frame's *right* edge, not the left, the way it does for left-to-right text. `left`/`right`/`center` are always literal, regardless of script |
| `textLineBreak` | `wordWrap` | `wordWrap`, `charWrap`, `clip`, `truncateHead`, `truncateMiddle`, `truncateTail` — `wordWrap`/`charWrap` allow multiple lines; the rest keep the text to one line, either clipping it or inserting `…` |

`HSCanvas.minimumTextSize(index, text)` measures how much space a string would need using an
existing text element's font attributes, without changing what's on screen — handy for
sizing a `frame` to fit before setting it.

### `image`

| Property | Default | Notes |
|---|---|---|
| `image` | *(required)* | an `HSImage` — see [`HSImage.fromPath()`](HSImage.html) and friends |
| `frame` | the whole canvas | `{x, y, w, h}` — also a real clip boundary, same as `text`'s |
| `imageAlpha` | `1.0` | |
| `imageScaling` | `scaleProportionally` | `none` (native size), `scaleToFit` (stretches to fill `frame`, distorting aspect ratio), `scaleProportionally` (scales up *or* down to fit, preserving aspect ratio), `shrinkToFit` (like proportional, but never enlarges) |
| `imageAlignment` | `center` | `center`, `top`, `bottom`, `left`, `right`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight` — where the (possibly smaller, after scaling) image sits within `frame` |

`HSCanvas.imageFromCanvas()` renders a canvas's current contents to an `HSImage`, which you
can then feed straight back into an `image` element (on this canvas or another) — see the
[image badge demo](#an-image-badge) below.

### `canvas`

Embeds another, already-created `HSCanvas` as a nested element — its own elements render
inside this one's, transformed along with it.

| Property | Default | Notes |
|---|---|---|
| `canvas` | *(required)* | another `HSCanvas` object |
| `frame` | the whole canvas | `{x, y, w, h}` |
| `canvasAlpha` | `1.0` | |

Nesting is capped at 8 levels deep, to guard against a canvas that (directly or indirectly)
embeds itself.

### `resetClip`

No properties beyond `type: "resetClip"` — see [the action pipeline](#the-action-pipeline-fill-stroke-build-clip-skip-resetclip)
above for what it does.

## Demos

### A rounded screen corner overlay

The canonical `build`/`clip`/`resetClip` example — a tiny canvas sits over a screen corner,
with a circle punching a hole out of an opaque square via reversed-winding cancellation,
leaving only a curved sliver that masks the physical corner:

```js
const radius = 12
const corner = hs.canvas.create({x: 0, y: 0, w: radius, h: radius})
corner.appendElements([
    { action: "build", type: "rectangle" },
    { action: "clip", type: "circle", center: {x: radius, y: radius}, radius: radius, reversePath: true },
    { action: "fill", type: "rectangle", fillColor: { alpha: 1 } },
    { type: "resetClip" },
])
corner.levelValue(hs.canvas.windowLevels.screenSaver + 1)
corner.behavior("canJoinAllSpaces")
corner.ignoreMouseEvents(true)  // purely decorative -- never intercept clicks meant for what's underneath
corner.show()
```

### A labeled gauge

Combines a gradient-filled arc, a pie-slice outline, and custom-font text to build a small
"battery"-style readout:

```js
const level = 0.72  // 0.0-1.0
const c = hs.canvas.create({x: 100, y: 100, w: 160, h: 160})
c.appendElements([
    // Track: a full circle in a muted color, stroked only.
    { type: "circle", action: "stroke", center: {x: 80, y: 80}, radius: 60,
      strokeColor: { red: 0.3, green: 0.3, blue: 0.3, alpha: 1 }, strokeWidth: 10 },

    // Fill: a pie slice from the top, sized to `level`, colored by a gradient.
    { type: "arc", action: "fill", center: {x: 80, y: 80}, radius: 60,
      startAngle: -90, endAngle: -90 + level * 360,
      fillGradient: "linear", fillGradientAngle: 90,
      fillGradientColors: [{ green: 1, alpha: 1 }, { red: 0.2, green: 0.8, blue: 1, alpha: 1 }] },

    // Percentage, centered in the middle of the ring.
    { type: "text", text: Math.round(level * 100) + "%",
      frame: {x: 0, y: 65, w: 160, h: 30}, textSize: 22, textWeight: "bold",
      textAlignment: "center", textColor: { alpha: 1 } },
])
c.show()
```

### An image badge

`imageScaling`/`imageAlignment` combined with a rounded backdrop and a text label —
`imageFromCanvas()` then snapshots the whole thing into a reusable `HSImage`:

```js
const icon = HSImage.fromPath("/path/to/icon.png")
const c = hs.canvas.create({x: 300, y: 100, w: 160, h: 60})
c.appendElements([
    { type: "rectangle", action: "fill", roundedRectRadii: 10, fillColor: { red: 0.1, green: 0.1, blue: 0.12, alpha: 1 } },
    { type: "image", image: icon, frame: {x: 8, y: 8, w: 44, h: 44}, imageScaling: "scaleProportionally", imageAlignment: "center" },
    { type: "text", text: "Connected", frame: {x: 60, y: 20, w: 90, h: 20}, textSize: 15, textColor: { alpha: 1 } },
])
c.show()

const badgeImage = c.imageFromCanvas()  // reuse this badge as an image element elsewhere
```

### An interactive hover tooltip

A dot that reveals a label on hover, using `trackMouseEnterExit`, `mouseCallback()`, and
`setElementAttribute()` to mutate elements already on screen rather than rebuilding them:

```js
const c = hs.canvas.create({x: 500, y: 100, w: 200, h: 80})
c.appendElements([
    { type: "circle", action: "fill", center: {x: 30, y: 40}, radius: 12,
      fillColor: { red: 0.9, green: 0.3, blue: 0.4, alpha: 1 },
      trackMouseEnterExit: true, id: "dot" },
    { type: "text", text: "", frame: {x: 55, y: 30, w: 140, h: 20},
      textSize: 13, textColor: { alpha: 0 }, id: "tooltip" },  // starts invisible
])

function indexOf(id) {
    return c.canvasElements().findIndex((el) => el.id === id)
}

c.mouseCallback((canvas, message, id) => {
    if (id !== "dot") return
    const tooltipIndex = indexOf("tooltip")
    const visible = message === "mouseEnter"
    canvas.setElementAttribute(tooltipIndex, "text", visible ? "That's a dot!" : "")
    canvas.setElementAttribute(tooltipIndex, "textColor", { alpha: visible ? 1 : 0 })
})

c.show()
```

## Where to go from here

The [Getting Started guide](getting-started.html) covers hotkeys, timers, watchers, and
`hs.ui` — the rest of what a config typically needs alongside `hs.canvas`. The
[`HSCanvas` API reference](HSCanvas.html) covers every method (window/Spaces control,
element mutation, mouse and drag callbacks, transforms, `duplicate()`, `imageFromCanvas()`)
in full. If you're packaging something built with `hs.canvas` to share with others, see the
[Spoons guide](spoons-guide.html).
