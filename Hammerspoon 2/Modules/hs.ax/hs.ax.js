// hs.ax.js
// JavaScript enhancements for the hs.ax module

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
