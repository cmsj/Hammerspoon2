// TypeScript definitions for Hammerspoon 2
// Auto-generated from API documentation
// DO NOT EDIT - Regenerate using: npm run docs:typescript

// ========================================
// Global Types
// ========================================

/**
 * This is a JavaScript object used to represent macOS fonts. It includes a variety of static methods that can instantiate the various font sizes commonly used with UI elements, and also includes static methods for instantiating the system font at various sizes/weights, or any custom font available on the system.
 */
declare class HSFont {
}

/**
 * This is a JavaScript object used to represent coordinates, or "points", as used in various places throughout Hammerspoon's API, particularly where dealing with positions on a screen. Behind the scenes it is a wrapper for the CGPoint type in Swift/ObjectiveC.
 */
declare class HSPoint {
}

/**
 * This is a JavaScript object used to represent a rectangle, as used in various places throughout Hammerspoon's API, particularly where dealing with portions of a display. Behind the scenes it is a wrapper for the CGRect type in Swift/ObjectiveC.
 */
declare class HSRect {
}

/**
 * This is a JavaScript object used to represent the size of a rectangle, as used in various places throughout Hammerspoon's API, particularly where dealing with portions of a display. Behind the scenes it is a wrapper for the CGSize type in Swift/ObjectiveC.
 */
declare class HSSize {
}

// ========================================
// Modules
// ========================================

/**
 * These functions are provided to maintain convenience with the console.log() function present in many JavaScript instances.
 */
declare namespace console {
}

/**
 * Module for accessing information about the Hammerspoon application itself
 */
declare namespace hs.alert {
}

/**
 * An object for use with hs.alert API
 */
declare class HSAlert {
}

/**
 * Module for accessing information about the Hammerspoon application itself
 */
declare namespace hs.appinfo {
}

/**
 * Module for interacting with applications
 */
declare namespace hs.application {
    /**
     * Create a watcher for application events
     * @param event The event type to listen for
     * @param listener A javascript function/lambda to call when the event is received. The function will be called with two parameters: the name of the event, and the associated HSApplication object
     */
    function addWatcher(event: any, listener: any): void;

    /**
     * Remove a watcher for application events
     * @param event The event type to stop listening for
     * @param listener The javascript function/lambda that was previously being used to handle the event
     */
    function removeWatcher(event: any, listener: any): void;

}

/**
 * Object representing an application. You should not instantiate this directly in JavaScript, but rather, use the methods from hs.application which will return appropriate HSApplication objects.
 */
declare class HSApplication {
}

/**
 * # Accessibility API Module
## Basic Usage
```js
// Get the focused UI element
const element = hs.ax.focusedElement();
console.log(element.role, element.title);

// Watch for window creation events
const app = hs.application.frontmost();
hs.ax.addWatcher(app, "AXWindowCreated", (notification, element) => {
    console.log("New window:", element.title);
});
```
**Note:** Requires accessibility permissions in System Preferences.
 */
declare namespace hs.ax {
    /**
     * Add a watcher for application AX events
     * @param application An HSApplication object
     * @param notification An event name
     * @param listener A function/lambda to be called when the event is fired. The function/lambda will be called with two arguments: the name of the event, and the element it applies to
     */
    function addWatcher(application: any, notification: any, listener: any): void;

    /**
     * Remove a watcher for application AX events
     * @param application An HSApplication object
     * @param notification The event name to stop watching
     * @param listener The function/lambda provided when adding the watcher
     */
    function removeWatcher(application: any, notification: any, listener: any): void;

    /**
     * Fetch the focused UI element
     * @returns An HSAXElement representing the focused UI element, or null if none was found
     */
    function focusedElement(): any;

    /**
     * Find AX elements for a given role
     * @param role The role name to search for
     * @param parent An HSAXElement object to search. If none is supplied, the search will be conducted system-wide
     * @returns An array of found elements
     */
    function findByRole(role: any, parent: any): any;

    /**
     * Find AX elements by title
     * @param title The name to search for
     * @param parent An HSAXElement object to search. If none is supplied, the search will be conducted system-wide
     * @returns An array of found elements
     */
    function findByTitle(title: any, parent: any): any;

    /**
     * Prints the hierarchy of a given element to the Console
     * @param element An HSAXElement
     * @param depth This parameter should not be supplied
     */
    function printHierarchy(element: any, depth: any): void;

}

/**
 * Object representing an Accessibility element. You should not instantiate this directly, but rather, use the hs.ax methods to create these as required.
 */
declare class HSAXElement {
}

/**
 * Module for controlling the Hammerspoon console
 */
declare namespace hs.console {
}

/**
 * Module for hashing and encoding operations
 */
declare namespace hs.hash {
}

/**
 * Module for creating and managing system-wide hotkeys
 */
declare namespace hs.hotkey {
}

/**
 * Object representing a system-wide hotkey. You should not create these objects directly, but rather, use the methods in hs.hotkey to instantiate these.
 */
declare class HSHotkey {
}

/**
 * Module for checking and requesting system permissions
 */
declare namespace hs.permissions {
}

/**
 * Module for running external processes
 */
declare namespace hs.task {
    /**
     * Create and run a task asynchronously
     * @param launchPath - Full path to the executable
     * @param args - Array of arguments
     * @param options - Options object or legacy callback
     * @param options .environment - Environment variables (optional)
     * @param options .workingDirectory - Working directory (optional)
     * @param options .onOutput - Callback for streaming output: (stream, data) => {} (optional)
     * @param legacyStreamCallback - Legacy streaming callback (optional)
     * @returns {Promise<{exitCode: number, stdout: string, stderr: string}>}
     */
    function run(launchPath: string, args: string[], options: Object|Function, options: Object, options: string, options: Function, legacyStreamCallback: Function): any;

    /**
     * Run a shell command asynchronously
     * @param command - Shell command to execute
     * @param options - Options (same as run)
     * @returns {Promise<{exitCode: number, stdout: string, stderr: string}>}
     */
    function shell(command: string, options: Object): any;

    /**
     * Run multiple tasks in parallel
     * @param tasks - Array of task specifications: [{path, args, options}, ...]
     * @returns Array of results
     */
    function parallel(tasks: Array): Promise<Array>;

    /**
     * Create a task builder for fluent API
     * @param launchPath - Full path to the executable
     * @returns {TaskBuilder}
     */
    function builder(launchPath: string): any;

}

/**
 * Object representing an external process task
 */
declare class HSTask {
}

/**
 * Module for creating and managing timers
 */
declare namespace hs.timer {
    /**
     * Converts minutes to seconds
Parameter n: A number of minutes
     * @param n A number of minutes
     * @returns The equivalent number of seconds
     */
    function minutes(n: any): any;

    /**
     * Converts hours to seconds
Parameter n: A number of hours
     * @param n A number of hours
     * @returns The equivalent number of seconds
     */
    function hours(n: any): any;

    /**
     * Converts days to seconds
Parameter n: A number of days
     * @param n A number of days
     * @returns The equivalent number of seconds
     */
    function days(n: any): any;

    /**
     * Converts weeks to seconds
Parameter n: A number of weeks
     * @param n A number of weeks
     * @returns The equivalent number of seconds
     */
    function weeks(n: any): any;

    /**
     * SKIP_DOCS
     */
    function seconds(): void;

    /**
     * Repeat a function/lambda until a given predicate function/lambda returns true
     * @param predicateFn A function/lambda to test if the timer should continue. Return True to end the timer, False to continue it
     * @param actionFn A function/lambda to call until the predicateFn returns true
     * @param checkInterval How often, in seconds, to call actionFn
     */
    function doUntil(predicateFn: any, actionFn: any, checkInterval: any): void;

    /**
     * Repeat a function/lambda while a given predicate function/lambda returns true
     * @param predicateFn A function/lambda to test if the timer should continue. Return True to continue the timer, False to end it
     * @param actionFn A function/lambda to call while the predicateFn returns true
     * @param checkInterval How often, in seconds, to call actionFn
     */
    function doWhile(predicateFn: any, actionFn: any, checkInterval: any): void;

    /**
     * Wait to call a function/lambda until a given predicate function/lambda returns true
     * @param predicateFn A function/lambda to test if the actionFn should be called. Return True to call the actionFn, False to continue waiting
     * @param actionFn A function/lambda to call when the predicateFn returns true. This will only be called once and then the timer will stop.
     * @param checkInterval How often, in seconds, to call predicateFn
     */
    function waitUntil(predicateFn: any, actionFn: any, checkInterval: any): void;

    /**
     * Wait to call a function/lambda until a given predicate function/lambda returns false
     * @param predicateFn A function/lambda to test if the actionFn should be called. Return False to call the actionFn, True to continue waiting
     * @param actionFn A function/lambda to call when the predicateFn returns False. This will only be called once and then the timer will stop.
     * @param checkInterval How often, in seconds, to call predicateFn
     */
    function waitWhile(predicateFn: any, actionFn: any, checkInterval: any): void;

    /**
     * SKIP_DOCS
     */
    function delayed(): void;

}

/**
 * Object representing a timer. You should not instantiate these yourself, but rather, use the methods in hs.timer to create them for you.
 */
declare class HSTimer {
}

/**
 * # hs.ui
**Create custom user interfaces, alerts, dialogs, and file pickers**
The `hs.ui` module provides a comprehensive set of tools for creating custom user interfaces
in Hammerspoon. It supports everything from simple alerts to complex custom windows with
SwiftUI-like declarative syntax.
## Key Features
## Basic Examples
### Simple Alert
```javascript
hs.ui.alert("Task completed!")
    .duration(3)
    .show();
```
### Dialog with Buttons
```javascript
hs.ui.dialog("Save changes?")
    .informativeText("Your document has unsaved changes.")
    .buttons(["Save", "Don't Save", "Cancel"])
    .onButton((index) => {
        if (index === 0) print("Saving...");
    })
    .show();
```
### Text Input Prompt
```javascript
hs.ui.textPrompt("Enter your name")
    .defaultText("John Doe")
    .onButton((buttonIndex, text) => {
        print("User entered: " + text);
    })
    .show();
```
### File Picker
```javascript
hs.ui.filePicker()
    .message("Choose a file")
    .allowedFileTypes(["txt", "md"])
    .onSelection((path) => {
        if (path) print("Selected: " + path);
    })
    .show();
```
### Custom Window
```javascript
hs.ui.window({x: 100, y: 100, w: 300, h: 200})
    .vstack()
        .spacing(10)
        .padding(20)
        .text("Hello, World!")
            .font(HSFont.title())
            .foregroundColor("#FFFFFF")
        .rectangle()
            .fill("#4A90E2")
            .cornerRadius(10)
            .frame({w: "100%", h: 60})
    .end()
    .backgroundColor("#2C3E50")
    .show();
```
 */
declare namespace hs.ui {
}

/**
 * Module for interacting with windows
 */
declare namespace hs.window {
    /**
     * Find windows by title
Parameter title: The window title to search for. All windows with titles that include this string, will be matched
     * @param title The window title to search for. All windows with titles that include this string, will be matched
     * @returns An array of HSWindow objects with matching titles
     */
    function findByTitle(title: any): any;

    /**
     * Get all windows for the current application
     * @returns An array of HSWindow objects
     */
    function currentWindows(): any;

    /**
     * Move a window to left half of screen
Parameter win: An HSWindow object
     * @param win An HSWindow object
     * @returns True if the operation was successful, otherwise False
     */
    function moveToLeftHalf(win: any): any;

    /**
     * Move a window to right half of screen
Parameter win: An HSWindow object
     * @param win An HSWindow object
     * @returns True if the operation was successful, otherwise False
     */
    function moveToRightHalf(win: any): any;

    /**
     * Maximize a window
Parameter win: An HSWindow object
     * @param win An HSWindow object
     * @returns True if the operation was successful, otherwise false
     */
    function maximize(win: any): any;

    /**
     * SKIP_DOCS
     */
    function cycleWindows(): void;

}

/**
 * Object representing a window. You should not instantiate these directly, but rather, use the methods in hs.window to create them for you.
 */
declare class HSWindow {
}

