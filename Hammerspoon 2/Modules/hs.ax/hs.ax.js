// hs.ax.js
// JavaScript enhancements for the hs.ax module

"use strict";

// FIXME: Consider adding API to introspect what watchers exist and what events they are watching

// Observer management - stores observers by PID and their emitters
const observers = new Map(); // pid -> { observer, emitters: Map(element+notification -> emitter) }

// Helper to create a unique key for element+notification
function makeWatcherKey(element, notification) {
    // Use the element's pid and role/title as part of the key since we can't use object identity
    const elementId = `${element.pid}_${element.role}_${element.title || 'notitle'}`;
    return `${elementId}:${notification}`;
}

// Event emitter for individual element+notification combinations
class AXObserverEmitter {
    #listeners = [];
    #element = null;
    #notification = null;
    #observer = null;

    constructor(element, notification, observer) {
        this.#element = element;
        this.#notification = notification;
        this.#observer = observer;
    }

    handleEvent(observer, element, notification) {
        const listeners = this.#listeners.slice();
        for (let i = 0; i < listeners.length; i++) {
            listeners[i].call(null, element, notification);
        }
    }

    addListener(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.ax.addWatcher(): The provided handler must be a function");
        }

        if (this.#listeners.includes(listener)) {
            console.error("hs.ax.addWatcher(): The provided handler is already registered.");
            return;
        }

        // If this is the first listener, add the watcher to the observer
        if (this.#listeners.length === 0) {
            this.#observer.addWatcher(this.#element, this.#notification);
        }

        this.#listeners.push(listener);
    }

    removeListener(listener) {
        const idx = this.#listeners.indexOf(listener);
        if (idx > -1) {
            this.#listeners.splice(idx, 1);
        }

        // If no more listeners, stop watching this notification
        if (this.#listeners.length === 0) {
            this.#observer.removeWatcher(this.#element, this.#notification);
        }
    }

    hasListeners() {
        return this.#listeners.length > 0;
    }

    get element() {
        return this.#element;
    }

    get notification() {
        return this.#notification;
    }
}

// User-facing API for adding watchers
hs.ax.addWatcher2 = function(application, notification, listener) {
    if (!application || !notification || !listener) {
        throw new Error("hs.ax.addWatcher(): application, notification, and listener are required");
    }

    const pid = application.pid;
    const element = application.axElement();
    if (pid < 0 || element == null) {
        throw new Error("hs.ax.addWatcher(): Invalid HSApplication object");
    }

    // Get or create observer for this PID
    if (!observers.has(pid)) {
        const observer = hs.ax._createObserver(pid);
        if (!observer) {
            throw new Error(`hs.ax.addWatcher(): Failed to create observer for PID ${pid}`);
        }

        const observerData = {
            observer: observer,
            emitters: new Map()
        };

        // Set up a single callback that dispatches to all emitters
        observer.callback((obs, elem, notif) => {
            // Find all emitters that match this element+notification
            for (const [key, emitter] of observerData.emitters) {
                // Check if this emitter matches the notification
                if (emitter.notification === notif) {
                    emitter.handleEvent(obs, elem, notif);
                }
            }
        });

        // Start the observer
        observer.start();

        observers.set(pid, observerData);
    }

    const observerData = observers.get(pid);
    const key = makeWatcherKey(element, notification);

    // Get or create emitter for this element+notification
    if (!observerData.emitters.has(key)) {
        observerData.emitters.set(key, new AXObserverEmitter(element, notification, observerData.observer));
    }

    const emitter = observerData.emitters.get(key);
    emitter.addListener(listener);
};

// User-facing API for removing watchers
hs.ax.removeWatcher = function(element, notification, listener) {
    if (!element || !notification || !listener) {
        throw new Error("hs.ax.removeWatcher(): element, notification, and listener are required");
    }

    const pid = element.pid;
    const observerData = observers.get(pid);

    if (!observerData) {
        return; // No observer for this PID
    }

    const key = makeWatcherKey(element, notification);
    const emitter = observerData.emitters.get(key);

    if (emitter) {
        emitter.removeListener(listener);

        // Clean up emitter if no more listeners
        if (!emitter.hasListeners()) {
            observerData.emitters.delete(key);
        }

        // Clean up observer if no more emitters
        if (observerData.emitters.size === 0) {
            observerData.observer.stop();
            observers.delete(pid);
        }
    }
};

// Convenience function to get the focused element
hs.ax.focusedElement = function() {
    const focusedApp = hs.application.frontmost();
    if (!focusedApp) {
        return null;
    }

    const appElement = hs.ax.applicationElement(focusedApp.pid);
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
