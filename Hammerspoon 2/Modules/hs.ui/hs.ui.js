// hs.ui JavaScript extensions
//
// This file provides JavaScript-side enhancements for the hs.ui module

// Export HSColor to global scope for convenience
if (typeof HSColor === 'undefined') {
    console.log("Warning: HSColor not found in JavaScript context");
}

// Export HSFont to global scope for convenience
if (typeof HSFont === 'undefined') {
    console.log("Warning: HSFont not found in JavaScript context");
}

// Module is ready
console.log("hs.ui module loaded");
