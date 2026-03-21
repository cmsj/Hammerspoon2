// hs.console.js — companion JS for hs.console module
//
// getConsole/getHistory are declared in the HSConsoleModuleAPI JSExport
// protocol and implemented directly on HSConsoleModule. They survive GC
// automatically because JSC re-exports protocol methods when recreating
// the proxy wrapper. This companion file is a no-op placeholder for
// consistency with other modules.
