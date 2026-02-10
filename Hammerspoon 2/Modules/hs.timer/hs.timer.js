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

// Parse time strings
// Supports formats like "HH:MM:SS", "HH:MM", "5m", "2h", "1d", etc.
// FIXME: Decide if we want this or not, and if its name should change. If we want it, document it.
/// SKIP_DOCS
hs.timer.seconds = function(timeString) {
    if (typeof timeString !== 'string') {
        throw new Error("hs.timer.seconds(): argument must be a string");
    }

    // Try parsing as HH:MM:SS or HH:MM format (time since midnight)
    const timeMatch = timeString.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
    if (timeMatch) {
        const hours = parseInt(timeMatch[1]);
        const minutes = parseInt(timeMatch[2]);
        const seconds = timeMatch[3] ? parseInt(timeMatch[3]) : 0;

        if (hours >= 24 || minutes >= 60 || seconds >= 60) {
            throw new Error("hs.timer.seconds(): invalid time string (hours must be < 24, minutes/seconds < 60)");
        }

        return hours * 3600 + minutes * 60 + seconds;
    }

    // Try parsing as duration format: "5m", "2h", "1d", "30s", "500ms"
    const durationMatch = timeString.match(/^(\d+(?:\.\d+)?)(ms|s|m|h|d)$/);
    if (durationMatch) {
        const value = parseFloat(durationMatch[1]);
        const unit = durationMatch[2];

        switch (unit) {
            case 'ms':
                return value / 1000;
            case 's':
                return value;
            case 'm':
                return value * 60;
            case 'h':
                return value * 3600;
            case 'd':
                return value * 86400;
        }
    }

    throw new Error("hs.timer.seconds(): unable to parse time string '" + timeString + "'");
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

// Delayed timer implementation - fires only after a period of inactivity
// FIXME: This seems like a bad idea, and I'm pretty sure it's buggy, like `timer` should be inside `delayedObj`. Decide if we want this or not. Document if we do.
/// SKIP_DOCS
hs.timer.delayed = function(delay, fn) {
    if (typeof fn !== 'function') {
        throw new Error("hs.timer.delayed(): callback must be a function");
    }

    let timer = null;

    const delayedObj = {
        start: function(delayOverride) {
            const actualDelay = delayOverride !== undefined ? delayOverride : delay;

            if (timer) {
                timer.stop();
            }

            timer = hs.timer.doAfter(actualDelay, fn);
            return delayedObj;
        },

        stop: function() {
            if (timer) {
                timer.stop();
                timer = null;
            }
            return delayedObj;
        },

        running: function() {
            return timer ? timer.running() : false;
        },

        nextTrigger: function() {
            return timer ? timer.nextTrigger() : -1;
        },

        setDelay: function(newDelay) {
            delay = newDelay;
            return delayedObj;
        }
    };

    return delayedObj;
};
