"use strict";

// Run once each time a config first requires the extension, as the body of a function whose
// argument, `ext`, is the extension's module.
ext.greet = function (name) {
    return "Hello, " + name + "!";
};
