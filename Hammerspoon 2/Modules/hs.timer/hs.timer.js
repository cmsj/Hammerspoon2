//
//  hs.timer.js
//  Hammerspoon 2
//
//  Created by Chris Jones on 06/11/2025.
//

"use strict";

// Alias for compatibility with enhancements (they use .new(), but the Swift API is .create())
hs.timer.new = hs.timer.create;

// Time conversion utilities
/// Converts minutes to seconds
/// Parameter n: A number of minutes
/// Returns: The equivalent number of seconds
hs.timer.minutes = function(n) {
    return n * 60;
};

/// Converts hours to seconds
/// Parameter n: A number of hours
/// Returns: The equivalent number of seconds
hs.timer.hours = function(n) {
    return n * 3600;
};

/// Converts days to seconds
/// Parameter n: A number of days
/// Returns: The equivalent number of seconds
hs.timer.days = function(n) {
    return n * 86400;
};

/// Converts weeks to seconds
/// Parameter n: A number of weeks
/// Returns: The equivalent number of seconds
hs.timer.weeks = function(n) {
    return n * 604800;
};

// Predicate-based timers

/// Repeat a function/lambda until a given predicate function/lambda returns true
/// Parameters:
///  - predicateFn: A function/lambda to test if the timer should continue. Return True to end the timer, False to continue it
///  - actionFn: A function/lambda to call until the predicateFn returns true
///  - checkInterval: How often, in seconds, to call actionFn
hs.timer.doUntil = function(predicateFn, actionFn, checkInterval) {
    if (typeof predicateFn !== 'function') {
        throw new Error("hs.timer.doUntil(): predicate must be a function");
    }
    if (typeof actionFn !== 'function') {
        throw new Error("hs.timer.doUntil(): action must be a function");
    }

    checkInterval = checkInterval || 1;

    const timer = hs.timer.new(checkInterval, function() {
        if (predicateFn()) {
            actionFn();
            timer.stop();
        } else {
            actionFn();
        }
    });

    timer.start();
};

/// Repeat a function/lambda while a given predicate function/lambda returns true
/// Parameters:
///  - predicateFn: A function/lambda to test if the timer should continue. Return True to continue the timer, False to end it
///  - actionFn: A function/lambda to call while the predicateFn returns true
///  - checkInterval: How often, in seconds, to call actionFn
hs.timer.doWhile = function(predicateFn, actionFn, checkInterval) {
    if (typeof predicateFn !== 'function') {
        throw new Error("hs.timer.doWhile(): predicate must be a function");
    }
    if (typeof actionFn !== 'function') {
        throw new Error("hs.timer.doWhile(): action must be a function");
    }

    checkInterval = checkInterval || 1;

    const timer = hs.timer.new(checkInterval, function() {
        if (!predicateFn()) {
            timer.stop();
        } else {
            actionFn();
        }
    });

    timer.start();
};

/// Wait to call a function/lambda until a given predicate function/lambda returns true
/// Parameters:
///  - predicateFn: A function/lambda to test if the actionFn should be called. Return True to call the actionFn, False to continue waiting
///  - actionFn: A function/lambda to call when the predicateFn returns true. This will only be called once and then the timer will stop.
///  - checkInterval: How often, in seconds, to call predicateFn
hs.timer.waitUntil = function(predicateFn, actionFn, checkInterval) {
    if (typeof predicateFn !== 'function') {
        throw new Error("hs.timer.waitUntil(): predicate must be a function");
    }
    if (typeof actionFn !== 'function') {
        throw new Error("hs.timer.waitUntil(): action must be a function");
    }

    checkInterval = checkInterval || 1;

    const timer = hs.timer.new(checkInterval, function() {
        if (predicateFn()) {
            actionFn();
            timer.stop();
        }
    });

    return timer.start();
};

/// Wait to call a function/lambda until a given predicate function/lambda returns false
/// Parameters:
///  - predicateFn: A function/lambda to test if the actionFn should be called. Return False to call the actionFn, True to continue waiting
///  - actionFn: A function/lambda to call when the predicateFn returns False. This will only be called once and then the timer will stop.
///  - checkInterval: How often, in seconds, to call predicateFn
hs.timer.waitWhile = function(predicateFn, actionFn, checkInterval) {
    if (typeof predicateFn !== 'function') {
        throw new Error("hs.timer.waitWhile(): predicate must be a function");
    }
    if (typeof actionFn !== 'function') {
        throw new Error("hs.timer.waitWhile(): action must be a function");
    }

    checkInterval = checkInterval || 1;

    const timer = hs.timer.new(checkInterval, function() {
        if (!predicateFn()) {
            actionFn();
            timer.stop();
        }
    });

    return timer.start();
};
