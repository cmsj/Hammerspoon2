# Using TypeScript with Hammerspoon 2

This guide explains how to write your Hammerspoon configuration in TypeScript for better autocomplete, type checking, and inline documentation.

## Why TypeScript?

- **Autocomplete**: Get intelligent code completion in VS Code, WebStorm, and other TypeScript-aware editors
- **Type Safety**: Catch errors before running your config
- **Inline Documentation**: See parameter types and descriptions as you code
- **Refactoring**: Safely rename and restructure your code

## Quick Start

### 1. Install TypeScript

First, install TypeScript in your Hammerspoon config directory:

```bash
cd ~/.config/hammerspoon2
npm init -y
npm install --save-dev typescript
```

### 2. Download Type Definitions

Download the Hammerspoon type definitions:

```bash
curl -o hammerspoon.d.ts https://github.com/cmsj/Hammerspoon2/docs/hammerspoon.d.ts
```

### 3. Create TypeScript Configuration

Create a `tsconfig.json` file in `~/.config/hammerspoon2`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "outDir": "./compiled",
    "strict": true,
    "noImplicitAny": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "sourceMap": true
  },
  "include": ["*.ts"],
  "exclude": ["node_modules", "compiled"]
}
```

### 4. Write Your Config in TypeScript

Create `config.ts`:

```typescript
// TypeScript config with full autocomplete!

// Show an alert when Hammerspoon loads
hs.alert.show("Hammerspoon loaded!");

// Bind a hotkey with type checking
hs.hotkey.bind(["cmd", "alt"], "r", () => {
    hs.console.printStyledtext("Reloading config...");
    hs.console.reload();
});

// Work with windows with autocomplete
const win = hs.window.focusedWindow();
if (win) {
    const frame = win.frame();
    console.log(`Window size: ${frame.w} x ${frame.h}`);
}

// Create alerts with the HSAlert API
const alert = new HSAlert("Hello from TypeScript!");
hs.alert.showAlert(alert);
```

### 5. Compile TypeScript to JavaScript

Compile your TypeScript:

```bash
npx tsc
```

This creates `compiled/config.js` which Hammerspoon can run.

### 6. Load Compiled Config

In your main `init.js`, load the compiled JavaScript:

```javascript
// Load the TypeScript-compiled config
require("compiled/config");
```

## Development Workflow

### Watch Mode

For automatic compilation on file changes:

```bash
npx tsc --watch
```

Now whenever you save `config.ts`, it automatically compiles to `config.js`.

### NPM Scripts

Add scripts to your `package.json` for convenience:

```json
{
  "scripts": {
    "build": "tsc",
    "watch": "tsc --watch",
    "clean": "rm -rf compiled"
  }
}
```

Then use:

```bash
npm run build   # Compile once
npm run watch   # Watch for changes
npm run clean   # Remove compiled files
```

## Editor Setup

### VS Code

VS Code works with TypeScript automatically! Just open your `~/.config/hammerspoon2` folder and start coding.

**Recommended extensions:**
- ESLint (for linting)
- Prettier (for formatting)

### WebStorm / IntelliJ

TypeScript support is built-in. Just open the folder and start coding.

### Vim / Neovim

Use a TypeScript language server plugin:
- **coc.nvim**: With `coc-tsserver`
- **ALE**: With TypeScript support
- **vim-lsp**: With `typescript-language-server`

## Example: Full TypeScript Config

Here's a more complete, but completely untested, example showing TypeScript's benefits:

```typescript
// Define a custom type for your config
interface HammerspoonConfig {
    modifiers: string[];
    hotkeys: HotkeyBinding[];
}

interface HotkeyBinding {
    key: string;
    description: string;
    action: () => void;
}

// Configuration with type safety
const config: HammerspoonConfig = {
    modifiers: ["cmd", "alt"],
    hotkeys: [
        {
            key: "r",
            description: "Reload Hammerspoon",
            action: () => hs.console.reload()
        },
        {
            key: "w",
            description: "Show focused window info",
            action: showWindowInfo
        }
    ]
};

// Helper function with type annotations
function showWindowInfo(): void {
    const win = hs.window.focusedWindow();
    if (!win) {
        hs.alert.show("No focused window");
        return;
    }

    const app = win.application();
    const frame = win.frame();

    const message = `
        App: ${app?.title() ?? "Unknown"}
        Size: ${frame.w} x ${frame.h}
        Position: (${frame.x}, ${frame.y})
    `;

    hs.alert.show(message);
}

// Bind all hotkeys from config
config.hotkeys.forEach(binding => {
    hs.hotkey.bind(config.modifiers, binding.key, binding.action);
    console.log(`Bound: ${config.modifiers.join("+")}+${binding.key} - ${binding.description}`);
});

hs.alert.show("TypeScript config loaded!");
```

## Updating Type Definitions

When Hammerspoon's API is updated, download the latest type definitions from the URL above.

## Troubleshooting

### "Cannot find name 'hs'"

Make sure `hammerspoon.d.ts` is in the same directory as your `tsconfig.json`, or add it to the `types` array:

```json
{
  "compilerOptions": {
    "types": ["./hammerspoon"]
  }
}
```

### Compilation Errors

If you see type errors, you can temporarily disable strict mode:

```json
{
  "compilerOptions": {
    "strict": false
  }
}
```

### Source Maps Not Working

Ensure `sourceMap: true` is in your `tsconfig.json` for better debugging.

## Benefits in Action

### Before (JavaScript)
```javascript
// No autocomplete, no type checking
hs.windw.focusedWindow(); // Typo! Runtime error
```

### After (TypeScript)
```typescript
// TypeScript catches the typo at compile time!
hs.windw.focusedWindow();
//    ~~~~~ Error: Property 'windw' does not exist on type...
//          Did you mean 'window'?

// Correct version with autocomplete
hs.window.focusedWindow(); // ✓ Autocomplete suggests this!
```

## Learn More

- [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html)
- [TypeScript in 5 Minutes](https://www.typescriptlang.org/docs/handbook/typescript-in-5-minutes.html)
- [Hammerspoon Documentation](https://cmsj.github.io/Hammerspoon2/)

## Support

If you encounter issues with the type definitions, please open an issue on the [Hammerspoon 2 repository](https://github.com/cmsj/Hammerspoon2/issues).
