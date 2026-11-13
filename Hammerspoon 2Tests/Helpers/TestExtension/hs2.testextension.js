"use strict";

// The test extension's enhancement script. It runs once per engine, when the extension is first
// required, as the body of a function whose argument `ext` is the extension's module. Anything
// it sets on `ext` must be declared in the module's API, or it's lost when the wrapper is
// collected.
ext.greet = function (name) {
    return "Hello, " + name + ", from " + ext.toString();
};
