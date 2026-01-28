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
    /**
     * Body text style
     * @returns An HSFont object
     */
    static body(): HSFont;

    /**
     * Callout text style
     * @returns An HSFont object
     */
    static callout(): HSFont;

    /**
     * Caption text style
     * @returns An HSFont object
     */
    static caption(): HSFont;

    /**
     * Caption2 text style
     * @returns An HSFont object
     */
    static caption2(): HSFont;

    /**
     * Footnote text style
     * @returns An HSFont object
     */
    static footnote(): HSFont;

    /**
     * Headline text style
     * @returns An HSFont object
     */
    static headline(): HSFont;

    /**
     * Large Title text style
     * @returns An HSFont object
     */
    static largeTitle(): HSFont;

    /**
     * Sub-headline text style
     * @returns An HSFont object
     */
    static subheadline(): HSFont;

    /**
     * Title text style
     * @returns An HSFont object
     */
    static title(): HSFont;

    /**
     * Title2 text style
     * @returns An HSFont object
     */
    static title2(): HSFont;

    /**
     * Title3 text style
     * @returns An HSFont object
     */
    static title3(): HSFont;

    /**
     * The system font in a custom size
     * @param size The font size in points
     * @returns An HSFont object
     */
    static system(size: number): HSFont;

    /**
     * The system font in a custom size with a choice of weights
     * @param size The font size in points
     * @param weight The font weight as a string (e.g. "ultralight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black")
     * @returns An HSFont object
     */
    static system(size: number, weight: string): HSFont;

    /**
     * A font present on the system at a given size
     * @param name A string containing the name of the font to instantiate
     * @param size The font size in points
     * @returns An HSFont object
     */
    static custom(name: string, size: number): HSFont;

}

/**
 * This is a JavaScript object used to represent coordinates, or "points", as used in various places throughout Hammerspoon's API, particularly where dealing with positions on a screen. Behind the scenes it is a wrapper for the CGPoint type in Swift/ObjectiveC.
 */
declare class HSPoint {
    /**
     * Create a new HSPoint object
     * @param x A coordinate for this point on the x-axis
     * @param y A coordinate for this point on the y-axis
     */
    constructor(x: number, y: number);

    /**
     * A coordinate for the x-axis position of this point
     */
    x: number;

    /**
     * A coordinate for the y-axis position of this point
     */
    y: number;

}

/**
 * This is a JavaScript object used to represent a rectangle, as used in various places throughout Hammerspoon's API, particularly where dealing with portions of a display. Behind the scenes it is a wrapper for the CGRect type in Swift/ObjectiveC.
 */
declare class HSRect {
    /**
     * Create a new HSRect object
     * @param x The x-axis coordinate of the top-left corner
     * @param y The y-axis coordinate of the top-left corner
     * @param w The width of the rectangle
     * @param h The height of the rectangle
     */
    constructor(x: number, y: number, w: number, h: number);

    /**
     * An x-axis coordinate for the top-left point of the rectangle
     */
    x: number;

    /**
     * A y-axis coordinate for the top-left point of the rectangle
     */
    y: number;

    /**
     * The width of the rectangle
     */
    w: number;

    /**
     * The height of the rectangle
     */
    h: number;

    /**
     * The "origin" of the rectangle, ie the coordinates of its top left corner, as an HSPoint object
     */
    origin: HSPoint;

    /**
     * The size of the rectangle, ie its width and height, as an HSSize object
     */
    size: HSSize;

}

/**
 * This is a JavaScript object used to represent the size of a rectangle, as used in various places throughout Hammerspoon's API, particularly where dealing with portions of a display. Behind the scenes it is a wrapper for the CGSize type in Swift/ObjectiveC.
 */
declare class HSSize {
    /**
     * Create a new HSSize object
     * @param w The width of the rectangle
     * @param h The height of the rectangle
     */
    constructor(w: number, h: number);

    /**
     * The width of the rectangle
     */
    w: number;

    /**
     * The height of the rectangle
     */
    h: number;

}

// ========================================
// Modules
// ========================================

/**
 * These functions are provided to maintain convenience with the console.log() function present in many JavaScript instances.
 */
declare namespace console {
    /**
     * Log a message to the Hammerspoon Log Window
     * @param message A message to log
     */
    function log(message: string): void;

    /**
     * Log an error to the Hammerspoon Log Window
     * @param message An error message
     */
    function error(message: string): void;

    /**
     * Log a warning to the Hammerspoon Log WIndow
     * @param message A warning message
     */
    function warn(message: string): void;

    /**
     * Log an informational message to the Hammerspoon Log Window
     * @param message An informational message
     */
    function info(message: string): void;

    /**
     * Log a debug message to the Hammerspoon Log Window
     * @param message A debug message
     */
    function debug(message: string): void;

}

/**
 * Module for accessing information about the Hammerspoon application itself
 */
declare namespace hs.alert {
    /**
     * Show an HSAlert object
     * @param alert The HSAlert object to show
     */
    function showAlert(alert: HSAlert): void;

    /**
     * Show an alert to the user
     * @param message The text to include in the alert
     */
    function show(message: string): void;

}

/**
 * An object for use with hs.alert API
 */
declare class HSAlert {
    /**
     * Create a new HSAlert object
     * @param message The mssage to show in the alert
     */
    constructor(message: string);

    /**
     * The message to display in an alert
     */
    message: string;

    /**
     * How many seconds the alert should be shown for
     */
    expire: number;

    /**
     * An HSFont describing the font to use in the alert
     */
    font: HSFont;

    /**
     * How many points of padding to use in the alert
     */
    padding: number;

}

/**
 * Module for accessing information about the Hammerspoon application itself
 */
declare namespace hs.appinfo {
    /**
     * The application's internal name (e.g., "Hammerspoon 2")
     */
    const appName: string;

    /**
     * The application's display name shown to users
     */
    const displayName: string;

    /**
     * The application's version string (e.g., "2.0.0")
     */
    const version: string;

    /**
     * The application's build number
     */
    const build: string;

    /**
     * The minimum macOS version required to run this application
     */
    const minimumOSVersion: string;

    /**
     * The copyright notice for this application
     */
    const copyrightNotice: string;

    /**
     * The application's bundle identifier (e.g., "com.hammerspoon.Hammerspoon-2")
     */
    const bundleIdentifier: string;

    /**
     * The filesystem path to the application bundle
     */
    const bundlePath: string;

    /**
     * The filesystem path to the application's resource directory
     */
    const resourcePath: string;

}

/**
 * Module for interacting with applications
 */
declare namespace hs.application {
    /**
     * Fetch all running applications
     * @returns An array of all currently running applications
     */
    function runningApplications(): HSApplication[];

    /**
     * Fetch the first running application that matches a name
     * @param name The applicaiton name to search for
     * @returns The first matching application, or nil if none matched
     */
    function matchingName(name: string): HSApplication | undefined;

    /**
     * Fetch the first running application that matches a Bundle ID
     * @param bundleID The identifier to search for
     * @returns The first matching application, or nil if none matched
     */
    function matchingBundleID(bundleID: string): HSApplication | undefined;

    /**
     * Fetch the running application that matches a POSIX PID
     * @param pid The PID to search for
     * @returns The matching application, or nil if none matched
     */
    function fromPID(pid: number): HSApplication | undefined;

    /**
     * Fetch the currently focused application
     * @returns The matching application, or nil if none matched
     */
    function frontmost(): HSApplication | undefined;

    /**
     * Fetch the application which currently owns the menu bar
     * @returns The matching application, or nil if none matched
     */
    function menuBarOwner(): HSApplication | undefined;

    /**
     * Fetch the filesystem path for an application
     * @param bundleID The application bundle identifier to search for (e.g. "com.apple.Safari")
     * @returns The application's filesystem path, or nil if it was not found
     */
    function pathForBundleID(bundleID: string): string | undefined;

    /**
     * Fetch filesystem paths for an application
     * @param bundleID The application bundle identifier to search for (e.g. "com.apple.Safari")
     * @returns An array of strings containing any filesystem paths that were found
     */
    function pathsForBundleID(bundleID: string): string[];

    /**
     * Fetch filesystem path for an application able to open a given file type
     * @param fileType The file type to search for. This can be a UTType identifier, a MIME type, or a filename extension
     * @returns The path to an application for the given filetype, or il if none were found
     */
    function pathForFileType(fileType: string): string | undefined;

    /**
     * Fetch filesystem paths for applications able to open a given file type
     * @param fileType The file type to search for. This can be a UTType identifier, a MIME type, or a filename extension
     * @returns An array of strings containing the filesystem paths for any applications that were found
     */
    function pathsForFileType(fileType: string): string[];

    /**
     * Launch an application, or give it focus if it's already running
     * @param bundleID A bundle identifier for the app to launch/focus (e.g. "com.apple.Safari")
     * @returns A Promise that resolves to true if successful, false otherwise
     */
    function launchOrFocus(bundleID: string): Promise<boolean>;

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
    /**
     * Terminate the application
     * @returns True if the application was terminated, otherwise false
     */
    static kill(): boolean;

    /**
     * Force-terminate the application
     * @returns True if the application was force-terminated, otherwise false
     */
    static kill9(): boolean;

    /**
     * The application's HSAXElement object, for use with the hs.ax APIs
     * @returns An HSAXElement object, or nil if it could not be obtained
     */
    static axElement(): HSAXElement | undefined;

    /**
     * POSIX Process Identifier
     */
    pid: number;

    /**
     * Bundle Identifier (e.g. com.apple.Safari)
     */
    bundleID: string | undefined;

    /**
     * The application's title
     */
    title: string | undefined;

    /**
     * Location of the application on disk
     */
    bundlePath: string | undefined;

    /**
     * Is the application hidden
     */
    isHidden: boolean;

    /**
     * Is the application focused
     */
    isActive: boolean;

    /**
     * The main window of this application, or nil if there is no main window
     */
    mainWindow: HSWindow | undefined;

    /**
     * The focused window of this application, or nil if there is no focused window
     */
    focusedWindow: HSWindow | undefined;

    /**
     * All windows of this application
     */
    allWindows: HSWindow[];

    /**
     * All visible (ie non-hidden) windows of this application
     */
    visibleWindows: HSWindow[];

}

/**
 * # Accessibility API Module ## Basic Usage ```js // Get the focused UI element const element = hs.ax.focusedElement(); console.log(element.role, element.title); // Watch for window creation events const app = hs.application.frontmost(); hs.ax.addWatcher(app, "AXWindowCreated", (notification, element) => { console.log("New window:", element.title); }); ``` **Note:** Requires accessibility permissions in System Preferences.
 */
declare namespace hs.ax {
    /**
     * Get the system-wide accessibility element
     * @returns The system-wide AXElement, or nil if accessibility is not available
     */
    function systemWideElement(): HSAXElement | undefined;

    /**
     * Get the accessibility element for an application
     * @param element An HSApplication object
     * @returns The AXElement for the application, or nil if accessibility is not available
     */
    function applicationElement(element: HSApplication): HSAXElement | undefined;

    /**
     * Get the accessibility element for a window
     * @param window An HSWindow  object
     * @returns The AXElement for the window, or nil if accessibility is not available
     */
    function windowElement(window: HSWindow): HSAXElement | undefined;

    /**
     * Get the accessibility element at the specific screen position
     * @param point An HSPoint object containing screen coordinates
     * @returns The AXElement at that position, or nil if none found
     */
    function elementAtPoint(point: HSPoint): HSAXElement | undefined;

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

    /**
     * A dictionary containing all of the notification types that can be used with hs.ax.addWatcher()
     */
    const notificationTypes: Record<string, string>;

}

/**
 * Object representing an Accessibility element. You should not instantiate this directly, but rather, use the hs.ax methods to create these as required.
 */
declare class HSAXElement {
    /**
     * The element's children
     * @returns An array of HSAXElement objects
     */
    static children(): HSAXElement[];

    /**
     * Get a specific child by index
     * @param index The index to fetch
     * @returns An HSAXElement object, if a child exists at the given index
     */
    static childAtIndex(index: number): HSAXElement | undefined;

    /**
     * Get all available attribute names
     * @returns An array of attribute names
     */
    static attributeNames(): string[];

    /**
     * Get the value of a specific attribute
     * @param attribute The attribute name to fetch the value for
     * @returns The requested value, or nil if none was found
     */
    static attributeValue(attribute: string): any | undefined;

    /**
     * Set the value of a specific attribute
     * @param attribute The attribute name to set
     * @param value The value to set
     * @returns True if the operation succeeded, otherwise False
     */
    static setAttributeValue(attribute: string, value: any): boolean;

    /**
     * Check if an attribute is settable
     * @param attribute An attribute name
     * @returns True if the attribute is settable, otherwise False
     */
    static isAttributeSettable(attribute: string): boolean;

    /**
     * Get all available action names
     * @returns An array of available action names
     */
    static actionNames(): string[];

    /**
     * Perform a specific action
     * @param action The action to perform
     * @returns True if the action succeeded, otherwise False
     */
    static performAction(action: string): boolean;

    /**
     * The element's role (e.g., "AXWindow", "AXButton")
     */
    role: string | undefined;

    /**
     * The element's subrole
     */
    subrole: string | undefined;

    /**
     * The element's title
     */
    title: string | undefined;

    /**
     * The element's value
     */
    value: any | undefined;

    /**
     * The element's description
     */
    elementDescription: string | undefined;

    /**
     * Whether the element is enabled
     */
    isEnabled: boolean;

    /**
     * Whether the element is focused
     */
    isFocused: boolean;

    /**
     * The element's position on screen
     */
    position: HSPoint | undefined;

    /**
     * The element's size
     */
    size: HSSize | undefined;

    /**
     * The element's frame (position and size combined)
     */
    frame: HSRect | undefined;

    /**
     * The element's parent
     */
    parent: HSAXElement | undefined;

    /**
     * Get the process ID of the application that owns this element
     */
    pid: number;

}

/**
 * Module for controlling the Hammerspoon console
 */
declare namespace hs.console {
    /**
     * Open the console window
     */
    function open(): void;

    /**
     * Close the console window
     */
    function close(): void;

    /**
     * Clear all console output
     */
    function clear(): void;

    /**
     * Print a message to the console
     * @param message The message to print
     */
    function print(message: string): void;

    /**
     * Print a debug message to the console
     * @param message The message to print
     */
    function debug(message: string): void;

    /**
     * Print an info message to the console
     * @param message The message to print
     */
    function info(message: string): void;

    /**
     * Print a warning message to the console
     * @param message The message to print
     */
    function warning(message: string): void;

    /**
     * Print an error message to the console
     * @param message The message to print
     */
    function error(message: string): void;

}

/**
 * Module for hashing and encoding operations
 */
declare namespace hs.hash {
    /**
     * Encode a string to base64
     * @param data The string to encode
     * @returns Base64 encoded string
     */
    function base64Encode(data: string): string;

    /**
     * Decode a base64 string
     * @param data The base64 string to decode
     * @returns Decoded string, or nil if the input is invalid
     */
    function base64Decode(data: string): string | undefined;

    /**
     * Generate MD5 hash of a string
     * @param data The string to hash
     * @returns Hexadecimal MD5 hash
     */
    function md5(data: string): string;

    /**
     * Generate SHA1 hash of a string
     * @param data The string to hash
     * @returns Hexadecimal SHA1 hash
     */
    function sha1(data: string): string;

    /**
     * Generate SHA256 hash of a string
     * @param data The string to hash
     * @returns Hexadecimal SHA256 hash
     */
    function sha256(data: string): string;

    /**
     * Generate SHA512 hash of a string
     * @param data The string to hash
     * @returns Hexadecimal SHA512 hash
     */
    function sha512(data: string): string;

    /**
     * Generate HMAC-MD5 of a string with a key
     * @param key The secret key
     * @param data The data to authenticate
     * @returns Hexadecimal HMAC-MD5
     */
    function hmacMD5(key: string, data: string): string;

    /**
     * Generate HMAC-SHA1 of a string with a key
     * @param key The secret key
     * @param data The data to authenticate
     * @returns Hexadecimal HMAC-SHA1
     */
    function hmacSHA1(key: string, data: string): string;

    /**
     * Generate HMAC-SHA256 of a string with a key
     * @param key The secret key
     * @param data The data to authenticate
     * @returns Hexadecimal HMAC-SHA256
     */
    function hmacSHA256(key: string, data: string): string;

    /**
     * Generate HMAC-SHA512 of a string with a key
     * @param key The secret key
     * @param data The data to authenticate
     * @returns Hexadecimal HMAC-SHA512
     */
    function hmacSHA512(key: string, data: string): string;

}

/**
 * Module for creating and managing system-wide hotkeys
 */
declare namespace hs.hotkey {
    /**
     * Bind a hotkey
     * @param mods An array of modifier key strings (e.g., ["cmd", "shift"])
     * @param key The key name or character (e.g., "a", "space", "return")
     * @param callbackPressed A JavaScript function to call when the hotkey is pressed
     * @param callbackReleased A JavaScript function to call when the hotkey is released
     * @returns A hotkey object, or nil if binding failed
     */
    function bind(mods: JSValue, key: string, callbackPressed: JSValue, callbackReleased: JSValue): HSHotkey | undefined;

    /**
     * Bind a hotkey with a message description
     * @param mods An array of modifier key strings
     * @param key The key name or character
     * @param message A description of what this hotkey does (currently unused, for future features)
     * @param callbackPressed A JavaScript function to call when the hotkey is pressed
     * @param callbackReleased A JavaScript function to call when the hotkey is released
     * @returns A hotkey object, or nil if binding failed
     */
    function bindSpec(mods: JSValue, key: string, message: string | undefined, callbackPressed: JSValue, callbackReleased: JSValue): HSHotkey | undefined;

    /**
     * Get the system-wide mapping of key names to key codes
     * @returns A dictionary mapping key names to numeric key codes
     */
    function getKeyCodeMap(): Record<string, number>;

    /**
     * Get the mapping of modifier names to modifier flags
     * @returns A dictionary mapping modifier names to their numeric values
     */
    function getModifierMap(): Record<string, number>;

}

/**
 * Object representing a system-wide hotkey. You should not create these objects directly, but rather, use the methods in hs.hotkey to instantiate these.
 */
declare class HSHotkey {
    /**
     * Enable the hotkey
     * @returns True if the hotkey was enabled, otherwise False
     */
    static enable(): boolean;

    /**
     * Disable the hotkey
     */
    static disable(): void;

    /**
     * Check if the hotkey is currently enabled
     * @returns True if the hotkey is enabled, otherwise False
     */
    static isEnabled(): boolean;

    /**
     * Delete the hotkey (disables and clears callbacks)
     */
    static delete(): void;

}

/**
 * Module for checking and requesting system permissions
 */
declare namespace hs.permissions {
    /**
     * Check if the app has Accessibility permission
     * @returns true if permission is granted, false otherwise
     */
    function checkAccessibility(): boolean;

    /**
     * Request Accessibility permission (shows system dialog if not granted)
     */
    function requestAccessibility(): void;

    /**
     * Check if the app has Screen Recording permission
     * @returns true if permission is granted, false otherwise
     */
    function checkScreenRecording(): boolean;

    /**
     * Request Screen Recording permission
     */
    function requestScreenRecording(): void;

    /**
     * Check if the app has Camera permission
     * @returns true if permission is granted, false otherwise
     */
    function checkCamera(): boolean;

    /**
     * Request Camera permission (shows system dialog if not granted)
     * @returns A Promise that resolves to true if granted, false if denied
     */
    function requestCamera(): Promise<boolean>;

    /**
     * Check if the app has Microphone permission
     * @returns true if permission is granted, false otherwise
     */
    function checkMicrophone(): boolean;

    /**
     * Request Microphone permission (shows system dialog if not granted)
     * @returns A Promise that resolves to true if granted, false if denied
     */
    function requestMicrophone(): Promise<boolean>;

}

/**
 * Module for creating and managing timers
 */
declare namespace hs.timer {
    /**
     * Create a new timer
     * @param interval The interval in seconds at which the timer should fire
     * @param callback A JavaScript function to call when the timer fires
     * @param continueOnError If true, the timer will continue running even if the callback throws an error
     * @returns A timer object. Call start() to begin the timer.
     */
    function create(interval: number, callback: JSValue, continueOnError: boolean): HSTimer;

    /**
     * Create and start a one-shot timer
     * @param seconds Number of seconds to wait before firing
     * @param callback A JavaScript function to call when the timer fires
     * @returns A timer object (already started)
     */
    function doAfter(seconds: number, callback: JSValue): HSTimer;

    /**
     * Create and start a repeating timer
     * @param interval The interval in seconds at which the timer should fire
     * @param callback A JavaScript function to call when the timer fires
     * @returns A timer object (already started)
     */
    function doEvery(interval: number, callback: JSValue): HSTimer;

    /**
     * Create and start a timer that fires at a specific time
     * @param time Seconds since midnight (local time) when the timer should first fire
     * @param repeatInterval If provided, the timer will repeat at this interval. Pass 0 for one-shot.
     * @param callback A JavaScript function to call when the timer fires
     * @param continueOnError If true, the timer will continue running even if the callback throws an error
     * @returns A timer object (already started)
     */
    function doAt(time: number, repeatInterval: number, callback: JSValue, continueOnError: boolean): HSTimer;

    /**
     * Block execution for a specified number of microseconds (strongly discouraged)
     * @param microseconds Number of microseconds to sleep
     */
    function usleep(microseconds: number): void;

    /**
     * Get the current time as seconds since the UNIX epoch with sub-second precision
     * @returns Fractional seconds since midnight, January 1, 1970 UTC
     */
    function secondsSinceEpoch(): number;

    /**
     * Get the number of nanoseconds since the system was booted (excluding sleep time)
     * @returns Nanoseconds since boot
     */
    function absoluteTime(): UInt64;

    /**
     * Get the number of seconds since local midnight
     * @returns Seconds since midnight in the local timezone
     */
    function localTime(): number;

    /**
     * Converts minutes to seconds Parameter n: A number of minutes
     * @param n A number of minutes
     * @returns The equivalent number of seconds
     */
    function minutes(n: any): any;

    /**
     * Converts hours to seconds Parameter n: A number of hours
     * @param n A number of hours
     * @returns The equivalent number of seconds
     */
    function hours(n: any): any;

    /**
     * Converts days to seconds Parameter n: A number of days
     * @param n A number of days
     * @returns The equivalent number of seconds
     */
    function days(n: any): any;

    /**
     * Converts weeks to seconds Parameter n: A number of weeks
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
    /**
     * Start the timer
     */
    static start(): void;

    /**
     * Stop the timer
     */
    static stop(): void;

    /**
     * Immediately fire the timer's callback
     */
    static fire(): void;

    /**
     * Check if the timer is currently running
     * @returns true if the timer is running, false otherwise
     */
    static running(): boolean;

    /**
     * Get the number of seconds until the timer next fires
     * @returns Seconds until next trigger, or a negative value if the timer is not running
     */
    static nextTrigger(): number;

    /**
     * Set when the timer should next fire
     * @param seconds Number of seconds from now when the timer should fire
     */
    static setNextTrigger(seconds: number): void;

    /**
     * The timer's interval in seconds
     */
    interval: number;

    /**
     * Whether the timer repeats
     */
    repeats: boolean;

}

/**
 * Module for interacting with windows
 */
declare namespace hs.window {
    /**
     * Get the currently focused window
     * @returns The focused window, or nil if none
     */
    function focusedWindow(): HSWindow | undefined;

    /**
     * Get all windows from all applications
     * @returns An array of all windows
     */
    function allWindows(): HSWindow[];

    /**
     * Get all visible (not minimized) windows
     * @returns An array of visible windows
     */
    function visibleWindows(): HSWindow[];

    /**
     * Get windows for a specific application
     * @param app An HSApplication object
     * @returns An array of windows for that application
     */
    function windowsForApp(app: HSApplication): HSWindow[];

    /**
     * Get all windows on a specific screen
     * @param screenIndex The screen index (0 for main screen)
     * @returns An array of windows on that screen
     */
    function windowsOnScreen(screenIndex: number): HSWindow[];

    /**
     * Get the window at a specific screen position
     * @param point An HSPoint containing the coordinates
     * @returns The topmost window at that position, or nil if none
     */
    function windowAtPoint(point: HSPoint): HSWindow | undefined;

    /**
     * Get ordered windows (front to back)
     * @returns An array of windows in z-order
     */
    function orderedWindows(): HSWindow[];

    /**
     * Find windows by title Parameter title: The window title to search for. All windows with titles that include this string, will be matched
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
     * Move a window to left half of screen Parameter win: An HSWindow object
     * @param win An HSWindow object
     * @returns True if the operation was successful, otherwise False
     */
    function moveToLeftHalf(win: any): any;

    /**
     * Move a window to right half of screen Parameter win: An HSWindow object
     * @param win An HSWindow object
     * @returns True if the operation was successful, otherwise False
     */
    function moveToRightHalf(win: any): any;

    /**
     * Maximize a window Parameter win: An HSWindow object
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
    /**
     * Focus this window
     * @returns true if successful
     */
    static focus(): boolean;

    /**
     * Minimize this window
     * @returns true if successful
     */
    static minimize(): boolean;

    /**
     * Unminimize this window
     * @returns true if successful
     */
    static unminimize(): boolean;

    /**
     * Raise this window to the front
     * @returns true if successful
     */
    static raise(): boolean;

    /**
     * Toggle fullscreen mode
     * @returns true if successful
     */
    static toggleFullscreen(): boolean;

    /**
     * Close this window
     * @returns true if successful
     */
    static close(): boolean;

    /**
     * Center the window on the screen
     */
    static centerOnScreen(): void;

    /**
     * Get the underlying AXElement
     * @returns The accessibility element for this window
     */
    static axElement(): HSAXElement;

    /**
     * The window's title
     */
    title: string | undefined;

    /**
     * The application that owns this window
     */
    application: HSApplication | undefined;

    /**
     * The process ID of the application that owns this window
     */
    pid: number;

    /**
     * Whether the window is minimized
     */
    isMinimized: boolean;

    /**
     * Whether the window is visible (not minimized or hidden)
     */
    isVisible: boolean;

    /**
     * Whether the window is focused
     */
    isFocused: boolean;

    /**
     * Whether the window is fullscreen
     */
    isFullscreen: boolean;

    /**
     * Whether the window is standard (has a titlebar)
     */
    isStandard: boolean;

    /**
     * The window's position on screen {x: Int, y: Int}
     */
    position: HSPoint | undefined;

    /**
     * The window's size {w: Int, h: Int}
     */
    size: HSSize | undefined;

    /**
     * The window's frame {x: Int, y: Int, w: Int, h: Int}
     */
    frame: HSRect | undefined;

}

