//
//  docs-strings.js
//  Hammerspoon 2
//
//  Wording shared by every docs generator, so the HTML, TypeScript and JSDoc output can't drift
//  apart.
//

// Rendered for any method whose docs carry a `Throws: true` marker (see extract-docs.js).
const THROWS_DESCRIPTION = 'Throws an Error on failure; wrap calls in try/catch to handle it.';

module.exports = { THROWS_DESCRIPTION };
