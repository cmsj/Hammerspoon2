"use strict";

// The test extension's enhancement script. It runs once per engine, when the extension is first
// required, as the body of a function whose argument `ext` is the extension's module. Anything
// it sets on `ext` must be declared in the module's API, or it's lost when the wrapper is
// collected.

// Lets a test check what happens when an enhancement script throws
if (globalThis.__hs2TestExtensionScriptThrows) {
    throw new Error("the test extension's script failed");
}

ext.greet = function (name) {
    return "Hello, " + name + ", from " + ext.toString();
};
