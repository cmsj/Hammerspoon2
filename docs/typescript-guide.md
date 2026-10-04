Hammerspoon 2 configs are plain JavaScript, but nothing stops you writing them in TypeScript
instead and compiling down to the `.js` file Hammerspoon actually loads. The project ships a
`hammerspoon.d.ts` file with every module, type, and method from the
[API reference](index.html) declared as ambient globals, so `hs`, `console`, `HSRect`, and the
rest are all typed without any `import` statements — the same way they're available at global
scope when Hammerspoon runs your `init.js`. If you haven't written a Hammerspoon 2 config at
all yet, start with the [Getting Started guide](getting-started.html) instead; this guide
assumes you already know the runtime (object lifecycle, `require()`, hotkeys, `hs.ui`) and
just want type checking on top of it.

## Why bother?

- **Autocomplete** for every module and type, in any TypeScript-aware editor.
- **Compile-time errors** for typos (`hs.windw`) and wrong argument types/counts, instead of
  finding out when the callback fires.
- **Inline documentation** — the same `- Parameter:`/`- Returns:` text from the API reference
  shows up as hover tooltips, without switching to a browser.

None of this changes what runs at the other end: Hammerspoon's JavaScriptCore engine has no
idea TypeScript exists. You compile `.ts` to `.js` yourself, and only the compiled output is
ever loaded.

## Setup

### 1. Install TypeScript

In your config directory (`hs.appinfo.configDir`, typically `~/.config/Hammerspoon2/`):

```bash
cd ~/.config/Hammerspoon2
npm init -y
npm install --save-dev typescript
```

### 2. Get the type definitions and a tsconfig

Every published version of these docs carries the exact `hammerspoon.d.ts` and
`tsconfig.example.json` that match it, one directory up from this page, so the links below
always point at files for the version you're reading right now:

- [hammerspoon.d.ts](../hammerspoon.d.ts) — the ambient type declarations
- [tsconfig.example.json](../tsconfig.example.json) — a ready-to-use `tsconfig.json`

Save the first as `hammerspoon.d.ts` and the second as `tsconfig.json`, both directly in your
config directory. Re-download `hammerspoon.d.ts` whenever you update Hammerspoon 2, since
module APIs can gain methods or change shape between versions — `hs.docs.show()` in the
running app's console always matches your installed version exactly, if you'd rather not
guess which docs version that corresponds to on this site.

Everything `hammerspoon.d.ts` declares is also browsable as rendered documentation, in actual
TypeScript syntax rather than the API reference's JS-flavored view — useful for seeing the
real overload signatures and member types at a glance: [the TypeScript API reference](../../ts/index.html).
To read the TS docs using the in-app viewer, call `hs.docs.show(null, true)`.

The example tsconfig's important choices: `module: "commonjs"` (matching how Hammerspoon's
own `require()` works), an `outDir` of `./compiled` so compiled output stays out of the way,
and `strict` mode on. Point its `include` at wherever your `.ts` files actually live:

```json
{
  "include": ["*.ts", "src/**/*.ts"]
}
```

### 3. Write your config in TypeScript

Create `config.ts`:

```typescript
// Show an alert when Hammerspoon loads
hs.ui.alert("Hammerspoon loaded!")

// Bind a hotkey with type checking
hs.hotkey.bind(["cmd", "alt"], "r", () => {
    console.log("Reloading config...")
    hs.reload()
}, null, null)

// Work with windows with autocomplete
const win = hs.window.focusedWindow()
if (win) {
    const frame = win.frame
    console.log(`Window size: ${frame.w} x ${frame.h}`)
}
```

Nothing here differs from the plain-JS version in the [Getting Started guide](getting-started.html)
— the same [object lifecycle rule](getting-started.html#object-lifecycle-the-one-habit-that-saves-you-the-most-debugging-time)
applies, hotkeys and timers still need a kept reference, and `hs.ui` is built the same chained
way. TypeScript only adds the type layer on top; it doesn't change how any of these APIs
behave.

### 4. Compile and load it

```bash
npx tsc
```

This produces `compiled/config.js`. In your `init.js` — which always stays plain JavaScript,
since it's what Hammerspoon loads directly — require the compiled output:

```javascript
require("./compiled/config.js")
```

Remember `require()`'s own rule from the Getting Started guide: the leading `./` is mandatory
for local files, and `init.js` is the one file whose top level runs at true global scope — so
if `config.ts` sets up hotkeys or timers, requiring it from `init.js` is what keeps them alive
long enough to matter, exactly as if that code had been written directly in `init.js`.

## Development workflow

### Watch mode

```bash
npx tsc --watch
```

Recompiles `config.js` every time you save `config.ts`. It won't reload Hammerspoon itself —
pair this with a reload hotkey (`hs.reload()`) or the menu bar's "Reload Config" so you can
pick up each recompiled build.

### npm scripts

```json
{
  "scripts": {
    "build": "tsc",
    "watch": "tsc --watch",
    "clean": "rm -rf compiled"
  }
}
```

## Splitting a TypeScript config across multiple files

This works exactly like the plain-JS version covered in
[Splitting a growing config into multiple files](getting-started.html#splitting-a-growing-config-into-multiple-files)
— `require()` doesn't know or care whether the file it's loading started out as `.ts`, only
that the compiled `.js` exists on disk. A common structure:

```
config/
  src/
    window-management.ts
    hotkeys.ts
  compiled/
    window-management.js
    hotkeys.js
  init.js
```

```typescript
// src/window-management.ts
export function centerFocused(): void {
    const win = hs.window.focusedWindow()
    if (win) win.centerOnScreen()
}
```

```javascript
// init.js
const { centerFocused } = require("./compiled/window-management.js")
hs.hotkey.bind(["cmd", "alt"], "c", centerFocused, null, null)
```

Note the plain `export`/no-`import` mix here: `window-management.ts` uses TypeScript's own
`export` syntax (compiled by `tsc`, with `module: "commonjs"`, into the same `module.exports`
shape `require()` expects), while anything reaching into `hs` itself needs no import at all —
`hammerspoon.d.ts` declares those as ambient globals, available everywhere once it's on your
TypeScript `include`/`files` list.

## Editor setup

### VS Code

Works automatically — just open your config directory and start editing `.ts` files.
Recommended extensions: ESLint, Prettier.

### WebStorm / IntelliJ

TypeScript support is built in; open the folder and go.

### Vim / Neovim

Use a TypeScript language server plugin — `coc.nvim` with `coc-tsserver`, ALE with TypeScript
support, or `vim-lsp` with `typescript-language-server`.

## Troubleshooting

### "Cannot find name 'hs'"

`hammerspoon.d.ts` needs to be visible to the compiler. If it's sitting in your config
directory alongside `tsconfig.json`, TypeScript's default `include` picks it up automatically
as long as its extension (`.d.ts`) is included by the `include` glob you're using, or list it
explicitly:

```json
{
  "files": ["hammerspoon.d.ts"],
  "include": ["*.ts"]
}
```

### "Cannot find module" after compiling

This is almost always the same `require()` path rule from the Getting Started guide, not a
TypeScript problem: `require("./compiled/config.js")`, not `require("compiled/config.js")` — a
bare specifier without `./`/`../` is treated as a lookup for a named package, not a sibling
file.

### Compilation errors from third-party code

If strict mode is fighting code you don't control (a vendored file, a generated file), relax
it for just that corner rather than globally — either exclude the file from `include`, or wrap
the offending lines with an `// @ts-expect-error` comment, rather than turning `strict` off in
`tsconfig.json`.

## Benefits in action

```javascript
// Plain JS: no autocomplete, no type checking
hs.windw.focusedWindow() // Typo! Only fails at runtime, inside the callback that uses it.
```

```typescript
// TypeScript catches the typo at compile time, before you ever reload Hammerspoon:
hs.windw.focusedWindow()
//    ~~~~~ Error: Property 'windw' does not exist on type...
//          Did you mean 'window'?

hs.window.focusedWindow() // Correct — and autocompleted for you.
```

## Learn more

- [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html)
- [TypeScript in 5 Minutes](https://www.typescriptlang.org/docs/handbook/typescript-in-5-minutes.html)
- The [API reference](index.html) — every module and type `hammerspoon.d.ts` declares, with
  full method documentation
- The [TypeScript API reference](../ts/index.html) — the same declarations, rendered from
  `hammerspoon.d.ts` itself in TS syntax (or `hs.docs.show(null, true)` from inside the app)
- [Getting Started](getting-started.html) and the [migration guide](migration-guide.html), if
  you haven't read either yet

If you hit an issue with the type definitions themselves (a missing method, a wrong type),
please open an issue on the [Hammerspoon 2 repository](https://github.com/cmsj/Hammerspoon2/issues)
— they're generated directly from the Swift source, so a gap there usually means a doc-comment
gap in the module itself.
