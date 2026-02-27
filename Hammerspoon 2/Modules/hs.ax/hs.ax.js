// hs.ax.js
// JavaScript enhancements for the hs.ax module

"use strict";

// One-to-many event emitter for hs.ax events
// Similar to ApplicationModuleWatcherEmitter, this allows multiple JavaScript listeners
// for the same notification, while Swift only manages a single callback per app+notification
class AXModuleWatcherEmitter {
    #events = {}

    constructor() {}

    #handleEvent(key, notification, element) {
        if (Array.isArray(this.#events[key])) {
            var listeners = this.#events[key].slice();
            const length = listeners.length;

            for (var i = 0; i < length; i++) {
                listeners[i].apply(null, [notification, element]);
            }
        }
    }

    on(application, notification, listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.ax.addWatcher(): The provided handler must be a function");
        }

        // Create a unique key for this application+notification combination
        const key = `${application.pid}:${notification}`;

        if (!Array.isArray(this.#events[key])) {
            this.#events[key] = [];
            // First listener for this app+notification - register with Swift
            hs.ax._addWatcher(application, notification, (notif, elem) => {
                this.#handleEvent(key, notif, elem);
            });
        }

        if (this.#events[key].includes(listener)) {
            console.error(`hs.ax.addWatcher(): The provided handler for '${notification}' is already registered.`);
            return;
        }

        this.#events[key].push(listener);
    }

    removeListener(application, notification, listener) {
        const key = `${application.pid}:${notification}`;
        var idx;

        if (Array.isArray(this.#events[key])) {
            idx = this.#events[key].indexOf(listener);

            if (idx > -1) {
                this.#events[key].splice(idx, 1);
            }

            // If no more listeners for this app+notification, remove from Swift
            if (this.#events[key].length == 0) {
                hs.ax._removeWatcher(application, notification);
                delete this.#events[key];
            }
        }
    }
}

// Store an instance of the Watcher/Emitter in a Swift-retained property so it is not garbage collected.
hs.ax._watcherEmitter = new AXModuleWatcherEmitter();

// Convenience function to get the focused element
/// Fetch the focused UI element
/// Returns: An HSAXElement representing the focused UI element, or null if none was found
hs.ax.focusedElement = function() {
    const focusedApp = hs.application.frontmost();
    if (!focusedApp) {
        return null;
    }

    const appElement = hs.ax.applicationElement(focusedApp);
    if (!appElement) {
        return null;
    }

    // Find the focused element within the app
    const children = appElement.children();
    for (let child of children) {
        if (child.isFocused) {
            return child;
        }
    }

    return appElement;
};

// Helper to search for elements by role
/// Find AX elements for a given role
/// Parameters:
///  - role: The role name to search for
///  - parent: An HSAXElement object to search. If none is supplied, the search will be conducted system-wide
/// Returns: An array of found elements
hs.ax.findByRole = function(role, parent) {
    const searchRoot = parent || hs.ax.systemWideElement();
    if (!searchRoot) {
        return [];
    }

    const results = [];
    const stack = [searchRoot];

    while (stack.length > 0) {
        const element = stack.pop();

        if (element.role === role) {
            results.push(element);
        }

        const children = element.children();
        for (let child of children) {
            stack.push(child);
        }
    }

    return results;
};

// Helper to search for elements by title
/// Find AX elements by title
/// Parameters:
///  - title: The name to search for
///  - parent: An HSAXElement object to search. If none is supplied, the search will be conducted system-wide
/// Returns: An array of found elements
hs.ax.findByTitle = function(title, parent) {
    const searchRoot = parent || hs.ax.systemWideElement();
    if (!searchRoot) {
        return [];
    }

    const results = [];
    const stack = [searchRoot];

    while (stack.length > 0) {
        const element = stack.pop();

        if (element.title && element.title.includes(title)) {
            results.push(element);
        }

        const children = element.children();
        for (let child of children) {
            stack.push(child);
        }
    }

    return results;
};

// Helper to print element hierarchy
/// Prints the hierarchy of a given element to the Console
/// Parameters:
///  - element: An HSAXElement
///  - depth: This parameter should not be supplied
hs.ax.printHierarchy = function(element, depth = 0) {
    element = element || hs.ax.systemWideElement();
    if (!element) {
        console.log("No element provided");
        return;
    }

    const indent = "  ".repeat(depth);
    const role = element.role || "unknown";
    const title = element.title || "";
    const titleStr = title ? ` "${title}"` : "";

    console.log(`${indent}${role}${titleStr}`);

    if (depth < 5) { // Limit depth to avoid infinite recursion
        const children = element.children();
        for (let child of children) {
            hs.ax.printHierarchy(child, depth + 1);
        }
    }
};
