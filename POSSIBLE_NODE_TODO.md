# TODO

## Node-like globals for third-party library compatibility

Third-party npm libraries bundled for use with `require()` often assume a Node.js
or browser environment. The following globals are commonly expected but not currently
provided. Implementing them (as shims or real integrations) would broaden the range
of npm packages that work out of the box.

- **`setTimeout` / `setInterval`** — map to `hs.timer.doAfter` / `hs.timer.doEvery`
- **`process.env`, `process.platform`** — minimal `process` object; `platform` would always be `"darwin"`
- **`fs`, `path`, `os`** — Node built-in modules; `fs` and `path` have natural mappings to `hs.fs`
- **`crypto`** — Node's `crypto` module; JavaScriptCoreExtras already provides Web Crypto (`subtle`), but the Node API differs
- **`Buffer`** — Node's binary data type; no direct JSC equivalent
- **`fetch`** — JavaScriptCoreExtras provides this; may just need wiring up
- **`window`, `document`** — browser globals; unclear what these would map to in a macOS automation context
