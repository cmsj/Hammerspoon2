//
//  engine.js
//  Hammerspoon 2
//
//  Created by Chris Jones on 21/10/2025.
//

console.log("engine.js loading...")
// FIXME: This is not really useful, it came from https://levelup.gitconnected.com/extend-enum-cases-in-swift-workarounds-and-practical-use-cases-7fcc192f6567
class Enum {
    constructor(...properties) {
        let value = 0;
        properties.forEach( function (prop) {
            const newValue = value;
            Object.defineProperty(this, prop, {
                get: function() { return newValue; }
            });
            value++;
        }, this);
        Object.freeze(this);
    }
}
