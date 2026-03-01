// TypeScript definitions for Hammerspoon 2
// Auto-generated from API documentation
// DO NOT EDIT - Regenerate using: npm run docs:typescript

// ========================================
// Global Types
// ========================================

/**
 * Bridge type for working with colors in JavaScript
 */
declare class HSColor {
    /**
     * Create a color from RGB values
     * @param r Red component (0.0-1.0)
     * @param g Green component (0.0-1.0)
     * @param b Blue component (0.0-1.0)
     * @param a Alpha component (0.0-1.0)
     * @returns An HSColor object
     */
    static rgb(r: number, g: number, b: number, a: number): HSColor;

    /**
     * Create a color from a hex string
     * @param hex Hex string (e.g. "#FF0000" or "FF0000")
     * @returns An HSColor object
     */
    static hex(hex: string): HSColor;

    /**
     * Create a color from a named system color
     * @param name Name of the system color (e.g. "red", "blue", "systemBlue")
     * @returns An HSColor object
     */
    static named(name: string): HSColor;

    /**
     * Update this color's value
     * @param value New color as a hex string (e.g. "#FF0000") or another HSColor object
     */
    static set(value: JSValue): void;

}

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
 * Bridge type for working with images in JavaScript
HSImage provides a comprehensive API for loading, manipulating, and saving images.
It supports various image sources including files, system icons, app bundles, and URLs.
## Loading Images
```javascript
// Load from file
const img = HSImage.fromPath("/path/to/image.png")

// Load system image
const icon = HSImage.fromName("NSComputer")

// Load app icon
const appIcon = HSImage.fromAppBundle("com.apple.Safari")

// Load from URL (asynchronous with Promise)
HSImage.fromURL("https://example.com/image.png")
    .then(image => console.log("Image loaded:", image.size()))
    .catch(err => console.error("Failed to load image:", err))

// Or with async/await
const image = await HSImage.fromURL("https://example.com/image.png")
```
## Image Manipulation
```javascript
const img = HSImage.fromPath("/path/to/image.png")

// Get size
const size = img.size()  // Returns HSSize

// Resize image
const resized = img.setSize({w: 100, h: 100}, false)  // Proportional

// Crop image
const cropped = img.croppedCopy({x: 10, y: 10, w: 50, h: 50})

// Save to file
img.saveToFile("/path/to/output.png")
```
 */
declare class HSImage {
    /**
     * Load an image from a file path
     * @param path Path to the image file
     * @returns An HSImage object, or null if the file couldn't be loaded
     */
    static fromPath(path: string): HSImage | undefined;

    /**
     * Load a system image by name
     * @param name Name of the system image (e.g., "NSComputer", "NSFolder")
     * @returns An HSImage object, or null if the image couldn't be found
     */
    static fromName(name: string): HSImage | undefined;

    /**
     * Load an app's icon by bundle identifier
     * @param bundleID Bundle identifier of the application
     * @returns An HSImage object, or null if the app couldn't be found
     */
    static fromAppBundle(bundleID: string): HSImage | undefined;

    /**
     * Get the icon for a file
     * @param path Path to the file
     * @returns An HSImage object representing the file's icon
     */
    static iconForFile(path: string): HSImage | undefined;

    /**
     * Get the icon for a file type
     * @param fileType File extension or UTI (e.g., "png", "public.png")
     * @returns An HSImage object representing the file type's icon
     */
    static iconForFileType(fileType: string): HSImage | undefined;

    /**
     * Load an image from a URL (asynchronous)
     * @param url URL string of the image
     * @returns A Promise that resolves to the loaded image, or rejects on error
     */
    static fromURL(url: string): Promise<HSImage>;

    /**
     * Get or set the image size
     * @param size Optional HSSize to set (if provided, returns a resized copy)
     * @returns The current size as HSSize, or a resized copy if size was provided
     */
    static size(size: JSValue): JSValue;

    /**
     * Get or set the image name
     * @param name Optional name to set
     * @returns The current or new name
     */
    static name(name: JSValue): string | undefined;

    /**
     * Create a resized copy of the image
     * @param size Target size as HSSize
     * @param absolute If true, resize exactly to specified dimensions. If false, maintain aspect ratio
     * @returns A new resized HSImage
     */
    static setSize(size: JSValue, absolute: boolean): HSImage | undefined;

    /**
     * Create a copy of the image
     * @returns A new HSImage copy
     */
    static copyImage(): HSImage | undefined;

    /**
     * Create a cropped copy of the image
     * @param rect HSRect defining the crop area
     * @returns A new cropped HSImage, or null if cropping failed
     */
    static croppedCopy(rect: JSValue): HSImage | undefined;

    /**
     * Save the image to a file
     * @param path Destination file path (extension determines format: png, jpg, tiff, bmp, gif)
     * @returns true if saved successfully, false otherwise
     */
    static saveToFile(path: string): boolean;

    /**
     * Get or set the template image flag
     * @param state Optional boolean to set template state
     * @returns Current template state
     */
    static template(state: JSValue): boolean;

    /**
     * Replace the image with a new one, triggering a re-render if bound to a UI element
     * @param value New image as an HSImage object or a file path string
     */
    static set(value: JSValue): void;

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

/**
 * A reactive string container. Pass to `.text()` to get automatic
re-renders when `.set()` is called from JavaScript.
 */
declare class HSString {
    /**
     * Update the string value, triggering a re-render if bound to a UI element
     * @param newValue The new string
     */
    static set(newValue: string): void;

    /**
     * The current string value
     */
    value: string;

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
    function addWatcher(event: string, listener: JSValue): void;

    /**
     * Remove a watcher for application events
     * @param event The event type to stop listening for
     * @param listener The javascript function/lambda that was previously being used to handle the event
     */
    function removeWatcher(event: string, listener: JSValue): void;

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
    function addWatcher(application: HSApplication, notification: string, listener: JSValue): void;

    /**
     * Remove a watcher for application AX events
     * @param application An HSApplication object
     * @param notification The event name to stop watching
     * @param listener The function/lambda provided when adding the watcher
     */
    function removeWatcher(application: HSApplication, notification: string, listener: JSValue): void;

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

    /**
     * Fetch the focused UI element. Swift-retained storage for the JS implementation.
     */
    const focusedElement: JSValue | undefined;

    /**
     * Find AX elements by role. Swift-retained storage for the JS implementation.
     */
    const findByRole: JSValue | undefined;

    /**
     * Find AX elements by title. Swift-retained storage for the JS implementation.
     */
    const findByTitle: JSValue | undefined;

    /**
     * Print the element hierarchy. Swift-retained storage for the JS implementation.
     */
    const printHierarchy: JSValue | undefined;

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

    /**
     * The callback function to be called when the hotkey is pressed
     */
    callbackPressed: JSValue | undefined;

    /**
     * The callback function to be called when the hotkey is released
     */
    callbackReleased: JSValue | undefined;

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
 * Module for running external processes
 */
declare namespace hs.task {
    /**
     * Create a new task
     * @param launchPath The full path to the executable to run
     * @param arguments An array of arguments to pass to the executable
     * @param completionCallback Optional callback function called when the task terminates
     * @param environment Optional dictionary of environment variables for the task
     * @param streamingCallback Optional callback function called when the task produces output
     * @returns A task object. Call start() to begin execution.
     */
    function new(launchPath: string, arguments: string[], completionCallback: JSValue | undefined, environment: JSValue | undefined, streamingCallback: JSValue | undefined): HSTask;

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
    function runAsync(launchPath: string, args: string[], options: Object|Function, options: Object, options: string, options: Function, legacyStreamCallback: Function): any;

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

    /**
     * Run a task, returning a Promise. Swift-retained storage for the JS implementation.
     */
    const runAsync: JSValue | undefined;

    /**
     * Run a shell command. Swift-retained storage for the JS implementation.
     */
    const shell: JSValue | undefined;

    /**
     * Run multiple tasks in parallel. Swift-retained storage for the JS implementation.
     */
    const parallel: JSValue | undefined;

    /**
     * Run multiple tasks in sequence. Swift-retained storage for the JS implementation.
     */
    const sequence: JSValue | undefined;

    /**
     * Create a task builder. Swift-retained storage for the JS implementation.
     */
    const builder: JSValue | undefined;

    /**
     * TaskBuilder class. Swift-retained storage for the JS implementation.
     */
    const TaskBuilder: JSValue | undefined;

}

/**
 * Object representing an external process task
 */
declare class HSTask {
    /**
     * Start the task
     * @returns The task object for chaining
     */
    static start(): HSTask;

    /**
     * Terminate the task (send SIGTERM)
     */
    static terminate(): void;

    /**
     * Terminate the task with extreme prejudice (send SIGKILL)
     */
    static kill9(): void;

    /**
     * Interrupt the task (send SIGINT)
     */
    static interrupt(): void;

    /**
     * Pause the task (send SIGSTOP)
     */
    static pause(): void;

    /**
     * Resume the task (send SIGCONT)
     */
    static resume(): void;

    /**
     * Wait for the task to complete (blocking)
     */
    static waitUntilExit(): void;

    /**
     * Write data to the task's stdin
     * @param data The string data to write
     */
    static sendInput(data: string): void;

    /**
     * Close the task's stdin
     */
    static closeInput(): void;

    /**
     * Check if the task is currently running
     */
    isRunning: boolean;

    /**
     * The process ID of the running task
     */
    pid: Int32;

    /**
     * The environment variables for the task
     */
    environment: Record<string, string>;

    /**
     * The working directory for the task
     */
    workingDirectory: string | undefined;

    /**
     * The termination status of the task
     */
    terminationStatus: NSNumber | undefined;

    /**
     * The termination reason
     */
    terminationReason: string | undefined;

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
     * Create a new timer (alias for create())
     * @param interval The interval in seconds at which the timer should fire
     * @param callback A JavaScript function to call when the timer fires
     * @param continueOnError If true, the timer will continue running even if the callback throws an error
     * @returns A timer object. Call start() to begin the timer.
     */
    function new(interval: number, callback: JSValue, continueOnError: boolean): HSTimer;

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
     * Converts minutes to seconds
     * @param n A number of minutes
     * @returns The equivalent number of seconds
     */
    function minutes(n: number): number;

    /**
     * Converts hours to seconds
     * @param n A number of hours
     * @returns The equivalent number of seconds
     */
    function hours(n: number): number;

    /**
     * Converts days to seconds
     * @param n A number of days
     * @returns The equivalent number of seconds
     */
    function days(n: number): number;

    /**
     * Converts weeks to seconds
     * @param n A number of weeks
     * @returns The equivalent number of seconds
     */
    function weeks(n: number): number;

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
     * Repeat a function until a predicate returns true. Swift-retained storage for the JS implementation.
     */
    const doUntil: JSValue | undefined;

    /**
     * Repeat a function while a predicate returns true. Swift-retained storage for the JS implementation.
     */
    const doWhile: JSValue | undefined;

    /**
     * Wait to call a function until a predicate returns true. Swift-retained storage for the JS implementation.
     */
    const waitUntil: JSValue | undefined;

    /**
     * Wait to call a function until a predicate returns false. Swift-retained storage for the JS implementation.
     */
    const waitWhile: JSValue | undefined;

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
 * # hs.ui
**Create custom user interfaces, alerts, dialogs, and file pickers**
The `hs.ui` module provides a set of tools for creating custom user interfaces
in Hammerspoon with SwiftUI-like declarative syntax.
## Key Features
then call `.set()` on it from any callback to re-render the canvas automatically
then call `.set()` on it to update the displayed content live
to swap the image without rebuilding the window
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
### Reactive Color on Hover
```javascript
// Create a mutable color, then mutate it inside the hover callback
const btnColor = HSColor.hex("#4A90E2");

hs.ui.window({x: 100, y: 100, w: 160, h: 60})
    .rectangle()
        .fill(btnColor)
        .cornerRadius(8)
        .frame({w: "100%", h: "100%"})
        .onHover((isHovered) => {
            btnColor.set(isHovered ? "#E24A4A" : "#4A90E2");
        })
    .show();
```
### Reactive Text on Hover
```javascript
// Create a mutable string, then mutate it inside the hover callback
const label = hs.ui.string("Move your mouse here");

hs.ui.window({x: 100, y: 200, w: 220, h: 50})
    .text(label)
        .font(HSFont.body())
        .foregroundColor("#FFFFFF")
        .onHover((isHovered) => {
            label.set(isHovered ? "You're hovering!" : "Move your mouse here");
        })
    .show();
```
### Reactive Image on Click
```javascript
// Toggle between two system icons on each click
const icon = HSImage.fromName("NSStatusAvailable");

hs.ui.window({x: 100, y: 300, w: 80, h: 80})
    .image(icon)
        .resizable()
        .aspectRatio("fit")
        .frame({w: 64, h: 64})
        .onClick(() => {
            const next = (icon.name() === "NSStatusAvailable")
                ? HSImage.fromName("NSStatusUnavailable")
                : HSImage.fromName("NSStatusAvailable");
            icon.set(next);
        })
    .show();
```
## Complete Example: Status Dashboard
Here's a more complex example showing how to build an interactive status dashboard
```javascript
// Create a status dashboard window
const statusWindow = hs.ui.window({x: 100, y: 100, w: 400, h: 500})
    .vstack()
        .spacing(15)
        .padding(20)

        // Header
        .text("System Status Dashboard")
            .font(HSFont.largeTitle())
            .foregroundColor("#FFFFFF")

        // Status cards
        .hstack()
            .spacing(10)
            .vstack()
                .spacing(5)
                .rectangle()
                    .fill("#4CAF50")
                    .cornerRadius(8)
                    .frame({w: 180, h: 100})
                .text("CPU: 45%")
                    .font(HSFont.headline())
                    .foregroundColor("#FFFFFF")
            .end()
            .vstack()
                .spacing(5)
                .rectangle()
                    .fill("#2196F3")
                    .cornerRadius(8)
                    .frame({w: 180, h: 100})
                .text("Memory: 8.2GB")
                    .font(HSFont.headline())
                    .foregroundColor("#FFFFFF")
            .end()
        .end()

        // Activity indicator with image
        .hstack()
            .spacing(10)
            .image(HSImage.fromName("NSComputer"))
                .resizable()
                .aspectRatio("fit")
                .frame({w: 64, h: 64})
            .vstack()
                .text("System Running")
                    .font(HSFont.title())
                .text("All services operational")
                    .font(HSFont.caption())
                    .foregroundColor("#A0A0A0")
            .end()
        .end()

        // Circle status indicators
        .hstack()
            .spacing(20)
            .circle()
                .fill("#4CAF50")
                .frame({w: 30, h: 30})
            .circle()
                .fill("#FFC107")
                .frame({w: 30, h: 30})
            .circle()
                .fill("#F44336")
                .frame({w: 30, h: 30})
        .end()
    .end()
    .backgroundColor("#2C3E50");

// Show the dashboard
statusWindow.show();

// Later, interact with dialogs
hs.ui.dialog("Shutdown system?")
    .informativeText("This will close all applications.")
    .buttons(["Shutdown", "Cancel"])
    .onButton((index) => {
        if (index === 0) {
            hs.ui.alert("Shutting down...")
                .duration(3)
                .show();
        }
    })
    .show();
```
## Complete Example: Reactive Hover Card
Demonstrates reactive colors and reactive text together — a single `.onHover()`
```javascript
const cardColor = HSColor.hex("#3498DB");
const cardLabel = hs.ui.string("Hover the card");

hs.ui.window({x: 100, y: 100, w: 220, h: 120})
    .vstack()
        .spacing(12)
        .padding(16)
        .rectangle()
            .fill(cardColor)
            .cornerRadius(10)
            .frame({w: "100%", h: 60})
            .onHover((isHovered) => {
                cardColor.set(isHovered ? "#E74C3C" : "#3498DB");
                cardLabel.set(isHovered ? "You found it!" : "Hover the card");
            })
        .text(cardLabel)
            .font(HSFont.headline())
            .foregroundColor("#FFFFFF")
    .end()
    .backgroundColor("#1A252F")
    .show();
```
 */
declare namespace hs.ui {
    /**
     * Create a custom UI window
Creates a borderless window that can contain custom UI elements built using a declarative,
SwiftUI-like syntax with shapes, text, and layout containers.
     * @param dict Dictionary with keys: `x`, `y`, `w`, `h` (all numbers)
     * @returns An `HSUIWindow` object for chaining
     */
    function window(dict: Record<string, any>): HSUIWindow;

    /**
     * Create a temporary on-screen alert
Displays a temporary notification that automatically dismisses after the specified duration.
Similar to the old `hs.alert` module but with more features.
     * @param message The message text to display
     * @returns An `HSUIAlert` object for chaining
     */
    function alert(message: string): HSUIAlert;

    /**
     * Create a modal dialog with buttons
Shows a blocking dialog with customizable message, informative text, and buttons.
Use the callback to handle button presses.
     * @param message The main message text
     * @returns An `HSUIDialog` object for chaining
     */
    function dialog(message: string): HSUIDialog;

    /**
     * Create a text input prompt
Shows a modal dialog with a text input field. The callback receives the button index
and the entered text.
     * @param message The prompt message
     * @returns An `HSUITextPrompt` object for chaining
     */
    function textPrompt(message: string): HSUITextPrompt;

    /**
     * Create a reactive string for binding text element content to a dynamic value
An `HSString` is a reactive value container. When passed to `.text()`,
the canvas automatically re-renders whenever `.set()` is called from JavaScript.
     * @param initialValue The starting string value
     * @returns An `HSString` object whose value can be updated with `.set()`
     */
    function string(initialValue: string): HSString;

    /**
     * Create a file or directory picker
Shows a standard macOS file picker dialog. Can be configured to select files,
directories, or both, with support for file type filtering and multiple selection.
     * @returns An `HSUIFilePicker` object for chaining
     */
    function filePicker(): HSUIFilePicker;

}

/**
 * # HSUIWindow
**A custom window with declarative UI building**
`HSUIWindow` allows you to create custom borderless windows with a SwiftUI-like
declarative syntax. Build interfaces using shapes, text, images, and layout containers.
## Building UI Elements
## Modifying Elements
## Examples
**Simple window with text and shapes:**
```javascript
hs.ui.window({x: 100, y: 100, w: 300, h: 200})
    .vstack()
        .spacing(10)
        .padding(20)
        .text("Dashboard")
            .font(HSFont.largeTitle())
            .foregroundColor("#FFFFFF")
        .rectangle()
            .fill("#4A90E2")
            .cornerRadius(10)
            .frame({w: "90%", h: 80})
    .end()
    .backgroundColor("#2C3E50")
    .show();
```
**Window with image:**
```javascript
const img = HSImage.fromPath("~/Pictures/photo.jpg")
hs.ui.window({x: 100, y: 100, w: 400, h: 300})
    .vstack()
        .padding(20)
        .image(img)
            .resizable()
            .aspectRatio("fit")
            .frame({w: 360, h: 240})
    .end()
    .show();
```
 */
declare class HSUIWindow {
    /**
     * Show the window
     * @returns Self for chaining
     */
    static show(): HSUIWindow;

    /**
     * Hide the window (keeps it in memory)
     */
    static hide(): void;

    /**
     * Close and destroy the window
     */
    static close(): void;

    /**
     * Set the window's background color
     * @param colorValue Color as hex string (e.g., "#FF0000") or HSColor object
     * @returns Self for chaining
     */
    static backgroundColor(colorValue: JSValue): HSUIWindow;

    /**
     * Add a rectangle shape
     * @returns Self for chaining (apply modifiers like `fill()`, `frame()`)
     */
    static rectangle(): HSUIWindow;

    /**
     * Add a circle shape
     * @returns Self for chaining (apply modifiers like `fill()`, `frame()`)
     */
    static circle(): HSUIWindow;

    /**
     * Add a text element
or an `HSString` object (from `hs.ui.string()`) for reactive text
     * @param content The text to display — a plain JS string for static text,
     * @returns Self for chaining (apply modifiers like `font()`, `foregroundColor()`)
     */
    static text(content: JSValue): HSUIWindow;

    /**
     * Add an image element
     * @param imageValue Image as HSImage object or file path string
     * @returns Self for chaining (apply modifiers like `resizable()`, `aspectRatio()`, `frame()`)
     */
    static image(imageValue: JSValue): HSUIWindow;

    /**
     * Add a button element
or an `HSString` object (from `hs.ui.string()`) for reactive text
     * @param label The button label — a plain JS string for static text,
     * @returns Self for chaining (apply `.fill()`, `.cornerRadius()`, `.font()`,
     */
    static button(label: JSValue): HSUIWindow;

    /**
     * Begin a vertical stack (elements arranged top to bottom)
     * @returns Self for chaining (call `end()` when done)
     */
    static vstack(): HSUIWindow;

    /**
     * Begin a horizontal stack (elements arranged left to right)
     * @returns Self for chaining (call `end()` when done)
     */
    static hstack(): HSUIWindow;

    /**
     * Begin a z-stack (overlapping elements)
     * @returns Self for chaining (call `end()` when done)
     */
    static zstack(): HSUIWindow;

    /**
     * Add flexible spacing that expands to fill available space
     * @returns Self for chaining
     */
    static spacer(): HSUIWindow;

    /**
     * End the current layout container
     * @returns Self for chaining
     */
    static end(): HSUIWindow;

    /**
     * Fill a shape with a color
     * @param colorValue Color as hex string or HSColor
     * @returns Self for chaining
     */
    static fill(colorValue: JSValue): HSUIWindow;

    /**
     * Add a stroke (border) to a shape
     * @param colorValue Color as hex string or HSColor
     * @returns Self for chaining
     */
    static stroke(colorValue: JSValue): HSUIWindow;

    /**
     * Set the stroke width
     * @param width Width in points
     * @returns Self for chaining
     */
    static strokeWidth(width: number): HSUIWindow;

    /**
     * Round the corners of a shape
     * @param radius Corner radius in points
     * @returns Self for chaining
     */
    static cornerRadius(radius: number): HSUIWindow;

    /**
     * Set the frame (size) of an element
     * @param dict Dictionary with `w` and/or `h` (can be numbers or percentage strings like "50%")
     * @returns Self for chaining
     */
    static frame(dict: Record<string, any>): HSUIWindow;

    /**
     * Set the opacity of an element
     * @param value Opacity from 0.0 (transparent) to 1.0 (opaque)
     * @returns Self for chaining
     */
    static opacity(value: number): HSUIWindow;

    /**
     * Set the font for a text element
     * @param font An HSFont object (e.g., `HSFont.title()`)
     * @returns Self for chaining
     */
    static font(font: HSFont): HSUIWindow;

    /**
     * Set the text color
     * @param colorValue Color as hex string or HSColor
     * @returns Self for chaining
     */
    static foregroundColor(colorValue: JSValue): HSUIWindow;

    /**
     * Make an image resizable (allows it to scale with frame size)
     * @returns Self for chaining
     */
    static resizable(): HSUIWindow;

    /**
     * Set the aspect ratio mode for an image
     * @param mode "fit" (scales to fit within frame) or "fill" (scales to fill frame)
     * @returns Self for chaining
     */
    static aspectRatio(mode: string): HSUIWindow;

    /**
     * Add padding around a layout container
     * @param value Padding in points
     * @returns Self for chaining
     */
    static padding(value: number): HSUIWindow;

    /**
     * Set spacing between elements in a stack
     * @param value Spacing in points
     * @returns Self for chaining
     */
    static spacing(value: number): HSUIWindow;

    /**
     * Set a callback to fire when the element is clicked
     * @param callback A JavaScript function to call on click
     * @returns Self for chaining
     */
    static onClick(callback: JSValue): HSUIWindow;

    /**
     * Set a callback to fire when the cursor enters or leaves the element
     * @param callback A JavaScript function called with a boolean: true when entering, false when leaving
     * @returns Self for chaining
     */
    static onHover(callback: JSValue): HSUIWindow;

}

/**
 * # HSUIAlert
**A temporary on-screen notification**
Displays a message that automatically fades out after a specified duration.
Positioned in the center of the screen with a semi-transparent background.
## Example
```javascript
hs.ui.alert("Task completed!")
    .font(HSFont.headline())
    .duration(5)
    .padding(30)
    .show();
```
 */
declare class HSUIAlert {
    /**
     * Set the font for the alert text
     * @param font An HSFont object (e.g., `HSFont.headline()`)
     * @returns Self for chaining
     */
    static font(font: HSFont): HSUIAlert;

    /**
     * Set how long the alert is displayed
     * @param seconds Duration in seconds (default: 5.0)
     * @returns Self for chaining
     */
    static duration(seconds: number): HSUIAlert;

    /**
     * Set the padding around the alert text
     * @param points Padding in points (default: 20)
     * @returns Self for chaining
     */
    static padding(points: number): HSUIAlert;

    /**
     * Set a custom position for the alert
     * @param dict Dictionary with `x` and `y` coordinates
     * @returns Self for chaining
     */
    static position(dict: Record<string, any>): HSUIAlert;

    /**
     * Show the alert
     * @returns Self for chaining (can store reference to close manually)
     */
    static show(): HSUIAlert;

    /**
     * Close the alert immediately
     */
    static close(): void;

}

/**
 * # HSUIDialog
**A modal dialog with customizable buttons**
Shows a blocking dialog with a message, optional informative text, and custom buttons.
Use the callback to respond to button presses.
## Example
```javascript
hs.ui.dialog("Save changes?")
    .informativeText("Your document has unsaved changes.")
    .buttons(["Save", "Don't Save", "Cancel"])
    .onButton((index) => {
        if (index === 0) {
            print("Saving...");
        } else if (index === 1) {
            print("Discarding changes...");
        }
    })
    .show();
```
 */
declare class HSUIDialog {
    /**
     * Set additional informative text below the main message
     * @param text The informative text
     * @returns Self for chaining
     */
    static informativeText(text: string): HSUIDialog;

    /**
     * Set custom button labels
     * @param labels Array of button labels (default: ["OK"])
     * @returns Self for chaining
     */
    static buttons(labels: string[]): HSUIDialog;

    /**
     * Set the dialog style
     * @param style Style name (e.g., "informational", "warning", "critical")
     * @returns Self for chaining
     */
    static style(style: string): HSUIDialog;

    /**
     * Set the callback for button presses
     * @param callback Function receiving button index (0-based)
     * @returns Self for chaining
     */
    static onButton(callback: JSValue): HSUIDialog;

    /**
     * Show the dialog
     * @returns Self for chaining
     */
    static show(): HSUIDialog;

    /**
     * Close the dialog programmatically
     */
    static close(): void;

}

/**
 * # HSUIFilePicker
**A file or directory selection dialog**
Shows a standard macOS open panel for selecting files or directories. Supports
multiple selection, file type filtering, and more.
## Examples
### File Picker
```javascript
hs.ui.filePicker()
    .message("Choose a file to open")
    .allowedFileTypes(["txt", "md", "js"])
    .onSelection((path) => {
        if (path) {
            print("Selected: " + path);
        } else {
            print("User cancelled");
        }
    })
    .show();
```
### Directory Picker with Multiple Selection
```javascript
hs.ui.filePicker()
    .message("Choose directories to backup")
    .canChooseFiles(false)
    .canChooseDirectories(true)
    .allowsMultipleSelection(true)
    .onSelection((paths) => {
        if (paths) {
            paths.forEach(p => print("Dir: " + p));
        }
    })
    .show();
```
 */
declare class HSUIFilePicker {
    /**
     * Set the message displayed in the picker
     * @param text The message text
     * @returns Self for chaining
     */
    static message(text: string): HSUIFilePicker;

    /**
     * Set the starting directory
     * @param path Path to directory (supports `~` for home)
     * @returns Self for chaining
     */
    static defaultPath(path: string): HSUIFilePicker;

    /**
     * Set whether files can be selected
     * @param value true to allow file selection (default: true)
     * @returns Self for chaining
     */
    static canChooseFiles(value: boolean): HSUIFilePicker;

    /**
     * Set whether directories can be selected
     * @param value true to allow directory selection (default: false)
     * @returns Self for chaining
     */
    static canChooseDirectories(value: boolean): HSUIFilePicker;

    /**
     * Set whether multiple items can be selected
     * @param value true to allow multiple selection (default: false)
     * @returns Self for chaining
     */
    static allowsMultipleSelection(value: boolean): HSUIFilePicker;

    /**
     * Restrict to specific file types
     * @param types Array of file extensions (e.g., ["txt", "md"])
     * @returns Self for chaining
     */
    static allowedFileTypes(types: string[]): HSUIFilePicker;

    /**
     * Set whether to resolve symbolic links
     * @param value true to resolve aliases (default: true)
     * @returns Self for chaining
     */
    static resolvesAliases(value: boolean): HSUIFilePicker;

    /**
     * Set the callback for file selection
     * @param callback Function receiving selected path(s) or null if cancelled
     * @returns Self for chaining
     */
    static onSelection(callback: JSValue): HSUIFilePicker;

    /**
     * Show the file picker dialog
     */
    static show(): void;

}

/**
 * # HSUITextPrompt
**A modal dialog with text input**
Shows a blocking dialog with a text input field. The callback receives both the
button index and the entered text.
## Example
```javascript
hs.ui.textPrompt("Enter your name")
    .informativeText("Please provide your full name")
    .defaultText("John Doe")
    .buttons(["OK", "Cancel"])
    .onButton((buttonIndex, text) => {
        if (buttonIndex === 0) {
            print("User entered: " + text);
        }
    })
    .show();
```
 */
declare class HSUITextPrompt {
    /**
     * Set additional informative text below the main message
     * @param text The informative text
     * @returns Self for chaining
     */
    static informativeText(text: string): HSUITextPrompt;

    /**
     * Set the default text in the input field
     * @param text Default text value
     * @returns Self for chaining
     */
    static defaultText(text: string): HSUITextPrompt;

    /**
     * Set custom button labels
     * @param labels Array of button labels (default: ["OK", "Cancel"])
     * @returns Self for chaining
     */
    static buttons(labels: string[]): HSUITextPrompt;

    /**
     * Set the callback for button presses
     * @param callback Function receiving (buttonIndex, inputText)
     * @returns Self for chaining
     */
    static onButton(callback: JSValue): HSUITextPrompt;

    /**
     * Show the prompt dialog
     */
    static show(): void;

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

