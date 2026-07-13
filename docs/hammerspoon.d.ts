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
     * Update this color's value.
If this color is bound to a UI element, the canvas re-renders automatically.
     * @param value A hex color string (e.g. "#FF0000") or another HSColor object
     */
    set(value: string | HSColor): void;

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
    .then(image => console.log("Image loaded:", image.size))
    .catch(err => console.error("Failed to load image:", err))

// Or with async/await
const image = await HSImage.fromURL("https://example.com/image.png")
```
## Image Manipulation
```javascript
const img = HSImage.fromPath("/path/to/image.png")

// Get size
const size = img.size  // Returns HSSize

// Resize image (mutates in place)
img.size = HSSize(100, 100)

// Crop image
const cropped = img.croppedCopy(HSRect(10, 10, 50, 50))

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
    static fromPath(path: string): HSImage | null;

    /**
     * Load a system image by name
     * @param name Name of the system image (e.g., "NSComputer", "NSFolder")
     * @returns An HSImage object, or null if the image couldn't be found
     */
    static fromName(name: string): HSImage | null;

    /**
     * Load a system symbol by name
     * @param name Name of the symbol (e.g., "hammer", "questionmark.circle")
     * @returns An HSImage object, or null if the symbol couldn't be found
     */
    static fromSymbol(name: string): HSImage | null;

    /**
     * Load an app's icon by bundle identifier
     * @param bundleID Bundle identifier of the application
     * @param withFallbackSymbol The name of an SF Symbol to use if no bundle image could be loaded. Defaults to questionmark.circle
     * @returns An HSImage object, or null if the app couldn't be found
     */
    static fromAppBundle(bundleID: string, withFallbackSymbol?: string): HSImage | null;

    /**
     * Get the icon for a file
     * @param path Path to the file
     * @returns An HSImage object representing the file's icon
     */
    static iconForFile(path: string): HSImage | null;

    /**
     * Get the icon for a file type
     * @param fileType File extension or UTI (e.g., "png", "public.png")
     * @returns An HSImage object representing the file type's icon
     */
    static iconForFileType(fileType: string): HSImage | null;

    /**
     * Load an image from a URL (asynchronous)
     * @param url URL string of the image
     * @returns A Promise that resolves to the loaded image, or rejects on error
     */
    static fromURL(url: string): Promise<HSImage>;

    /**
     * Create a copy of the image
     * @returns A new HSImage copy
     */
    copyImage(): HSImage | null;

    /**
     * Create a cropped copy of the image
     * @param rect HSRect defining the crop area (x, y, w, h)
     * @returns A new cropped HSImage, or null if the rect falls outside the image bounds
     */
    croppedCopy(rect: HSRect): HSImage | null;

    /**
     * Save the image to a file
     * @param path Destination file path (extension determines format: png, jpg, tiff, bmp, gif)
     * @returns true if saved successfully, false otherwise
     */
    saveToFile(path: string): boolean;

    /**
     * Replace this image's content.
If this image is bound to a UI element, the canvas re-renders automatically.
     * @param value A file path string (`~` is expanded) or another HSImage object
     */
    set(value: string | HSImage): void;

    /**
     * The size of the image. Setting this resizes the image in place to the exact dimensions.
     */
    size: HSSize;

    /**
     * The name of the image, or null if not set.
     */
    name: string | null;

    /**
     * Whether the image is a template image.
Template images are tinted by the system to match the appearance context (e.g. menu bar icons).
     */
    template: boolean;

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
    set(newValue: string): void;

    /**
     * The current string value
     */
    readonly value: string;

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
 * Root Hammerspoon namespace
 */
declare namespace hs {
    /**
     * Destroy the current JavaScript runtime and start a new one, loading all configuration from disk again
     */
    function reload(): void;

    /**
     * Force garbage collection of JavaScript objects that no longer have any references
     * @remarks This uses private macOS API
     */
    function collectGarbage(): void;

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

    /**
     * The filesystem path to the main Hammerspoon 2 configuration file
     */
    const configPath: string;

    /**
     * The filesystem path to the directory Hammerspoon 2 loaded its config from
     */
    const configDir: string;

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
    function matchingName(name: string): HSApplication | null;

    /**
     * Fetch the first running application that matches a Bundle ID
     * @param bundleID The identifier to search for
     * @returns The first matching application, or nil if none matched
     */
    function matchingBundleID(bundleID: string): HSApplication | null;

    /**
     * Fetch the running application that matches a POSIX PID
     * @param pid The PID to search for
     * @returns The matching application, or nil if none matched
     */
    function fromPID(pid: number): HSApplication | null;

    /**
     * Fetch the currently focused application
     * @returns The matching application, or nil if none matched
     */
    function frontmost(): HSApplication | null;

    /**
     * Fetch the application which currently owns the menu bar
     * @returns The matching application, or nil if none matched
     */
    function menuBarOwner(): HSApplication | null;

    /**
     * Fetch the filesystem path for an application
     * @param bundleID The application bundle identifier to search for (e.g. "com.apple.Safari")
     * @returns The application's filesystem path, or nil if it was not found
     */
    function pathForBundleID(bundleID: string): string | null;

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
    function pathForFileType(fileType: string): string | null;

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
     * @param listener A javascript function/lambda to call when any application event is received. The function will be called with two parameters: the name of the event, and the associated HSApplication object
     */
    function addWatcher(listener: (event: string, app: HSApplication | null) => void): void;

    /**
     * Remove a watcher for application events
     * @param listener The javascript function/lambda that was previously being used to handle events
     */
    function removeWatcher(listener: (...args: any[]) => any): void;

}

/**
 * Object representing an application. You should not instantiate this directly in JavaScript, but rather, use the methods from hs.application which will return appropriate HSApplication objects.
 */
declare class HSApplication {
    /**
     * Terminate the application
     * @returns True if the application was terminated, otherwise false
     */
    kill(): boolean;

    /**
     * Force-terminate the application
     * @returns True if the application was force-terminated, otherwise false
     */
    kill9(): boolean;

    /**
     * The application's HSAXElement object, for use with the hs.ax APIs
     * @returns An HSAXElement object, or nil if it could not be obtained
     */
    axElement(): HSAXElement | null;

    /**
     * Bring this application to the foreground
     * @param allWindows Pass true to raise all application windows. Defaults to false.
     */
    activate(allWindows?: boolean): void;

    /**
     * Hide this application and all its windows
     */
    hide(): void;

    /**
     * Unhide this application
     */
    unhide(): void;

    /**
     * Get the full menu structure of this application
     * @remarks This traverses the accessibility hierarchy and may be slow for apps with large menus.
     * @returns An array of top-level menu objects, each with title and items keys, or null if unavailable
     */
    getMenuItems(): Record<string, any>[] | null;

    /**
     * Find a menu item by searching all menus for a matching title (case-insensitive)
     * @param name The menu item title to search for
     * @returns An object with title and enabled keys, or null if not found
     */
    findMenuItemByName(name: string): Record<string, any> | null;

    /**
     * Find a menu item by following a hierarchical path of titles
     * @param path An array of menu titles forming a path from the top-level menu to the item, e.g. ["Edit", "Select All"]
     * @returns An object with title and enabled keys, or null if not found
     */
    findMenuItemByPath(path: string[]): Record<string, any> | null;

    /**
     * Click a menu item found by searching all menus for a matching title (case-insensitive)
     * @param name The menu item title to search for
     * @returns true if the menu item was found and clicked, false otherwise
     */
    selectMenuItemByName(name: string): boolean;

    /**
     * Click a menu item found by following a hierarchical path of titles
     * @param path An array of menu titles forming a path from the top-level menu to the item, e.g. ["File", "New Window"]
     * @returns true if the menu item was found and clicked, false otherwise
     */
    selectMenuItemByPath(path: string[]): boolean;

    /**
     * Find windows whose title contains the given string (case-insensitive)
     * @param pattern A string to search for in window titles
     * @returns An array of matching HSWindow objects
     */
    findWindow(pattern: string): HSWindow[];

    /**
     * Get the first window with exactly the given title
     * @param title The exact window title to search for
     * @returns The matching HSWindow, or null if not found
     */
    getWindow(title: string): HSWindow | null;

    /**
     * POSIX Process Identifier
     */
    readonly pid: number;

    /**
     * Bundle Identifier (e.g. com.apple.Safari)
     */
    readonly bundleID: string | null;

    /**
     * The application's title
     */
    readonly title: string | null;

    /**
     * Location of the application on disk
     */
    readonly bundlePath: string | null;

    /**
     * Is the application hidden
     */
    isHidden: boolean;

    /**
     * Is the application focused
     */
    readonly isActive: boolean;

    /**
     * The main window of this application, or nil if there is no main window
     */
    readonly mainWindow: HSWindow | null;

    /**
     * The focused window of this application, or nil if there is no focused window
     */
    readonly focusedWindow: HSWindow | null;

    /**
     * All windows of this application
     */
    readonly allWindows: HSWindow[];

    /**
     * All visible (ie non-hidden) windows of this application
     */
    readonly visibleWindows: HSWindow[];

    /**
     * Whether the application process is still running
     */
    readonly isRunning: boolean;

    /**
     * The kind of application: "standard" (regular dock app), "accessory" (no dock), or "background" (agent)
     */
    readonly kind: string;

}

/**
 * Module for discovering and controlling audio devices.
## Finding devices
```javascript
const all = hs.audiodevice.all();
const out = hs.audiodevice.defaultOutputDevice();
const mic = hs.audiodevice.defaultInputDevice();
```
## Selecting a device
```javascript
const usb = hs.audiodevice.findDeviceByName("USB Audio CODEC");
if (usb) usb.setDefaultOutputDevice();
```
## Watching for system-level changes
```javascript
var fn = function(event) {
    if (event === "dOut") console.log("Default output changed");
    if (event === "dev+") console.log("A device was added");
};
hs.audiodevice.addWatcher(fn);
// later…
hs.audiodevice.removeWatcher(fn);
```
 */
declare namespace hs.audiodevice {
    /**
     * All audio devices attached to the system.
     * @returns An array of HSAudioDevice objects
     */
    function all(): HSAudioDevice[];

    /**
     * All audio devices that have at least one output stream.
     * @returns An array of HSAudioDevice objects
     */
    function allOutputDevices(): HSAudioDevice[];

    /**
     * All audio devices that have at least one input stream.
     * @returns An array of HSAudioDevice objects
     */
    function allInputDevices(): HSAudioDevice[];

    /**
     * The current system default output device.
     * @returns An HSAudioDevice, or null if none is set
     */
    function defaultOutputDevice(): HSAudioDevice | null;

    /**
     * The current system default input device.
     * @returns An HSAudioDevice, or null if none is set
     */
    function defaultInputDevice(): HSAudioDevice | null;

    /**
     * The current system alert sound device.
     * @returns An HSAudioDevice, or null if none is set
     */
    function defaultEffectDevice(): HSAudioDevice | null;

    /**
     * Find the first audio device whose name matches the given string.
     * @param name The device name to search for
     * @returns An HSAudioDevice if found, null otherwise
     */
    function findDeviceByName(name: string): HSAudioDevice | null;

    /**
     * Find the audio device with the given unique identifier.
     * @param uid The device UID to search for
     * @returns An HSAudioDevice if found, null otherwise
     */
    function findDeviceByUID(uid: string): HSAudioDevice | null;

    /**
     * Register a listener for all system-level audio configuration events.
     * @param listener A JavaScript function that receives the event name string
     */
    function addWatcher(listener: (event: string) => void): void;

    /**
     * Remove a previously registered system-level listener.
     * @param listener The JavaScript function that was passed to ``addWatcher(_:)``
     */
    function removeWatcher(listener: (...args: any[]) => any): void;

    /**
     * SKIP_DOCS
     */
    function _makeDeviceEmitter(): void;

}

/**
 * An audio device attached to the system.
Obtain instances via ``hs.audiodevice`` module methods — do not instantiate directly.
## Getting and setting volume
```javascript
const dev = hs.audiodevice.defaultOutputDevice();
if (dev) {
    console.log(dev.volume);    // 0.0 – 1.0, or null
    dev.volume = 0.5;
}
```
## Watching for changes
```javascript
const dev = hs.audiodevice.defaultOutputDevice();
if (dev) {
    var fn = function(event) { console.log("Device event:", event); };
    dev.addWatcher(fn);
    // later…
    dev.removeWatcher(fn);
}
```
 */
declare class HSAudioDevice {
    /**
     * The current output data source as `{ id, name }`, or `null` if unavailable.
     * @returns A dictionary containing the id and name of the current output data source
     */
    currentOutputDataSource(): Record<string, any> | null;

    /**
     * The current input data source as `{ id, name }`, or `null` if unavailable.
     * @returns A dictionary containing the id and name of the current input data source
     */
    currentInputDataSource(): Record<string, any> | null;

    /**
     * All available output data sources as an array of `{ id, name }` objects.
     * @returns A dictionary containing the ids and names of all available output data sources
     */
    outputDataSources(): Record<string, any>[];

    /**
     * All available input data sources as an array of `{ id, name }` objects.
     * @returns A dictionary containing the ids and names of all available input data sources
     */
    inputDataSources(): Record<string, any>[];

    /**
     * Select an output data source by its numeric ID.
     * @param sourceID The `id` value from ``outputDataSources()``
     * @returns `true` on success
     */
    setCurrentOutputDataSource(sourceID: number): boolean;

    /**
     * Select an input data source by its numeric ID.
     * @param sourceID The `id` value from ``inputDataSources()``
     * @returns `true` on success
     */
    setCurrentInputDataSource(sourceID: number): boolean;

    /**
     * Make this device the system default output device.
     * @returns `true` on success
     */
    setDefaultOutputDevice(): boolean;

    /**
     * Make this device the system default input device.
     * @returns `true` on success
     */
    setDefaultInputDevice(): boolean;

    /**
     * Make this device the system alert sound (effect) device.
     * @returns `true` on success
     */
    setDefaultEffectDevice(): boolean;

    /**
     * Register a listener for a per-device property-change event.
     * @param listener A JavaScript function that receives an event name string
     */
    addWatcher(listener: (event: string) => void): void;

    /**
     * Remove a previously registered per-device listener.
     * @param listener The JavaScript function that was passed to ``addWatcher(_:)``
     */
    removeWatcher(listener: (...args: any[]) => any): void;

    /**
     * The CoreAudio object ID of this device.
     */
    readonly id: number;

    /**
     * The human-readable name of this device (e.g. `"Built-in Output"`).
     */
    readonly name: string;

    /**
     * The persistent unique identifier for this device.
     */
    readonly uid: string;

    /**
     * Whether this device has output streams (can play audio).
     */
    readonly isOutput: boolean;

    /**
     * Whether this device has input streams (can record audio).
     */
    readonly isInput: boolean;

    /**
     * The transport mechanism: `"built-in"`, `"usb"`, `"bluetooth"`, `"bluetooth-le"`,
`"hdmi"`, `"display-port"`, `"firewire"`, `"airplay"`, `"avb"`,
`"thunderbolt"`, `"virtual"`, `"aggregate"`, `"pci"`, or `"unknown"`.
     */
    readonly transportType: string;

    /**
     * Number of output channels, or 0 if the device has no output.
     */
    readonly outputChannels: number;

    /**
     * Number of input channels, or 0 if the device has no input.
     */
    readonly inputChannels: number;

    /**
     * Output volume scalar in the range `0.0`–`1.0`, or `null` if the device has
no controllable output volume. Setting `null` is a no-op.
     */
    volume: number | null;

    /**
     * Whether output is muted. Always `false` if the device has no mutable output.
     */
    muted: boolean;

    /**
     * Output stereo balance in the range `0.0` (full left)–`1.0` (full right),
or `null` if balance control is not available.
     */
    balance: number | null;

    /**
     * Input (microphone) volume scalar in the range `0.0`–`1.0`, or `null` if
the device has no controllable input volume.
     */
    inputVolume: number | null;

    /**
     * Whether input is muted. Always `false` if the device has no mutable input.
     */
    inputMuted: boolean;

    /**
     * The current nominal sample rate in Hz (e.g. `44100`), or `null` if unknown.
     */
    sampleRate: number | null;

    /**
     * All sample rates (in Hz) that this device supports.
For devices that support a range, both the minimum and maximum are included.
     */
    readonly availableSampleRates: number[];

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
    function systemWideElement(): HSAXElement | null;

    /**
     * Get the accessibility element for an application
     * @param element An HSApplication object
     * @returns The AXElement for the application, or nil if accessibility is not available
     */
    function applicationElement(element: HSApplication): HSAXElement | null;

    /**
     * Get the accessibility element for a window
     * @param window An HSWindow  object
     * @returns The AXElement for the window, or nil if accessibility is not available
     */
    function windowElement(window: HSWindow): HSAXElement | null;

    /**
     * Get the accessibility element at the specific screen position
     * @param point An HSPoint object containing screen coordinates
     * @returns The AXElement at that position, or nil if none found
     */
    function elementAtPoint(point: HSPoint): HSAXElement | null;

    /**
     * Add a watcher for application AX events
     * @param application An HSApplication object
     * @param notification An event name
     * @param listener A function called with the notification name and the accessibility element it applies to
     */
    function addWatcher(application: HSApplication, notification: string, listener: (notification: string, element: HSAXElement) => void): void;

    /**
     * Remove a watcher for application AX events
     * @param application An HSApplication object
     * @param notification The event name to stop watching
     * @param listener The function/lambda provided when adding the watcher
     */
    function removeWatcher(application: HSApplication, notification: string, listener: (...args: any[]) => any): void;

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
    children(): HSAXElement[];

    /**
     * Get a specific child by index
     * @param index The index to fetch
     * @returns An HSAXElement object, if a child exists at the given index
     */
    childAtIndex(index: number): HSAXElement | null;

    /**
     * Get all available attribute names
     * @returns An array of attribute names
     */
    attributeNames(): string[];

    /**
     * Get the value of a specific attribute
     * @param attribute The attribute name to fetch the value for
     * @returns The requested value, or nil if none was found
     */
    attributeValue(attribute: string): any | null;

    /**
     * Set the value of a specific attribute
     * @param attribute The attribute name to set
     * @param value The value to set
     * @returns True if the operation succeeded, otherwise False
     */
    setAttributeValue(attribute: string, value: any): boolean;

    /**
     * Check if an attribute is settable
     * @param attribute An attribute name
     * @returns True if the attribute is settable, otherwise False
     */
    isAttributeSettable(attribute: string): boolean;

    /**
     * Get all available action names
     * @returns An array of available action names
     */
    actionNames(): string[];

    /**
     * Perform a specific action
     * @param action The action to perform
     * @returns True if the action succeeded, otherwise False
     */
    performAction(action: string): boolean;

    /**
     * The element's role (e.g., "AXWindow", "AXButton")
     */
    readonly role: string | null;

    /**
     * The element's subrole
     */
    readonly subrole: string | null;

    /**
     * The element's title
     */
    readonly title: string | null;

    /**
     * The element's value
     */
    readonly value: any | null;

    /**
     * The element's description
     */
    readonly elementDescription: string | null;

    /**
     * Whether the element is enabled
     */
    readonly isEnabled: boolean;

    /**
     * Whether the element is focused
     */
    isFocused: boolean;

    /**
     * The element's position on screen
     */
    position: HSPoint | null;

    /**
     * The element's size
     */
    size: HSSize | null;

    /**
     * The element's frame (position and size combined)
     */
    frame: HSRect | null;

    /**
     * The element's parent
     */
    readonly parent: HSAXElement | null;

    /**
     * Get the process ID of the application that owns this element
     */
    readonly pid: number;

}

/**
 * Discover and publish Bonjour (mDNS / Zeroconf) network services.
Use `createSearch()` to search the network for services advertised by other
devices, and `advertise()` to advertise your own. The `networkServices()`
convenience function returns a snapshot of all service types currently
active on the local network.
## Common service type strings
The `hs.bonjour.serviceTypes` object maps short names to their mDNS strings,
e.g. `hs.bonjour.serviceTypes.ssh` → `"_ssh._tcp."`.
## Searching for a service
```js
// Find all SSH services on the local network and resolve each one
const search = hs.bonjour.createSearch()
search.findServices('_ssh._tcp.', 'local.', (event, svc, moreComing) => {
    if (event === 'serviceFound') {
        svc.resolve(5, ev => {
            if (ev === 'resolved') console.log(svc.hostname + ':' + svc.port)
        })
    }
})
```
## Advertising a service
```js
hs.bonjour.advertise('My Web Server', '_http._tcp.', 8080, ev => {
    if (ev === 'published') console.log('Now advertising!')
    else if (ev === 'error') console.error('Advertising failed')
})
// Later, to stop:
hs.bonjour.stopAdvertising('My Web Server', '_http._tcp.')
```
## Listing all active service types
```js
hs.bonjour.networkServices(5).then(types => {
    console.log('Active service types: ' + types.join(', '))
})
```
 */
declare namespace hs.bonjour {
    /**
     * Creates a new Bonjour search for discovering services or domains.
Call one of the `find…` methods on the returned search to start
discovering. Remove it with `removeSearch()` when finished.
     * @returns a new `HSBonjourSearch`
     */
    function createSearch(): HSBonjourSearch;

    /**
     * Stops and removes a previously created search.
     * @param search the search returned by `createSearch()`
     */
    function removeSearch(search: HSBonjourSearch): void;

    /**
     * Starts advertising a local service on the network.
If `domain` is omitted or not a string, it defaults to `"local."`.
If the 4th argument is a function, it is used as the callback and domain
defaults to `"local."`.
     * @param name human-readable name shown to browsers (e.g. `"My Web Server"`)
     * @param type service type in `"_proto._tcp."` or `"_proto._udp."` form
     * @param port port number the service listens on
     * @param domain mDNS domain; defaults to `"local."` if an empty string is passed
     * @param callback Optional function called on status changes with event name and optional error message
     */
    function advertise(name: string, type: string, port: number, domain: string, callback?: ((event: string, error?: string) => void) | null): void;

    /**
     * Stops advertising a service previously started with `advertise()`.
     * @param name the name passed to `advertise()`
     * @param type the type passed to `advertise()`
     */
    function stopAdvertising(name: string, type: string): void;

    /**
     * Returns a Promise that resolves to an array of service-type strings
currently advertised on the local network.
Internally searches for `_services._dns-sd._udp.` services, collects
results for up to `timeout` seconds (or until the browser signals no more
results), then resolves.
     * @param timeout maximum seconds to wait (pass `0` to use the default 5 s)
     * @returns a Promise resolving to an array of service-type strings such as `"_http._tcp."`
     */
    function networkServices(timeout: number): Promise<string[]>;

    /**
     * A frozen object mapping short service-type names to their mDNS strings.
Populated by the JavaScript enhancement layer.
     */
    const serviceTypes: Record<string, string>;

}

/**
 * Discovers Bonjour services and domains advertised on the local network.
Create via `hs.bonjour.newSearch()`, then call one of the `find…` methods.
Each search type uses its own underlying `NetServiceBrowser`, so service and
domain searches can run concurrently. Restarting any single search type stops
only that browser before beginning the new one.
## Service search callback events
| Event | Data | Description |
|-------|------|-------------|
| `"serviceFound"` | `HSBonjourService` | A matching service appeared |
| `"serviceRemoved"` | `HSBonjourService` | A previously found service disappeared |
| `"error"` | error string | The search failed |
## Domain search callback events
| Event | Data | Description |
|-------|------|-------------|
| `"domainFound"` | domain string | A domain was discovered |
| `"domainRemoved"` | domain string | A domain disappeared |
| `"error"` | error string | The search failed |
 */
declare class HSBonjourSearch {
    /**
     * Searches for services of the given type in the given domain.
If a service search is already active it is stopped before starting the
new one. Domain searches are unaffected. The callback receives
`(event, service, moreComing)` — see the type documentation for the
complete event table.
     * @param type service type string, e.g. `"_http._tcp."` or `"_ssh._tcp."`
     * @param domain mDNS domain; `"local."` for the local link, `""` for all domains
     * @param callback Called for each result with event name, service object, and whether more results are expected
     * @returns self, for chaining
     */
    findServices(type: string, domain: string, callback: (event: string, service: HSBonjourService, moreComing: boolean) => void): HSBonjourSearch;

    /**
     * Searches for domains visible to this machine (browsable domains).
If a browsable-domain search is already active it is stopped before
starting the new one. Service and registration-domain searches are
unaffected. The callback receives `(event, domain, moreComing)`.
     * @param callback Called for each result with event name, domain string, and whether more results are expected
     * @returns self, for chaining
     */
    findBrowsableDomains(callback: (event: string, domain: string, moreComing: boolean) => void): HSBonjourSearch;

    /**
     * Searches for domains on which this machine can register services.
If a registration-domain search is already active it is stopped before
starting the new one. Service and browsable-domain searches are
unaffected. The callback receives `(event, domain, moreComing)`.
     * @param callback Called for each result with event name, domain string, and whether more results are expected
     * @returns self, for chaining
     */
    findRegistrationDomains(callback: (event: string, domain: string, moreComing: boolean) => void): HSBonjourSearch;

    /**
     * Stops all active searches. Safe to call when no search is active.
     * @returns self, for chaining
     */
    stop(): HSBonjourSearch;

    /**
     * A unique identifier for this search object.
     */
    readonly identifier: string;

    /**
     * Whether to search over peer-to-peer Bluetooth/Wi-Fi in addition to
standard network interfaces. Defaults to `false`.
     */
    includesPeerToPeer: boolean;

}

/**
 * A discovered Bonjour service record. Call `resolve()` to look up its
hostname, port, and addresses.
Instances are delivered by an `HSBonjourSearch` callback. Call `resolve()`
to discover their hostname, port, and addresses, and optionally `monitor()`
to watch for TXT record changes.
## Callback events
| Method | Event | Extra data |
|--------|-------|------------|
| `resolve()` | `"resolved"` | _(none)_ |
| `resolve()` | `"stopped"` | _(none)_ |
| `resolve()` | `"error"` | error message string |
| `monitor()` | `"txtRecord"` | updated TXT record dict |
 */
declare class HSBonjourService {
    /**
     * Resolves the hostname, port, addresses, and TXT record of this service.
     * @param timeout seconds before giving up; pass `0` for no timeout
     * @param callback Called on status changes with event name and optional error message
     * @returns self, for chaining
     */
    resolve(timeout: number, callback: (event: string, error?: string) => void): HSBonjourService;

    /**
     * Starts monitoring the TXT record for changes. The callback fires whenever
the TXT record is updated.
Call `stopMonitoring()` to unsubscribe.
     * @param callback Called when TXT data changes with the updated record
     * @returns self, for chaining
     */
    monitor(callback: (txtRecord: Record<string, string>) => void): HSBonjourService;

    /**
     * Stops any active resolution.
     * @returns self, for chaining
     */
    stop(): HSBonjourService;

    /**
     * Stops TXT record monitoring started by `monitor()`.
     * @returns self, for chaining
     */
    stopMonitoring(): HSBonjourService;

    /**
     * A unique identifier assigned to this service object.
     */
    readonly identifier: string;

    /**
     * The service name (e.g. `"My Web Server"`).
     */
    readonly name: string;

    /**
     * The service type string (e.g. `"_http._tcp."`).
     */
    readonly type: string;

    /**
     * The mDNS domain (almost always `"local."`).
     */
    readonly domain: string;

    /**
     * The resolved hostname, or `null` before `resolve()` completes.
     */
    readonly hostname: string | null;

    /**
     * The service port. `-1` until `resolve()` completes.
     */
    readonly port: number;

    /**
     * IP address strings (IPv4 and/or IPv6) populated after `resolve()` completes.
     */
    readonly addresses: string[];

    /**
     * The TXT record as a `{key: value}` object, or `null` if none is available.
Populated after `resolve()` completes or when updated via `monitor()`.
     */
    readonly txtRecord: Record<string, string> | null;

    /**
     * Whether peer-to-peer Bluetooth/Wi-Fi is included in resolution.
     */
    includesPeerToPeer: boolean;

}

/**
 * Module for discovering and interacting with camera devices.
This module lets you enumerate cameras, capture still images, and react to
device connect/disconnect events in real time.
Camera access requires user permission. Call `hs.permissions.requestCamera()`
before using ``captureImage()`` or reading ``isInUse``.
## Enumerating cameras
```javascript
const cameras = hs.camera.all()
cameras.forEach(cam => {
    console.log(cam.name + " — " + (cam.isInUse ? "in use" : "idle"))
})
```
## Finding a specific camera
```javascript
const cam = hs.camera.findByName("FaceTime HD Camera")
if (cam) {
    cam.captureImage()
        .then(img => img.saveToFile("/tmp/snapshot.png"))
        .catch(err => console.error("Capture error: " + err))
}
```
## Watching for connect / disconnect events
```javascript
const handler = (event, camera) => {
    if (event === "connected")    console.log("Camera connected: " + camera.name)
    if (event === "disconnected") console.log("Camera disconnected: " + camera.name)
}
hs.camera.addWatcher(handler)
// Later…
hs.camera.removeWatcher(handler)
```
## Watching a camera's in-use state
```javascript
const cam = hs.camera.all()[0]
cam.addWatcher((isInUse) => {
    console.log(cam.name + " is now " + (isInUse ? "in use" : "idle"))
})
```
 */
declare namespace hs.camera {
    /**
     * All video camera devices currently connected to the system.
     * @returns An array of `HSCamera` objects
     */
    function all(): HSCamera[];

    /**
     * Find the first camera whose name matches the given string.
     * @param name The device name to search for (exact match)
     * @returns An `HSCamera` if found, `null` otherwise
     */
    function findByName(name: string): HSCamera | null;

    /**
     * Find the camera with the given unique identifier.
     * @param uid The device UID to search for
     * @returns An `HSCamera` if found, `null` otherwise
     */
    function findByUID(uid: string): HSCamera | null;

    /**
     * Register a listener for camera device connect/disconnect events.
     * @param listener A JavaScript function called with the event name (`"connected"` or `"disconnected"`) and the affected camera
     */
    function addWatcher(listener: (event: string, camera: HSCamera) => void): void;

    /**
     * Remove a previously registered module-level event listener.
     * @param listener The function originally passed to ``addWatcher(_:)``
     */
    function removeWatcher(listener: (...args: any[]) => any): void;

    /**
     * SKIP_DOCS
     */
    function _makeCameraEmitter(): void;

}

/**
 * A camera device attached to the system.
Obtain instances via the ``hs.camera`` module — do not instantiate directly.
## Reading camera properties
```javascript
const cam = hs.camera.all()[0]
console.log(cam.name + " uid=" + cam.uid + " inUse=" + cam.isInUse)
```
## Watching for in-use state changes
```javascript
const cam = hs.camera.all()[0]
const fn = (isInUse) => {
    console.log(cam.name + " is now " + (isInUse ? "in use" : "not in use"))
}
cam.addWatcher(fn)
// later…
cam.removeWatcher(fn)
```
## Capturing a still image
```javascript
const cam = hs.camera.all()[0]
cam.captureImage()
    .then(img => img.saveToFile("/tmp/shot.png"))
    .catch(err => console.error("Capture failed: " + err))
```
 */
declare class HSCamera {
    /**
     * Register a listener that fires whenever this camera's in-use state changes.
The listener receives one argument: a boolean that is `true` when the camera
starts being used and `false` when it is released.
     * @param listener A JavaScript function called with `true` when the camera starts being used and `false` when released
     */
    addWatcher(listener: (isInUse: boolean) => void): void;

    /**
     * Remove a previously registered per-camera in-use listener.
     * @param listener The function originally passed to ``addWatcher(_:)``
     */
    removeWatcher(listener: (...args: any[]) => any): void;

    /**
     * Capture a still image from this camera.
Camera permission must be granted via `hs.permissions.requestCamera()` before calling
this method. The returned `HSImage` can be saved, displayed in a UI element, or
passed to other image-processing APIs.
     * @returns A Promise that resolves to an `HSImage`, or rejects on error
     */
    captureImage(): Promise<HSImage>;

    /**
     * The type name for JavaScript introspection. Always `"HSCamera"`.
     */
    readonly typeName: string;

    /**
     * The persistent unique identifier for this camera.
     */
    readonly uid: string;

    /**
     * The human-readable name of this camera (e.g. `"FaceTime HD Camera"`).
     */
    readonly name: string;

    /**
     * Whether this camera is currently being used by any application.
Queries the underlying CoreMediaIO device state each time it is read.
     */
    readonly isInUse: boolean;

}

/**
 * # hs.chooser
**A Spotlight-style chooser for presenting options to the user**
`hs.chooser` lets you show a floating search panel that users can type into to filter and
select from a list of items. It's ideal for launchers, emoji pickers, command palettes, and
any interface where you want fast, keyboard-driven selection.
## Quick Start
```javascript
const chooser = hs.chooser.create()

chooser.setChoices([
    { text: "Open Safari", subText: "Web browser", action: "safari" },
    { text: "Open Terminal", subText: "Command line", action: "terminal" }
])

chooser.onSelect = (item) => {
    if (item) console.log("Selected: " + item.text + " (" + item.action + ")")
}

chooser.show()
```
## Dynamic Choices
```javascript
const allApps = hs.application.runningApplications()

chooser.setChoices((query) => {
    const q = query.toLowerCase()
    return allApps
        .filter(a => a.title.toLowerCase().includes(q))
        .map(a => ({ text: a.title, subText: a.bundleID }))
})
```
## Async Choices (with debounce)
```javascript
let debounceTimer = null
let cachedResults = []

chooser.setChoices(() => cachedResults)

chooser.onQueryChange = (query) => {
    if (debounceTimer) debounceTimer.invalidate()
    debounceTimer = hs.timer.doAfter(0.05, () => {
        fetchFromAPI(query).then(results => {
            cachedResults = results
            chooser.refreshChoices()
        })
    })
}
```
 */
declare namespace hs.chooser {
    /**
     * Create a new chooser.
     * @returns A new `HSChooser` object ready for configuration
     */
    function create(): HSChooser;

}

/**
 * A keyboard-driven floating chooser panel.
Create via `hs.chooser.create()`. Configure choices, set callbacks, then call `.show()`.
## Choice format
Each choice is a plain object with required `text` and optional `subText`, `image`, `valid`,
and `contextMenu` fields. All other fields are passed through to the `onSelect` callback unchanged.
The `contextMenu` array defines per-row right-click menu entries. Each entry is either
```javascript
{
  text: "Open Safari", subText: "com.apple.Safari",
  image: HSImage.fromAppBundle("com.apple.Safari"), valid: true, myData: 42,
  contextMenu: [
    { title: "Open", action: () => hs.urlevent.openURL("https://apple.com") },
    { type: "divider" },
    { title: "Copy bundle ID", action: () => hs.pasteboard.writeString("com.apple.Safari") }
  ]
}
```
## Keyboard shortcuts
 */
declare class HSChooser {
    /**
     * on show. The function is responsible for filtering; the chooser displays all items it returns.
     * @param choices An array of choice objects, or a function `(query) => [...]`
     * @returns Self for chaining
     */
    setChoices(choices: Array<Record<string, any>> | ((query: string) => Array<Record<string, any>>)): HSChooser;

    /**
     * Re-apply filtering (static choices) or re-invoke the choices function (dynamic).
Call after updating an external data source in an async `onQueryChange` handler.
     * @returns Self for chaining
     */
    refreshChoices(): HSChooser;

    /**
     * Show the chooser.
     * @returns Self for chaining
     */
    show(): HSChooser;

    /**
     * Hide the chooser without making a selection. Restores focus to the previously active window.
     * @returns Self for chaining
     */
    hide(): HSChooser;

    /**
     * Programmatically confirm a selection.
Omit `row` to confirm the currently highlighted row. Fires `onSelect` (or `onInvalid`
for rows with `valid: false`) and hides the chooser.
     * @param row Zero-based row index, or omit to use the current selection.
     * @returns Self for chaining
     */
    select(row: number | null): HSChooser;

    /**
     * Returns the dict for the highlighted row, or for a specific row by index.
Returns `null` if the index is out of range or no choices are set.
     * @param row Zero-based row index, or omit to query the highlighted row.
     * @returns The row dict (`{ text, subText?, image?, valid, ...extras }`) or `null`.
     */
    selectedRowContents(row: number | null): Record<string, any> | null;

    /**
     * Read-only type identifier.
     */
    readonly typeName: string;

    /**
     * Stable UUID string for this chooser instance.
     */
    readonly identifier: string;

    /**
     * The current text in the search field. Setting this from JS updates the display but
does not invoke the `onQueryChange` callback.
     */
    query: string;

    /**
     * Placeholder text shown in the empty search field (default: `"Search..."`).
     */
    placeholder: string;

    /**
     * Whether searches match against `subText` in addition to `text` (default: `false`).
Only applies when a static choices array is provided.
     */
    searchSubText: boolean;

    /**
     * When `true` and the query is non-empty but there are no matching choices, `onSelect`
is called with `{ text: <query> }` instead of `null` (default: `false`).
     */
    enableDefaultForQuery: boolean;

    /**
     * The zero-based index of the currently highlighted row (-1 when empty).
     */
    selectedRow: number;

    /**
     * Width of the chooser as a fraction of the screen width (default: `0.5` = 50 %).
     */
    width: number;

    /**
     * Maximum number of rows visible at once without scrolling (default: `10`).
     */
    visibleRows: number;

    /**
     * `true` if the chooser panel is currently on screen.
     */
    readonly isVisible: boolean;

    /**
     * Called when the user confirms a selection, or null to remove the handler.
The argument is the chosen row object (the original dict you passed to `setChoices`,
with `text`, `subText`, `image`, `valid`, and any custom fields intact).
The argument is `null` when dismissed (Escape).
     */
    onSelect: ((item: Record<string, any> | null) => void) | null;

    /**
     * Called on every keystroke with the new query string, or null to remove the handler.
Use this to debounce expensive searches or trigger async data fetching.
     */
    onQueryChange: ((query: string) => void) | null;

    /**
     * Called after the panel becomes visible, or null to remove the handler.
     */
    onShow: (() => void) | null;

    /**
     * Called after the panel is hidden (for any reason: selection, Escape, or `hide()`), or null to remove the handler.
     */
    onHide: (() => void) | null;

    /**
     * Called when the user activates a row whose `valid` field is `false`, or null to remove the handler.
The chooser stays open; the argument is the row dict (same shape as `onSelect`).
If unset, activating an invalid row is silently ignored.
     */
    onInvalid: ((item: Record<string, any>) => void) | null;

}

/**
 * # hs.docs
**Offline API documentation browser**
Browse and query the Hammerspoon 2 API documentation from within the app.
`hs.docs.show()` opens an `hs.ui.webview` window with the JS or TypeScript docs.
`hs.docs.get()` returns formatted plain-text documentation from the bundled `api.json`.
 */
declare namespace hs.docs {
    /**
     * Open the Hammerspoon 2 API documentation in a new window
     * @param moduleName Optional module to navigate to directly (e.g. `"hs.application"`). Omit to open the index page.
     * @param showTS Pass `true` to show TypeScript docs instead of JS docs
     */
    function show(moduleName?: string | null, showTS?: boolean): void;

    /**
     * Return documentation for a module, method, or property
     * @param identifier Dot-separated path such as `"hs.camera"` or `"hs.camera.all"`
     * @returns A plain-text summary of the item, or `null` if not found
     */
    function get(identifier: string): string | null;

    /**
     * Return the filesystem path to the bundled JS documentation directory
     * @returns Absolute path to the JS docs folder inside the app bundle, or `null`
     */
    function jsDocsPath(): string | null;

    /**
     * Return the filesystem path to the bundled TypeScript documentation directory
     * @returns Absolute path to the TS docs folder inside the app bundle, or `null`
     */
    function tsDocsPath(): string | null;

    /**
     * Return the contents of the bundled `api.json` file
     * @returns JSON string containing the full API specification, or `null`
     */
    function apiJSON(): string | null;

}

/**
 * Monitor and synthesise macOS input events: keyboard, mouse, and scroll wheel.
All coordinate parameters use **Hammerspoon screen coordinates**: the origin `(0, 0)`
is at the top-left of the primary display and `y` increases downward, matching `hs.screen`.
## Tapping events
```js
const tap = hs.eventtap.addWatcher(
    [hs.eventtap.eventTypes.keyDown],
    (event) => {
        console.log("Key pressed: " + event.keyCode)
        return hs.eventtap.emit   // pass the event through
    }
)
tap.start()
```
## Suppressing events
Returning `hs.eventtap.consume` from the callback prevents the event from reaching
```js
const blocker = hs.eventtap.addWatcher(
    [hs.eventtap.eventTypes.leftMouseDown],
    (event) => hs.eventtap.consume
)
blocker.start()
```
## Sending events
```js
hs.eventtap.keyStroke(["cmd"], "c")
hs.eventtap.leftClick(500, 300)
```
 */
declare namespace hs.eventtap {
    /**
     * Create an event tap that calls a function for matching events. Call `.start()` to activate it.
The callback receives an `HSEventTapEvent`. For modify taps (`listenOnly` omitted or false),
return `hs.eventtap.consume` (false) to suppress the event or `hs.eventtap.emit` (true)
to pass it through. For listen-only taps the callback's return value is ignored — events
are always delivered to other applications. Requires Accessibility permission.
     * @remarks event tap watchers will not be automatically destroyed by JavaScript garbage collection. You *MUST* call `removeWatcher()` if you want to dispose of a watcher.
     * @param types An array of event type integers from `hs.eventtap.eventTypes`
     * @param callback Function called for each matching event. The return value is only meaningful for modify taps.
     * @param listenOnly If true, the tap receives events but cannot modify or suppress them. Omit or pass false for a modify tap (the default).
     * @returns An HSEventTap watcher, or null if the tap could not be created
     */
    function addWatcher(types: number[], callback: (event: HSEventTapEvent) => boolean | undefined, listenOnly: boolean): HSEventTap | null;

    /**
     * Stop and remove a previously created watcher
     * @param tap The HSEventTap returned by `addWatcher`
     */
    function removeWatcher(tap: HSEventTap): void;

    /**
     * Create a keyboard event
     * @param key A key name (e.g. "a", "space", "return", "f1") or numeric key code string
     * @param isDown true for key down, false for key up
     * @returns An HSEventTapEvent, or null if the key name is unknown
     */
    function makeKeyEvent(key: string, isDown: boolean): HSEventTapEvent | null;

    /**
     * Create a keyboard event using a raw key code
     * @param keyCode A numeric virtual key code
     * @param isDown true for key down, false for key up
     * @returns An HSEventTapEvent
     */
    function makeKeyEventWithCode(keyCode: number, isDown: boolean): HSEventTapEvent | null;

    /**
     * Create a mouse event at the given position.
Coordinates are in **Hammerspoon screen coordinates** (top-left origin of the primary
display, y increases downward), matching the values returned by `hs.screen`.
     * @param type An event type integer from hs.eventtap.eventTypes (e.g. leftMouseDown)
     * @param x Horizontal position in Hammerspoon screen coordinates
     * @param y Vertical position in Hammerspoon screen coordinates
     * @param button Mouse button number (0=left, 1=right, 2=middle)
     * @returns An HSEventTapEvent, or null if the event could not be created
     */
    function makeMouseEvent(type: number, x: number, y: number, button: number): HSEventTapEvent | null;

    /**
     * Create a scroll wheel event at the given position.
Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
     * @param deltaX Horizontal scroll amount in lines (positive = right)
     * @param deltaY Vertical scroll amount in lines (positive = down)
     * @param x Horizontal position in Hammerspoon screen coordinates
     * @param y Vertical position in Hammerspoon screen coordinates
     * @returns An HSEventTapEvent, or null if the event could not be created
     */
    function makeScrollWheelEvent(deltaX: number, deltaY: number, x: number, y: number): HSEventTapEvent | null;

    /**
     * Send a key down and key up event with optional modifier keys.
A 50 ms pause is inserted between the key-down and key-up events to improve
compatibility with applications that miss very fast synthetic keystrokes.
     * @param mods An array of modifier names (e.g. ["cmd", "shift"])
     * @param key A key name or single character (e.g. "a", "space", "return")
     */
    function keyStroke(mods: string[], key: string): void;

    /**
     * Type a string of characters as individual key events.
A 50 ms pause is inserted between each key-down and key-up event.
     * @param text The string to type
     */
    function keyStrokes(text: string): void;

    /**
     * Post a left mouse button click at the given position.
Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
     * @param x Horizontal position in Hammerspoon screen coordinates
     * @param y Vertical position in Hammerspoon screen coordinates
     */
    function leftClick(x: number, y: number): void;

    /**
     * Post a right mouse button click at the given position.
Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
     * @param x Horizontal position in Hammerspoon screen coordinates
     * @param y Vertical position in Hammerspoon screen coordinates
     */
    function rightClick(x: number, y: number): void;

    /**
     * Post a left mouse button double-click at the given position.
Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
     * @param x Horizontal position in Hammerspoon screen coordinates
     * @param y Vertical position in Hammerspoon screen coordinates
     */
    function doubleLeftClick(x: number, y: number): void;

    /**
     * Post a middle mouse button click at the given position.
Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
     * @param x Horizontal position in Hammerspoon screen coordinates
     * @param y Vertical position in Hammerspoon screen coordinates
     */
    function middleClick(x: number, y: number): void;

    /**
     * Post a scroll wheel event at the given position.
Coordinates are in **Hammerspoon screen coordinates** (top-left origin, y increases downward).
     * @param deltaX Horizontal scroll amount in lines (positive = right)
     * @param deltaY Vertical scroll amount in lines (positive = down)
     * @param x Horizontal position in Hammerspoon screen coordinates
     * @param y Vertical position in Hammerspoon screen coordinates
     */
    function scrollWheel(deltaX: number, deltaY: number, x: number, y: number): void;

    /**
     * Returns the currently held modifier keys
     * @returns An array of modifier key names such as ["cmd", "shift"]
     */
    function currentModifiers(): string[];

    /**
     * Returns the currently pressed mouse buttons
     * @returns A dictionary with keys "left", "right", "middle" mapping to booleans
     */
    function checkMouseButtons(): Record<string, boolean>;

    /**
     * Returns the current mouse cursor position in Hammerspoon screen coordinates
(top-left origin of primary display, y increases downward, matching hs.screen).
     * @returns A dictionary with "x" and "y" keys
     */
    function mouseLocation(): Record<string, number>;

    /**
     * Returns the system double-click interval in seconds
     * @returns The maximum time between clicks that counts as a double-click
     */
    function doubleClickInterval(): number;

    /**
     * Returns the system key repeat delay in seconds
     * @returns The delay before key repeat begins
     */
    function keyRepeatDelay(): number;

    /**
     * Returns the system key repeat interval in seconds
     * @returns The interval between repeated key events
     */
    function keyRepeatInterval(): number;

    /**
     * A dictionary mapping event type names to their numeric values.
Pass values from this dictionary to `addWatcher()` to specify which events to monitor.
     */
    const eventTypes: Record<string, number>;

    /**
     * A dictionary mapping modifier key names to their bitmask values for use with `rawFlags`.
Includes generic names (`cmd`, `shift`, `alt`, `ctrl`) and side-specific names
(`leftCmd`, `rightCmd`, `leftShift`, `rightShift`, `leftAlt`, `rightAlt`,
`leftCtrl`, `rightCtrl`) for distinguishing physical keys.
     */
    const modifierFlags: Record<string, number>;

    /**
     * Return this from an event tap callback to suppress the event (prevent other apps from receiving it).
     */
    const consume: boolean;

    /**
     * Return this from an event tap callback to allow the event to pass through to other applications.
     */
    const emit: boolean;

}

/**
 * An event tap watcher that intercepts input events from the system.
Obtain instances via `hs.eventtap.addWatcher()` — do not instantiate directly.
## Monitoring keyboard events
```js
const tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
    console.log("Key pressed: " + event.keyCode)
})
```
 */
declare class HSEventTap {
    /**
     * Start receiving events. Requires Accessibility permission.
     * @returns This tap, for chaining
     */
    start(): HSEventTap;

    /**
     * Stop receiving events
     * @returns This tap, for chaining
     */
    stop(): HSEventTap;

    /**
     * Replace the callback function
     * @param callback A function called for each matching event. Return false to consume (suppress) the event; return anything else to pass it through.
     * @returns This tap, for chaining
     */
    setCallback(callback: (event: HSEventTapEvent) => boolean | undefined): HSEventTap;

    /**
     * Whether this tap is currently active
     * @returns True if the tap is running
     */
    isEnabled(): boolean;

    /**
     * Whether this tap has been registered with macOS
     * @returns True if the tap has been created
     */
    isCreated(): boolean;

    /**
     * A unique identifier for this tap
     */
    readonly identifier: string;

    /**
     * Whether this tap was created as listen-only (events are observed but never modified or suppressed)
     */
    readonly listenOnly: boolean;

}

/**
 * An input event captured or constructed by hs.eventtap.
Objects of this type are passed to event tap callbacks and can also be created directly
via the factory methods on hs.eventtap. Properties can be inspected and modified before
the event is passed through or posted back to the system.
 */
declare class HSEventTapEvent {
    /**
     * Create an independent copy of this event
     * @returns A new HSEventTapEvent with the same properties, or null if the copy failed
     */
    duplicate(): HSEventTapEvent | null;

    /**
     * Post this event to the HID event stream, optionally targeting a specific application.
When `app` is omitted or `null`, the event is posted to the global HID stream and
delivered by the OS as if a real input device generated it. When an application is
provided, the event is delivered directly to that process by PID.
     * @param app The application to target, or null/omit to post globally
     */
    post(app: HSApplication | null): void;

    /**
     * Type name for introspection
     */
    readonly typeName: string;

    /**
     * The numeric event type, matching a value in hs.eventtap.eventTypes
     */
    readonly type: number;

    /**
     * The virtual key code for keyboard events (get/set)
     */
    keyCode: number;

    /**
     * The raw modifier flags bitmask (get/set). Use values from hs.eventtap.modifierFlags.
     */
    rawFlags: number;

    /**
     * An array of active modifier key names (e.g. ["cmd", "shift"]).
When a device-specific modifier is detected, both the generic and side-specific
names are included — e.g. pressing the left Command key yields ["cmd", "leftCmd"].
     */
    readonly flags: string[];

    /**
     * The event's screen position as {x, y} in Hammerspoon screen coordinates
(top-left origin of primary display, y increases downward, matching hs.screen).
     */
    location: Record<string, number>;

    /**
     * The mouse button number for mouse events (0=left, 1=right, 2=middle)
     */
    buttonNumber: number;

    /**
     * The horizontal scroll delta for scroll wheel events
     */
    readonly scrollingDeltaX: number;

    /**
     * The vertical scroll delta for scroll wheel events
     */
    readonly scrollingDeltaY: number;

    /**
     * The Unicode characters produced by this keyboard event, or null for non-keyboard events
     */
    readonly characters: string | null;

}

/**
 * Module for filesystem operations.
`hs.fs` provides a comprehensive set of filesystem operations covering file
I/O, directory management, path manipulation, metadata access, symbolic
links, Finder tags, and macOS-specific features like file bookmarks and
Uniform Type Identifiers.
It replaces both Hammerspoon v1's `hs.fs` module and the functionality that
was previously available through Lua's built-in `io` and `file` modules.
## Reading and writing files
```javascript
const contents = hs.fs.read("/etc/hosts");           // entire file
const chunk    = hs.fs.read("/etc/hosts", 100, 50);  // 50 bytes from offset 100

hs.fs.readLines("/etc/hosts", function(line) {
    console.log(line);
    return true; // return false to stop early
});

hs.fs.write("/tmp/hello.txt", "Hello, world!\n");
hs.fs.append("/tmp/hello.txt", "More content\n");
```
## Directory operations
```javascript
hs.fs.mkdir("~/Projects/new-thing");

const files = hs.fs.list("~/Documents");
const all   = hs.fs.listRecursive("~/Documents");
```
## Path utilities
```javascript
const abs  = hs.fs.pathToAbsolute("~/Library");
const tmp  = hs.fs.temporaryDirectory();
const home = hs.fs.homeDirectory();
```
## Metadata
```javascript
const info = hs.fs.attributes("/etc/hosts");
// { size: 1234, type: "file", permissions: 420,
//   ownerID: 0, groupID: 0,
//   creationDate: 1700000000.0, modificationDate: 1700001000.0 }
```
 */
declare namespace hs.fs {
    /**
     * Read part or all of a file as a UTF-8 string.
     * @param path Path to the file. `~` is expanded.
     * @param offset Byte offset to start reading from. Pass `0` (or omit) to read from the beginning.
     * @param length Maximum number of bytes to read. Pass `0` (or omit) to read to the end of the file.
     * @returns The file contents as a UTF-8 string, or `null` if the file cannot be read.
     */
    function read(path: string, offset: number, length: number): string | null;

    /**
     * Read a file line-by-line, invoking a callback for each line.
Lines are delivered with newline characters stripped. Both `\n` and `\r\n` line endings are handled.
     * @param path Path to the file. `~` is expanded.
     * @param callback Called once per line with the line text. Return `true` to continue reading, or `false` to stop early.
     * @returns `true` if the file was read successfully (including early stops requested by the callback), or `false` if the file could not be opened.
     */
    function readLines(path: string, callback: (line: string) => boolean): boolean;

    /**
     * Write a UTF-8 string to a file, creating it or overwriting any existing content.
Intermediate directories are not created automatically; use `mkdir` first if needed.
     * @param path Path to the file. `~` is expanded.
     * @param content String to write.
     * @param inPlace Whether to write the file in-place or atomically. Defaults to atomically (false).
     * @returns `true` on success, `false` on failure.
     */
    function write(path: string, content: string, inPlace?: boolean): boolean;

    /**
     * Append a UTF-8 string to a file, creating it if it does not exist.
     * @param path Path to the file. `~` is expanded.
     * @param content String to append.
     * @returns `true` on success, `false` on failure.
     */
    function append(path: string, content: string): boolean;

    /**
     * Determine if a filesystem object exists at the given path
Unlike `isFile` and `isDirectory`, this follows symlinks.
     * @param path Path to check. `~` is expanded.
     * @returns `true` if any filesystem entry (file, directory, symlink, etc.) exists at the path.
     */
    function exists(path: string): boolean;

    /**
     * Determine if a file exists at the given path
This does **not** follow symlinks; a symlink pointing at a file returns `false`.
     * @param path Path to check. `~` is expanded.
     * @returns `true` if a regular file (not a directory or symlink) exists at the path.
     */
    function isFile(path: string): boolean;

    /**
     * Determine if a directory exists at the given path
This does **not** follow symlinks; a symlink pointing at a directory returns `false`.
     * @param path Path to check. `~` is expanded.
     * @returns `true` if a directory exists at the path.
     */
    function isDirectory(path: string): boolean;

    /**
     * Determine if a symlink exists at the given path
     * @param path Path to check. `~` is expanded.
     * @returns `true` if the path is a symbolic link.
     */
    function isSymlink(path: string): boolean;

    /**
     * Determine if a given filesystem path is readable
     * @param path Path to check. `~` is expanded.
     * @returns `true` if the current process can read the file or directory at the path.
     */
    function isReadable(path: string): boolean;

    /**
     * Determine if a given filesystem path is writable
     * @param path Path to check. `~` is expanded.
     * @returns `true` if the current process can write to the file or directory at the path.
     */
    function isWritable(path: string): boolean;

    /**
     * Copy a file or directory to a new location.
The destination must not already exist. If `source` is a directory, its
entire contents are copied recursively.
     * @param source Path to the existing file or directory. `~` is expanded.
     * @param destination Path for the copy. `~` is expanded.
     * @returns `true` on success, `false` on failure.
     */
    function copy(source: string, destination: string): boolean;

    /**
     * Move (rename) a file or directory.
The destination must not already exist.
     * @param source Path to the existing file or directory. `~` is expanded.
     * @param destination New path. `~` is expanded.
     * @returns `true` on success, `false` on failure.
     */
    function move(source: string, destination: string): boolean;

    /**
     * Delete a file or directory at the given path.
Directories are removed recursively. To remove only an empty directory,
use `rmdir` instead.
     * @param path Path to delete. `~` is expanded.
     * @returns `true` on success, `false` on failure.
     */
    function deletePath(path: string): boolean;

    /**
     * List the immediate contents of a directory.
Returns bare filenames (not full paths), sorted alphabetically.
The `.` and `..` entries are never included.
     * @param path Path to the directory. `~` is expanded.
     * @returns Sorted array of filenames, or `null` if the path cannot be read.
     */
    function list(path: string): string[] | null;

    /**
     * Recursively list all entries under a directory.
Returns paths relative to `path`, sorted alphabetically.
     * @param path Path to the root directory. `~` is expanded.
     * @returns Sorted array of relative paths, or `null` if the path cannot be read.
     */
    function listRecursive(path: string): string[] | null;

    /**
     * Create a directory, including all necessary intermediate directories.
Succeeds silently if the directory already exists.
     * @param path Path of the directory to create. `~` is expanded.
     * @returns `true` on success, `false` on failure.
     */
    function mkdir(path: string): boolean;

    /**
     * Remove an empty directory.
Fails if the directory is not empty. Use `deletePath` to remove a non-empty
directory recursively.
     * @param path Path of the directory to remove. `~` is expanded.
     * @returns `true` on success, `false` on failure.
     */
    function rmdir(path: string): boolean;

    /**
     * Returns the current working directory of the process.
     * @returns Current directory path, or `null` on error.
     */
    function currentDir(): string | null;

    /**
     * Change the current working directory of the process.
     * @param path New working directory path. `~` is expanded.
     * @returns `true` on success, `false` on failure.
     */
    function chdir(path: string): boolean;

    /**
     * Resolve a path to its absolute, canonical form.
Expands `~`, resolves `.` and `..`, and follows all symbolic links.
Returns `null` if any component of the path does not exist.
     * @param path Path to resolve.
     * @returns Absolute canonical path, or `null` if it cannot be resolved.
     */
    function pathToAbsolute(path: string): string | null;

    /**
     * Return the localised display name for a file or directory as shown by Finder.
For example, `/Library` appears as `"Library"` in Finder even though its
on-disk name is the same.
     * @param path Path to the file or directory. `~` is expanded.
     * @returns Display name string, or `null` if the path does not exist.
     */
    function displayName(path: string): string | null;

    /**
     * Returns the temporary directory for the current user.
     * @returns Temporary directory path (always ends with `/`).
     */
    function temporaryDirectory(): string;

    /**
     * Returns the home directory for the current user.
     * @returns Home directory path string.
     */
    function homeDirectory(): string;

    /**
     * Returns a `file://` URL string for the given path.
     * @param path Filesystem path. `~` is expanded.
     * @returns URL string
     */
    function urlFromPath(path: string): string;

    /**
     * Get metadata attributes for a file or directory.
Does not follow symbolic links. Use `isSymlink` to detect links before calling this if needed.
     * @param path Path to inspect. `~` is expanded.
     * @returns Attributes object, or `null` if the path cannot be accessed.
     */
    function attributes(path: string): Record<string, any> | null;

    /**
     * Update the modification timestamp of a file to the current time.
Creates the file if it does not exist (equivalent to the POSIX `touch` command).
     * @param path Path to the file. `~` is expanded.
     * @returns `true` on success, `false` on failure.
     */
    function touch(path: string): boolean;

    /**
     * Create a hard link at `destination` pointing at `source`.
Both paths must be on the same filesystem volume.
     * @param source Path of the existing file.
     * @param destination Path for the new hard link.
     * @returns `true` on success, `false` on failure.
     */
    function link(source: string, destination: string): boolean;

    /**
     * Create a symbolic link at `destination` pointing at `source`.
Unlike hard links, symlinks may cross filesystem boundaries and may
point to paths that do not yet exist.
     * @param source The path the symlink will point to.
     * @param destination The path where the symlink will be created.
     * @returns `true` on success, `false` on failure.
     */
    function symlink(source: string, destination: string): boolean;

    /**
     * Read the target of a symbolic link without resolving it.
     * @param path Path to the symbolic link.
     * @returns The raw path the link points to, or `null` if the path is not a symlink.
     */
    function readlink(path: string): string | null;

    /**
     * Get the Finder tags assigned to a file or directory.
     * @param path Path to the file or directory. `~` is expanded.
     * @returns Array of tag name strings, or `null` if no tags are set.
     */
    function tags(path: string): string[] | null;

    /**
     * Replace all Finder tags on a file or directory.
This function is only available on macOS Tahoe (26) or later.
     * @param path Path to the file.
     * @returns `true` on success, `false` on failure.
     */
    function fileUTI(path: string): string | null;

    /**
     * Encode a file path as a persistent bookmark that survives file moves and renames.
The returned string is base64-encoded bookmark data that can be stored and
later resolved with `pathFromBookmark`.
     * @param path Path to the file or directory. `~` is expanded.
     * @returns Base64-encoded bookmark string, or `null` on failure.
     */
    function pathToBookmark(path: string): string | null;

    /**
     * Resolve a base64-encoded bookmark back to a file path.
     * @param data Base64-encoded bookmark string produced by `pathToBookmark`.
     * @returns The current file path, or `null` if the bookmark cannot be resolved.
     */
    function pathFromBookmark(data: string): string | null;

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
    function base64Decode(data: string): string | null;

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
(`cmd`, `shift`, `alt`, `ctrl`, `fn`) and side-specific names (`leftCmd`, `rightCmd`,
`leftAlt`, `rightAlt`, `leftCtrl`, `rightCtrl`, `leftShift`, `rightShift`).
     * @param mods An array of modifier key strings (e.g., ["cmd", "shift"]). Supports generic names
     * @param key The key name or character (e.g., "a", "space", "return", "f1")
     * @param callbackPressed A JavaScript function to call when the hotkey is pressed, or null for no callback
     * @param callbackReleased A JavaScript function to call when the hotkey is released, or null for no callback
     * @returns A hotkey object, or null if binding failed
     */
    function bind(mods: string[], key: string, callbackPressed: (() => void) | null, callbackReleased: (() => void) | null): HSHotkey | null;

    /**
     * Bind a hotkey with a message description
     * @param mods An array of modifier key strings
     * @param key The key name or character
     * @param message A description of what this hotkey does (currently unused, for future features)
     * @param callbackPressed A JavaScript function to call when the hotkey is pressed, or null for no callback
     * @param callbackReleased A JavaScript function to call when the hotkey is released, or null for no callback
     * @returns A hotkey object, or null if binding failed
     */
    function bindSpec(mods: string[], key: string, message: string | null, callbackPressed: (() => void) | null, callbackReleased: (() => void) | null): HSHotkey | null;

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

    /**
     * Create a new modal hotkey group, optionally entered via a trigger key combination
     * @param mods Modifier keys for the trigger hotkey (e.g. `["cmd", "shift"]`), or an empty array for no trigger
     * @param key Key name for the trigger hotkey (e.g. `"h"`), or an empty string for no trigger
     * @returns A new modal object. If a non-empty key is given but cannot be resolved, a warning is logged and the modal is returned without a trigger.
     */
    function createModal(mods: string[], key: string): HSHotkeyModal;

}

/**
 * Object representing a system-wide hotkey. You should not create these objects directly, but rather, use the methods in hs.hotkey to instantiate these.
 */
declare class HSHotkey {
    /**
     * Enable the hotkey
     * @returns True if the hotkey was enabled, otherwise False
     */
    enable(): boolean;

    /**
     * Disable the hotkey
     */
    disable(): void;

    /**
     * Check if the hotkey is currently enabled
     * @returns True if the hotkey is enabled, otherwise False
     */
    isEnabled(): boolean;

    /**
     * The callback function to be called when the hotkey is pressed, or null to remove it
     */
    callbackPressed: (() => void) | null;

    /**
     * The callback function to be called when the hotkey is released, or null to remove it
     */
    callbackReleased: (() => void) | null;

}

/**
 * A group of hotkeys that are activated and deactivated together.
Obtain instances via `hs.hotkey.modal.create()` — do not instantiate directly.
## Example
```js
const m = hs.hotkey.modal.create(['cmd', 'shift'], 'h')
m.bind([], 'j', () => console.log('j pressed in modal'), null)
m.enterFn = () => console.log('modal entered')
m.exitFn  = () => console.log('modal exited')
// Press Cmd+Shift+H to enter, then J triggers the modal hotkey
```
 */
declare class HSHotkeyModal {
    /**
     * Add a hotkey that is active only while this modal is entered
     * @param mods Modifier keys for the hotkey
     * @param key Key name for the hotkey
     * @param callbackPressed Called when the key is pressed, or null
     * @param callbackReleased Called when the key is released, or null
     * @returns This modal, for chaining
     */
    bind(mods: string[], key: string, callbackPressed: (() => void) | null, callbackReleased: (() => void) | null): HSHotkeyModal;

    /**
     * Activate the modal: enable its hotkeys and disable the trigger hotkey
     * @returns This modal, for chaining
     */
    enter(): HSHotkeyModal;

    /**
     * Deactivate the modal: disable its hotkeys and re-enable the trigger hotkey
     * @returns This modal, for chaining
     */
    exit(): HSHotkeyModal;

    /**
     * Destroy the modal and all its hotkeys without calling exitFn
     */
    destroy(): void;

    /**
     * Called when the modal is entered
     */
    enterFn: (() => void) | null;

    /**
     * Called when the modal is exited
     */
    exitFn: (() => void) | null;

    /**
     * Whether the modal is currently active
     */
    readonly isActive: boolean;

}

/**
 * HTTP client module for making network requests from JavaScript.
All request methods return Promises that resolve with a result object containing
`status` (number), `body` (string), and `headers` (object). On network failure,
`status` is -1 and `body` is an empty string.
## Quick start
```js
hs.http.get("https://api.example.com/data").then(r => {
    if (r.status === 200) {
        console.log("Got: " + r.body)
    }
})
```
 */
declare namespace hs.http {
    /**
     * Perform an HTTP GET request.
     * @param url The URL to request.
     * @param headers Optional dictionary of request headers.
     * @returns {Promise<{status: number, body: string, headers: object}>} Resolves with the HTTP response.
     */
    function get(url: string, headers?: Record<string, string> | null): Promise<any>;

    /**
     * Perform an HTTP POST request.
     * @param url The URL to request.
     * @param body Optional request body string.
     * @param headers Optional dictionary of request headers.
     * @returns {Promise<{status: number, body: string, headers: object}>} Resolves with the HTTP response.
     */
    function post(url: string, body?: string | null, headers?: Record<string, string> | null): Promise<any>;

    /**
     * Perform an HTTP PUT request.
     * @param url The URL to request.
     * @param body Optional request body string.
     * @param headers Optional dictionary of request headers.
     * @returns {Promise<{status: number, body: string, headers: object}>} Resolves with the HTTP response.
     */
    function put(url: string, body?: string | null, headers?: Record<string, string> | null): Promise<any>;

    /**
     * Perform an HTTP request with any method (GET, POST, PUT, DELETE, PATCH, etc.).
Use this for methods not covered by the convenience helpers, such as DELETE or PATCH.
     * @param url The URL to request.
     * @param method The HTTP method string (e.g. "DELETE", "PATCH", "HEAD").
     * @param body Optional request body string.
     * @param headers Optional dictionary of request headers.
     * @returns {Promise<{status: number, body: string, headers: object}>} Resolves with the HTTP response.
     */
    function doRequest(url: string, method: string, body?: string | null, headers?: Record<string, string> | null): Promise<any>;

    /**
     * URL-encode a string for use as a query parameter value.
Encodes characters that are illegal in a URL query string (including `?`, `=`, `+`, `&`, `#`)
using percent-encoding.
     * @param string The string to encode.
     * @returns The percent-encoded string.
     */
    function encodeForQuery(string: string): string;

    /**
     * Parse a URL into its component parts.
Returns an object containing only the fields present in the URL. The `queryItems` field
is an array of `{name, value}` objects from the query string.
     * @param url The URL string to parse.
     * @returns An object with any of the fields: `scheme`, `host`, `port`, `user`, `password`, `path`, `query`, `fragment`, `queryItems`. Returns `null` if the URL is unparseable.
     */
    function urlParts(url: string): Record<string, any> | null;

    /**
     * Convert HTML entities in a string to their UTF-8 character equivalents.
Handles named entities (e.g. `&amp;`, `&lt;`, `&copy;`), decimal numeric references
(`&#38;`), and hexadecimal numeric references (`&#x26;`).
     * @param string The string containing HTML entities.
     * @returns The string with HTML entities replaced by their UTF-8 characters.
     */
    function convertHtmlEntities(string: string): string;

    /**
     * Open a WebSocket connection to the given URL.
The connection begins immediately. Use the returned object's chainable setter methods to
register event callbacks. The connection is automatically closed when `hs.reload()` is
called or the engine shuts down.
     * @param url The WebSocket URL (`ws://` or `wss://`).
     * @returns An `HSWebSocket` object, or `null` if the URL is invalid.
     */
    function openWebSocket(url: string): HSWebSocket | null;

}

/**
 * A WebSocket client connection created by `hs.http.openWebSocket()`.
The connection opens immediately when returned. Use the chainable setter methods to register
event callbacks, then call `send()` to transmit messages.
Do not instantiate `HSWebSocket` directly — use `hs.http.openWebSocket()`.
 */
declare class HSWebSocket {
    /**
     * Set the callback invoked when the connection is established.
     * @param callback Called when the connection opens.
     * @returns This WebSocket, for chaining.
     */
    setOpenCallback(callback: () => void): HSWebSocket;

    /**
     * Set the callback invoked when a text message is received from the server.
     * @param callback Called with each received message.
     * @returns This WebSocket, for chaining.
     */
    setMessageCallback(callback: (message: string) => void): HSWebSocket;

    /**
     * Set the callback invoked when the connection is closed by the remote end.
     * @param callback Called with the WebSocket close code and reason.
     * @returns This WebSocket, for chaining.
     */
    setCloseCallback(callback: (code: number, reason: string) => void): HSWebSocket;

    /**
     * Set the callback invoked when a connection or protocol error occurs.
     * @param callback Called with the error description.
     * @returns This WebSocket, for chaining.
     */
    setErrorCallback(callback: (error: string) => void): HSWebSocket;

    /**
     * Send a text message to the server.
The connection must be open (`readyState === 1`).
     * @param message The text message to send.
     * @returns This WebSocket, for chaining.
     */
    send(message: string): HSWebSocket;

    /**
     * Close the WebSocket connection with a normal closure code (1000).
If a close callback is registered, it is invoked synchronously.
     */
    close(): void;

    /**
     * Destroy this WebSocket, releasing all resources without invoking callbacks.
Called automatically by `hs.http.shutdown()`. After `destroy()`, do not use this object.
     */
    destroy(): void;

    /**
     * A unique identifier for this connection (UUID string).
     */
    readonly identifier: string;

    /**
     * The current connection state.
     */
    readonly readyState: number;

}

/**
 * Module for creating and managing HTTP servers.
Create a server with `hs.httpserver.create()`, configure it with chainable setters,
then call `start()`. The server accepts both synchronous and async (Promise-returning)
request handler callbacks.
## Quick start
```js
const server = hs.httpserver.create()
    .setPort(8080)
    .setCallback((method, path, headers, body) => {
        return {body: "<h1>Hello from Hammerspoon!</h1>", status: 200, headers: {"Content-Type": "text/html"}}
    })
    .start()
console.log("Listening on port " + server.getPort())
```
## Async callback
```js
server.setCallback(async (method, path, headers, body) => {
    const data = await hs.http.get("https://api.example.com/data")
    return {body: data.body, status: 200, headers: {"Content-Type": "application/json"}}
})
```
## Static file serving
```js
const server = hs.httpserver.create()
    .setPort(8080)
    .setDocumentRoot("/Users/me/Sites")
    .start()
```
## TLS (HTTPS)
```bash
openssl genrsa -out key.pem 2048
openssl req -new -x509 -key key.pem -out cert.pem -days 365
openssl pkcs12 -export -out identity.p12 -inkey key.pem -in cert.pem
```
```js
const server = hs.httpserver.create()
    .setPort(8443)
    .setTLSFromPKCS12("/path/to/identity.p12", "passphrase")
    .setCallback(handler)
    .start()
```
 */
declare namespace hs.httpserver {
    /**
     * Create a new HTTP server instance.
The server is not running until you call `start()` on the returned object.
     * @returns A new `HSHTTPServer` instance.
     */
    function create(): HSHTTPServer;

}

/**
 * An HTTP server instance created by `hs.httpserver.create()`.
Configure with chainable setter methods, then call `start()` to begin accepting connections.
The server supports synchronous and async (Promise-returning) request callbacks, optional
static file serving, HTTP Basic authentication, Bonjour advertisement, and TLS via PKCS#12.
Do not instantiate `HSHTTPServer` directly — use `hs.httpserver.create()`.
 */
declare class HSHTTPServer {
    /**
     * Set the TCP port to listen on. Must be called before `start()`.
Pass 0 to let the OS assign an available port (use `getPort()` after `start()` to discover it).
     * @param port TCP port number (0–65535).
     * @returns This server, for chaining.
     */
    setPort(port: number): HSHTTPServer;

    /**
     * Set the network interface to listen on.
Pass `null` to listen on all interfaces (the default). Pass `"localhost"` or `"loopback"`
to restrict to the loopback interface only.
     * @param iface Interface name or IP address string, or `null` for all interfaces.
     * @returns This server, for chaining.
     */
    setInterface(iface: string | null): HSHTTPServer;

    /**
     * Set a password required for Basic authentication.
When set, every request must supply an `Authorization: Basic` header with any
username and the configured password. Pass `null` to disable authentication.
     * @param password The required password, or `null` to remove authentication.
     * @returns This server, for chaining.
     */
    setPassword(password: string | null): HSHTTPServer;

    /**
     * Set the maximum allowed incoming request body size in bytes.
Requests with a body exceeding this limit receive a 413 response. Defaults to 10 MB.
     * @param size Maximum body size in bytes.
     * @returns This server, for chaining.
     */
    setMaxBodySize(size: number): HSHTTPServer;

    /**
     * Set the Bonjour service name advertised on the local network.
Only used when Bonjour is enabled via `setBonjour(true)`.
     * @param name The Bonjour service name.
     * @returns This server, for chaining.
     */
    setName(name: string): HSHTTPServer;

    /**
     * Enable or disable Bonjour advertisement of this server on the local network.
     * @param enable `true` to advertise via Bonjour, `false` to disable (default).
     * @returns This server, for chaining.
     */
    setBonjour(enable: boolean): HSHTTPServer;

    /**
     * Set the request handler callback.
If the callback returns `null` or `undefined`, the server falls through to static file serving
(if a document root is set), or responds with 404.
     * @param callback The request handler, or `null` to clear.
     * @returns This server, for chaining.
     */
    setCallback(callback: ((method: string, path: string, headers: object, body: string) => ({body: string, status: number, headers: object} | Promise<{body: string, status: number, headers: object}>)) | null): HSHTTPServer;

    /**
     * Set the filesystem path to serve static files from.
When a document root is set, requests not handled by the callback are served as
static files from this directory. Pass `null` to disable static file serving.
     * @param path Absolute path to a directory, or `null` to disable.
     * @returns This server, for chaining.
     */
    setDocumentRoot(path: string | null): HSHTTPServer;

    /**
     * Set the list of index filenames checked when a directory is requested.
Defaults to `["index.html", "index.htm"]`. Files are checked in order.
     * @param files Array of filename strings.
     * @returns This server, for chaining.
     */
    setDirectoryIndex(files: string[]): HSHTTPServer;

    /**
     * Enable or disable directory listing for requests that map to a directory with no index file.
When disabled (the default), directory requests without an index file return 403.
     * @param allow `true` to serve directory listings, `false` to return 403 (default).
     * @returns This server, for chaining.
     */
    setAllowDirectoryListing(allow: boolean): HSHTTPServer;

    /**
     * Configure TLS using a PKCS#12 (.p12) identity file.
When TLS is configured, the server accepts HTTPS connections. The `.p12` file must
contain both the certificate and the private key.
     * @param path Absolute path to the `.p12` file.
     * @param password The password protecting the `.p12` file.
     * @returns This server, for chaining.
     */
    setTLSFromPKCS12(path: string, password: string): HSHTTPServer;

    /**
     * Start the server and begin accepting connections.
The server must be configured before calling `start()`. To restart the server with new
settings, call `stop()` followed by `start()`.
     * @returns This server, for chaining.
     */
    start(): HSHTTPServer;

    /**
     * Stop the server and close all connections.
     * @returns This server, for chaining.
     */
    stop(): HSHTTPServer;

    /**
     * Destroy this server, releasing all resources.
After calling `destroy()`, the server object should not be used.
     */
    destroy(): void;

    /**
     * Get the TCP port the server is currently listening on.
Returns 0 if the server is not running.
     * @returns The TCP port number.
     */
    getPort(): number;

    /**
     * Get the configured Bonjour service name.
     * @returns The Bonjour service name.
     */
    getName(): string;

    /**
     * Get the configured network interface, or `null` if listening on all interfaces.
     * @returns The interface name or IP address string, or `null`.
     */
    getInterface(): string | null;

    /**
     * Register a WebSocket handler for a URL path.
When a client connects and performs a WebSocket upgrade handshake on `path`, the callback
is invoked with three arguments: `event` (string), `connection` (HSWebSocketConnection),
and `message` (string).
**Events:**
Pass `null` to remove the WebSocket handler for the path.
     * @param path The URL path to handle WebSocket connections on (e.g. `"/ws"`).
     * @param callback The event handler, or `null` to remove.
     * @returns This server, for chaining.
     */
    setWebSocketCallback(path: string, callback: ((event: string, connection: HSWebSocketConnection, message: string) => void) | null): HSHTTPServer;

    /**
     * A unique identifier for this server instance (UUID string).
     */
    readonly identifier: string;

}

/**
 * A WebSocket connection to a single client, passed to the callback registered with
`server.setWebSocketCallback()`.
Use `send()` to push messages to the connected client and `close()` to end the connection.
Do not instantiate `HSWebSocketConnection` directly — it is created by the server when a
client performs a WebSocket upgrade.
 */
declare class HSWebSocketConnection {
    /**
     * Send a text message to the connected WebSocket client.
     * @param message The text message to send.
     */
    send(message: string): void;

    /**
     * Close the WebSocket connection to the client.
Sends a WebSocket close frame and cancels the underlying TCP connection.
     */
    close(): void;

    /**
     * Destroy this connection object, releasing all resources.
     */
    destroy(): void;

    /**
     * A unique identifier for this connection (UUID string).
     */
    readonly identifier: string;

}

/**
 * Access information about the current keyboard layout and input sources, and respond to changes.
## Reading the current layout
```js
console.log("Layout: " + hs.keycodes.currentLayout())
console.log("Source ID: " + hs.keycodes.currentSourceID())
```
## Key code mapping
```js
// Look up a keycode by name
const code = hs.keycodes.map["a"]    // e.g. 0 on ANSI US
// Look up a name by keycode
const name = hs.keycodes.map["0"]   // e.g. "a"
```
## Switching layouts
```js
hs.keycodes.setLayout("British")
```
## Watching for input source changes
```js
hs.keycodes.addWatcher(() => {
    console.log("Switched to: " + hs.keycodes.currentLayout())
})
```
 */
declare namespace hs.keycodes {
    /**
     * Returns the localized name of the current keyboard layout.
Uses the base keyboard layout, which is the underlying layout even when an input
method (such as a CJK input method) is also active.
     * @returns The display name of the active layout (e.g. `"U.S."`, `"British"`), or `null`.
     */
    function currentLayout(): string | null;

    /**
     * Returns the localized name of the active input method, or `null` if none is active.
Input methods are distinct from keyboard layouts. They provide complex character
composition such as CJK input. Returns `null` when using a plain keyboard layout
with no input method overlay.
     * @returns The display name of the active input method (e.g. `"Hiragana"`), or `null`.
     */
    function currentMethod(): string | null;

    /**
     * Returns the reverse-DNS identifier of the currently selected keyboard input source.
     * @returns A string such as `"com.apple.keylayout.US"`, or `null` if unavailable.
     */
    function currentSourceID(): string | null;

    /**
     * Returns the localized names of all currently enabled keyboard layouts.
     * @returns An array of layout name strings (e.g. `["U.S.", "British", "French"]`).
     */
    function layouts(): string[];

    /**
     * Returns the localized names of all currently enabled input methods.
     * @returns An array of input method name strings. May be empty if none are enabled.
     */
    function methods(): string[];

    /**
     * Switches the active keyboard layout to the one with the given localized name.
Use `layouts()` to enumerate valid names.
     * @param layoutName The localized name of the layout to activate (e.g. `"U.S."`).
     * @returns `true` if the layout was found and selected, `false` otherwise.
     */
    function setLayout(layoutName: string): boolean;

    /**
     * Switches the active input method to the one with the given localized name.
Use `methods()` to enumerate valid names.
     * @param methodName The localized name of the input method to activate.
     * @returns `true` if the method was found and selected, `false` otherwise.
     */
    function setMethod(methodName: string): boolean;

    /**
     * Switches the active input source to the one with the given reverse-DNS identifier.
Use `currentSourceID()` to see the current value.
     * @param sourceID The input source ID to activate (e.g. `"com.apple.keylayout.British"`).
     * @returns `true` if the source was found and selected, `false` otherwise.
     */
    function setSourceID(sourceID: string): boolean;

    /**
     * Registers a listener that fires whenever the keyboard input source changes.
The listener is called with no arguments. Read `currentLayout()`, `currentSourceID()`,
or `map` inside the callback to inspect the new state.
The OS subscription starts lazily on the first listener and is released automatically
when the last listener is removed via `removeWatcher`.
     * @param listener A function called when the input source changes.
     */
    function addWatcher(listener: () => void): void;

    /**
     * Removes a previously registered input source change listener.
     * @param listener The function originally passed to `addWatcher`.
     */
    function removeWatcher(listener: (...args: any[]) => any): void;

    /**
     * A bidirectional mapping between key names and their macOS virtual key codes.
Entries exist for both directions: look up a name to get its integer keycode, or look
up a keycode (as a string) to get the key name. The map is rebuilt automatically
whenever the keyboard input source changes.
     */
    const map: Record<string, any>;

}

/**
 * Determine the Mac's location via macOS Location Services.
Location data is obtained through WiFi network scanning and, where available, GPS
hardware. User permission is required — call `hs.permissions.requestLocation()`
before using any tracking features.
The module exposes a `geocoder` sub-object for forward/reverse geocoding without
requiring Location Services.
## locationTable
| Key | Type | Description |
|-----|------|-------------|
| `latitude` | number | Degrees north (positive) or south (negative) |
| `longitude` | number | Degrees east (positive) or west (negative) |
| `altitude` | number | Metres above sea level (`0` if unknown) |
| `horizontalAccuracy` | number | Uncertainty radius in metres (`-1` if invalid) |
| `verticalAccuracy` | number | Altitude accuracy in metres (`-1` if invalid) |
| `course` | number | Direction of travel in degrees (`-1` if invalid) |
| `speed` | number | Metres per second (`-1` if invalid) |
| `timestamp` | number | Seconds since the Unix epoch |
 */
declare namespace hs.location {
    /**
     * Geocodes an address string into an array of placemarkTables.
Returns a Promise that resolves with an array of placemarkTable objects
(sorted by relevance) or rejects with an error message.
     * @param address a free-form address string in any locale
     * @returns a Promise resolving to an array of placemarkTables
     */
    function lookupAddress(address: string): Promise<Record<string, any>[]>;

    /**
     * Reverse-geocodes a locationTable into an array of placemarkTables.
Returns a Promise that resolves with matching placemarks or rejects with
an error.
     * @param locationTable an object with at least `latitude` and `longitude`
     * @returns a Promise resolving to an array of placemarkTables
     */
    function lookupLocation(locationTable: Record<string, number>): Promise<Record<string, any>[]>;

    /**
     * Returns true if Location Services are enabled system-wide.
     * @returns true if enabled, false otherwise
     */
    function servicesEnabled(): boolean;

    /**
     * Returns the app's current Location Services authorization status as a string.
     * @returns `"authorized"`, `"denied"`, `"restricted"`, or `"notDetermined"`
     */
    function authorizationStatus(): string;

    /**
     * Returns the most recently cached location as a locationTable, or null.
Activates Location Services if not already running. The cache is updated
periodically while any watcher is running.
     * @returns a locationTable, or null if no cached location is available
     */
    function get(): Record<string, any> | null;

    /**
     * Calculates the straight-line distance in metres between two locationTables.
Does not require Location Services.
     * @param from locationTable with at least `latitude` and `longitude`
     * @param to locationTable with at least `latitude` and `longitude`
     * @returns distance in metres, or `-1` if either table is invalid
     */
    function distance(from: Record<string, number>, to: Record<string, number>): number;

    /**
     * Returns the time of sunrise for the given coordinates and date, or null if the sun does not rise on that date (polar night).
     * @param latitude degrees north (positive) or south (negative)
     * @param longitude degrees east (positive) or west (negative)
     * @param date the date to calculate for; pass null or omit to use today
     * @returns A Date object representing the time of sunrise, or null
     */
    function sunrise(latitude: number, longitude: number, date: Date | null): Date | null;

    /**
     * Returns the time of sunset for the given coordinates and date, or null if the sun does not set on that date (midnight sun).
     * @param latitude degrees north (positive) or south (negative)
     * @param longitude degrees east (positive) or west (negative)
     * @param date the date to calculate for; pass null or omit to use today
     * @returns A Date object representing the time of sunset, or null
     */
    function sunset(latitude: number, longitude: number, date: Date | null): Date | null;

    /**
     * Creates a new location watcher object. Call `.start()` on it to begin
receiving updates. The watcher is automatically stopped when the module
shuts down.
     * @returns an HSLocationWatcher
     */
    function addWatcher(): HSLocationWatcher;

    /**
     * Removes a previously created watcher and stops it if running.
     * @param watcher the watcher returned by `addWatcher()`
     */
    function removeWatcher(watcher: HSLocationWatcher): void;

}

/**
 * An independent location tracking object.
Create via `hs.location.addWatcher()`. Call `start()` to begin receiving
updates, and set a callback to handle them.
| Event | Data |
|-------|------|
| `"location"` | a locationTable |
| `"error"` | an error message string |
| `"authorizationChanged"` | the new status string (`"authorized"`, `"denied"`, `"restricted"`, `"notDetermined"`) |
 */
declare class HSLocationWatcher {
    /**
     * Starts location updates. The callback must be set first.
     * @returns self, for chaining
     */
    start(): HSLocationWatcher;

    /**
     * Stops location updates.
     * @returns self, for chaining
     */
    stop(): HSLocationWatcher;

    /**
     * Sets the callback function invoked when location events occur.
     * @param fn Called with the event name and associated data; see type documentation for event names
     * @returns self, for chaining
     */
    setCallback(fn: (event: string, data: Record<string, any>) => void): HSLocationWatcher;

    /**
     * Returns the most recently received location, or null if none yet.
     * @returns a locationTable, or null
     */
    location(): Record<string, any> | null;

    /**
     * The unique identifier assigned to this watcher.
     */
    readonly identifier: string;

    /**
     * The minimum distance in metres the device must move before a new update
is delivered. Defaults to `kCLDistanceFilterNone` (all movements reported).
     */
    distanceFilter: number;

}

/**
 * Module for creating and managing macOS system menu bar items.
Menu bar items appear in the right side of the macOS menu bar (alongside the clock, Wi-Fi icon, etc.).
Each item can display a title, an icon, or both, and can open a menu or invoke a callback when clicked.
## Creating a simple title item
```js
const item = hs.menubar.create()
item.title = "Hello"
item.setClickCallback(() => console.log("clicked!"))
```
## Creating an icon item with a static menu
```js
const item = hs.menubar.create()
item.setIcon(HSImage.fromSymbol("star.fill"))
item.setTooltip("My automation")
item.setMenu([
    { title: "Reload config", fn: () => hs.reload() },
    { title: "-" },
    { title: "Remove from menubar", fn: () => item.hide() }
])
```
## Creating an item with a dynamic menu
```js
const item = hs.menubar.create()
item.title = "Dynamic"
item.setMenu(() => [
    { title: "Time: " + new Date().toLocaleTimeString() },
    { title: "-" },
    { title: "Remove from menubar", fn: () => item.hide() }
])
```
 */
declare namespace hs.menubar {
    /**
     * Create a new menu bar item
     * @param hidden Pass true to create the item hidden (not shown in the menu bar). Defaults to false (immediately visible).
     * @returns A new HSMenuBarItem
     */
    function create(hidden?: boolean): HSMenuBarItem;

}

/**
 * Object representing a macOS system menu bar item.
Create instances with `hs.menubar.create()`.
 */
declare class HSMenuBarItem {
    /**
     * Set the icon displayed in the menu bar
     * @param image An HSImage object, or null to remove the icon
     */
    setIcon(image: HSImage | null): void;

    /**
     * Set the tooltip shown when hovering over the menu bar item
     * @param tooltip Tooltip text, or null to remove the tooltip
     */
    setTooltip(tooltip: string | null): void;

    /**
     * Set a callback invoked when the item is clicked (only fires when no menu is set)
     * @param fn A function to call on click, or null to remove the callback
     */
    setClickCallback(fn: (() => void) | null): void;

    /**
     * Set the menu for this item. Pass an array of menu item objects for a static menu,
or a function that returns an array for a dynamic menu populated each time it opens.
     * @param menuOrFn Array of menu item objects, a function returning such an array, or null to remove the menu
     */
    setMenu(menuOrFn: Array<Record<string, any>> | (() => Array<Record<string, any>>) | null): void;

    /**
     * Remove this item from the menu bar. The item is retained and can be shown again with show().
     */
    hide(): void;

    /**
     * Show this item in the menu bar.
     */
    show(): void;

    /**
     * Check if this item is currently visible in the menu bar.
     * @returns true if the item is visible in the menu bar
     */
    isVisible(): boolean;

    /**
     * Get or set the menu item's title.
     */
    title: string | null;

}

/**
 * Module for creating and displaying macOS system notifications.
macOS notifications require user permission before they will appear. Request it once
(typically at startup) via `hs.permissions.requestNotifications()` and it will be
```js
hs.permissions.requestNotifications().then(granted => {
    if (granted) hs.notify.show("Hammerspoon", "Notifications are enabled!")
})
```
## Quick notification
```js
// Fire and forget
hs.notify.show("Build complete", "Your project compiled successfully.")

// With a callback invoked when the user interacts
hs.notify.show("Build complete", "Click to view the log.", (response) => {
    console.log("User tapped:", response.actionIdentifier)
})
```
## Rich notification
```js
const n = hs.notify.create({
    title:    "New message",
    subtitle: "From Alice",
    body:     "Are you free tonight?",
    sound:    true,
    threadIdentifier: "messages-alice",
    actions: [
        { identifier: "REPLY", title: "Reply", textInput: true,
          textInputButtonTitle: "Send", textInputPlaceholder: "Type a reply…" },
        { identifier: "DISMISS", title: "Dismiss", destructive: true }
    ],
    callback: (response) => {
        if (response.actionIdentifier === "REPLY") {
            console.log("Reply text:", response.userText)
        }
    }
})
n.send()
// Later, if needed:
n.withdraw()
```
## Callback response object
| Property | Type | Description |
|----------|------|-------------|
| `actionIdentifier` | string | `"DEFAULT"` when the user tapped the notification body; `"DISMISS"` when dismissed (if `.customDismissAction` is set); otherwise the action's `identifier` string |
| `userText` | string? | Text entered in a `textInput` action; only present when applicable |
| `userInfo` | object | The `userInfo` object originally passed to `create()`, if any |
| `notificationId` | string | The notification's unique identifier |
## Options for `create()`
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `title` | string | *(required)* | The bold heading line |
| `subtitle` | string | — | A second line shown beneath the title |
| `body` | string | — | The main message body |
| `sound` | boolean \| string | `true` | `true` = default sound, `false` = no sound, string = named `.aiff` file |
| `badge` | number | — | Value to show on the app icon badge |
| `threadIdentifier` | string | — | Groups related notifications visually in Notification Center |
| `userInfo` | object | `{}` | Arbitrary payload passed back to the callback |
| `interruptionLevel` | string | `"active"` | `"passive"`, `"active"`, or `"timeSensitive"` — controls Focus/DND behaviour (macOS 12+) |
| `trigger` | object | — | When to deliver the notification (see below). Omit for immediate delivery. |
| `actions` | array | — | Action buttons (see below) |
| `callback` | function | — | Invoked when the user interacts with the notification |
## Triggers
Pass a `trigger` object in `create()`'s options to schedule the notification instead of delivering it
```js
trigger: { type: "timeInterval", interval: 300 }
```
**Calendar** — deliver at a specific date/time. Provide either a JS `Date` object or individual
```js
// At a specific moment
trigger: { type: "calendar", date: new Date("2026-06-01T09:00:00") }

// At 09:00 on the next day that matches (e.g. next Monday, weekday 2)
trigger: { type: "calendar", weekday: 2, hour: 9, minute: 0 }
```
Supported component keys: `year`, `month`, `day`, `hour`, `minute`, `second`, `weekday`.
## Action objects
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `identifier` | string | *(required)* | Unique identifier passed to the callback |
| `title` | string | *(required)* | Button label |
| `destructive` | boolean | `false` | Renders the title in a destructive (red) style |
| `foreground` | boolean | `false` | Brings Hammerspoon to the foreground when tapped |
| `textInput` | boolean | `false` | Converts this action to an inline text-reply button |
| `textInputButtonTitle` | string | `"Send"` | Label on the reply send button (requires `textInput: true`) |
| `textInputPlaceholder` | string | `""` | Placeholder shown in the text field (requires `textInput: true`) |
 */
declare namespace hs.notify {
    /**
     * Display a notification immediately.
     * @param title The notification title
     * @param body The notification body text
     * @param callback Optional function called when the user taps the notification. Receives a response object (see module docs for shape).
     */
    function show(title: string, body: string, callback: (response: Record<string, any>) => void): void;

    /**
     * Create a richly configured notification without sending it yet.
     * @param options A JavaScript object — see module documentation for supported keys.
     * @returns An `HSNotification` object. Call `.send()` on it to deliver the notification.
     */
    function create(options: Record<string, any>): HSNotification | null;

    /**
     * Remove all delivered Hammerspoon notifications from Notification Center.
     */
    function removeAllDelivered(): void;

    /**
     * Cancel all pending (not yet delivered) Hammerspoon notifications.
     */
    function removeAllPending(): void;

}

/**
 * A notification created by `hs.notify.new()`.
Call `.send()` to deliver it to macOS Notification Center. You can hold a reference
to the object and call `.withdraw()` later to remove it.
 */
declare class HSNotification {
    /**
     * Deliver this notification immediately to Notification Center.
     * @returns self, for method chaining
     */
    send(): HSNotification;

    /**
     * Remove this notification from Notification Center (if delivered) or cancel it (if pending).
     */
    withdraw(): void;

    /**
     * The unique identifier assigned to this notification.
Use it to correlate with system notification APIs if needed.
     */
    readonly identifier: string;

}

/**
 * Recognize text in images using Apple's Vision framework.
`hs.ocr` provides access to on-device text recognition without requiring
network access or any third-party dependencies. Pass a file path to
`recognizeText()` and receive back an `HSOCRResult` containing the full
recognized text and individual per-region observations with confidence
scores and normalized bounding boxes.
 */
declare namespace hs.ocr {
    /**
     * Recognize text in the image at the given file path.
Returns a Promise that resolves with an `HSOCRResult` containing all
recognized text and per-region observations. The image must exist on
disk; URLs and data buffers are not supported.
Recognition is performed on a background thread; the main thread is
not blocked during the operation.
`"accurate"` uses a larger neural network for better results;
`"fast"` trades accuracy for speed.
Observations whose `confidence` is below this threshold are excluded
from `result.observations` (and therefore from `result.text`).
Hints Vision toward specific languages. Use `supportedLanguages()` to
enumerate the available codes for the current device.
When `true`, Vision selects recognition languages automatically.
Overrides `languages` when set.
     * @param path Absolute path to the image file.
     * @param options Optional configuration object (see description).
     * @returns Resolves with the recognition result.
     */
    function recognizeText(path: string, options: Record<string, any> | null): Promise<HSOCRResult>;

    /**
     * Returns the BCP-47 language codes supported by the Vision text recognizer
on this device.
The set of languages varies between macOS versions and hardware. Call
this at runtime to discover which codes are valid for the `languages`
option passed to `recognizeText()`.
     * @returns An array of BCP-47 language code strings (e.g. `["en-US", "fr-FR"]`).
     */
    function supportedLanguages(): string[];

}

/**
 * A single region of text recognized in an image.
Instances are delivered inside the `observations` array of an `HSOCRResult`.
Each observation represents a discrete text run found in the source image,
along with a confidence score and a normalized bounding box.
`(0, 0)` is the top-left corner of the image and `(1, 1)` is the bottom-right.
This matches the convention used by most image-processing tools and differs
from Vision's internal bottom-left-origin system (the conversion is automatic).
 */
declare class HSOCRObservation {
    /**
     * The Swift type name, for JavaScript introspection.
     */
    readonly typeName: string;

    /**
     * The recognized text string for this observation.
     */
    readonly text: string;

    /**
     * Recognition confidence in the range `0.0` (uncertain) to `1.0` (certain).
Use `minimumConfidence` in the options passed to `recognizeText()` to
pre-filter observations below a threshold rather than filtering here.
     */
    readonly confidence: number;

    /**
     * Normalized bounding box of this observation in the source image, as an `HSRect`.
All values are in the range 0–1 with **top-left origin**
(`(0, 0)` = top-left corner, `(1, 1)` = bottom-right corner).
Use `bounds.x`, `bounds.y`, `bounds.w`, and `bounds.h` to access the components.
     */
    readonly bounds: HSRect;

}

/**
 * The result of a text recognition operation on an image.
An `HSOCRResult` is returned by `hs.ocr.recognizeText()` and bundles the
full recognized text together with an array of per-region observations,
each carrying its own confidence score and bounding box.
 */
declare class HSOCRResult {
    /**
     * The Swift type name, for JavaScript introspection.
     */
    readonly typeName: string;

    /**
     * The full recognized text from the image, with each observation's text
joined by newlines in the order Vision returned them.
Use this when you only need the raw text and don't care about bounding
boxes or per-region confidence scores.
     */
    readonly text: string;

    /**
     * The individual text observations that make up this result.
Each entry in the array is an `HSOCRObservation` with its own `text`,
`confidence`, and `bounds` properties. Observations are returned in the
order Vision produced them (typically top-to-bottom, left-to-right, but
this is image-dependent).
     */
    readonly observations: HSOCRObservation[];

}

/**
 * Run AppleScript and OSA JavaScript from Hammerspoon scripts.
Script execution is isolated in a separate XPC helper process
(`HammerspoonOSAScriptHelper`). If a script crashes or deadlocks, only the
helper is affected — the main app remains stable and the next call
reconnects automatically.
## Async API (Promise-based)
Every async function returns a `Promise` that **always resolves** (never rejects)
| Field | Type | Description |
|-------|------|-------------|
| `success` | `Boolean` | `true` if the script ran without error |
| `result` | `any` | Parsed return value of the script, or `null` on failure |
| `raw` | `String` | Raw string representation of the result, or the error message on failure |
## Sync API
The `*Sync` variants block until the script completes and return the same
`{ success, result, raw }` object directly.  Use these only when a Promise
chain is impractical; they block the JS thread for the duration of the call.
The `result` field is typed based on what the script returned: strings,
numbers, booleans, lists, and records are all mapped to their JavaScript
equivalents. `null` is used for AppleScript's `missing value` and for any
failure case.
## Examples
**Return a string (async):**
```javascript
hs.osascript.applescript('return "hello"')
  .then(r => console.log(r.result));  // "hello"
```
**Return a string (sync):**
```javascript
const r = hs.osascript.applescriptSync('return "hello"');
console.log(r.result);  // "hello"
```
**Interact with an application:**
```javascript
hs.osascript.applescript('tell application "Finder" to get name of home')
  .then(r => console.log(r.result));  // e.g. "cmsj"
```
**Handle errors (the Promise never rejects — check `success`):**
```javascript
hs.osascript.applescript('this is not valid')
  .then(r => {
    if (!r.success) console.log("Error:", r.raw);
  });
```
**OSA JavaScript:**
```javascript
hs.osascript.javascript('Application("Finder").name()')
  .then(r => console.log(r.result));  // "Finder"
```
**Run a script from a file:**
```javascript
hs.osascript.applescriptFromFile('/Users/me/scripts/notify.applescript')
  .then(r => console.log(r.success));
```
 */
declare namespace hs.osascript {
    /**
     * Run an AppleScript source string.
     * @param source The AppleScript source code to compile and execute.
     * @returns A `Promise` resolving to `{ success, result, raw }`.
     */
    function applescript(source: string): Promise<any>;

    /**
     * Run an OSA JavaScript source string.
OSA JavaScript is Apple's Open Scripting Architecture dialect of
JavaScript, distinct from the JavaScriptCore engine that runs
Hammerspoon scripts themselves.
     * @param source The OSA JavaScript source code to compile and execute.
     * @returns A `Promise` resolving to `{ success, result, raw }`.
     */
    function javascript(source: string): Promise<any>;

    /**
     * Read a file from disk and execute its contents as AppleScript.
The file is read in the main process before being sent to the XPC
helper. If the file cannot be read the promise resolves immediately
with `{ success: false, result: null, raw: "Failed to read file: <path>" }`.
     * @param path Absolute path to the AppleScript source file.
     * @returns A `Promise` resolving to `{ success, result, raw }`.
     */
    function applescriptFromFile(path: string): Promise<any>;

    /**
     * Read a file from disk and execute its contents as OSA JavaScript.
The file is read in the main process before being sent to the XPC
helper. If the file cannot be read the promise resolves immediately
with `{ success: false, result: null, raw: "Failed to read file: <path>" }`.
     * @param path Absolute path to the OSA JavaScript source file.
     * @returns A `Promise` resolving to `{ success, result, raw }`.
     */
    function javascriptFromFile(path: string): Promise<any>;

    /**
     * Low-level execution entry point used by the higher-level helpers.
Prefer `applescript()` or `javascript()` over calling this directly.
     * @param source The script source code.
     * @param language The OSA language name — must be `"AppleScript"` or `"JavaScript"`.
     * @returns A `Promise` resolving to `{ success, result, raw }`.
     */
    function _execute(source: string, language: string): Promise<any>;

    /**
     * Run an AppleScript source string synchronously.
Blocks the JS thread until the script completes.
     * @param source The AppleScript source code to compile and execute.
     * @returns An object `{ success, result, raw }`, or `null` on XPC failure.
     */
    function applescriptSync(source: string): Record<string, any> | null;

    /**
     * Run an OSA JavaScript source string synchronously.
Blocks the JS thread until the script completes.
     * @param source The OSA JavaScript source code to compile and execute.
     * @returns An object `{ success, result, raw }`, or `null` on XPC failure.
     */
    function javascriptSync(source: string): Record<string, any> | null;

    /**
     * Read a file from disk and execute its contents as AppleScript synchronously.
     * @param path Absolute path to the AppleScript source file.
     * @returns An object `{ success, result, raw }`, or `null` on XPC failure.
     */
    function applescriptSyncFromFile(path: string): Record<string, any> | null;

    /**
     * Read a file from disk and execute its contents as OSA JavaScript synchronously.
     * @param path Absolute path to the OSA JavaScript source file.
     * @returns An object `{ success, result, raw }`, or `null` on XPC failure.
     */
    function javascriptSyncFromFile(path: string): Record<string, any> | null;

    /**
     * Low-level synchronous execution entry point.
Prefer `applescriptSync()` or `javascriptSync()` over calling this directly.
     * @param source The script source code.
     * @param language The OSA language name — must be `"AppleScript"` or `"JavaScript"`.
     * @returns An object `{ success, result, raw }`, or `null` on XPC failure.
     */
    function _executeSync(source: string, language: string): Record<string, any> | null;

}

/**
 * Module for interacting with the macOS pasteboard (clipboard)
The macOS pasteboard is "rich" — a single clipboard operation can carry multiple representations
of the same content for different applications to consume. For example, text copied from a web
browser may carry plain text, HTML, and RTF representations simultaneously.
## Basic Usage
```js
// Read and write plain text
const text = hs.pasteboard.readString()
hs.pasteboard.writeString("Hello from Hammerspoon!")

// Check what types are currently on the pasteboard
const available = hs.pasteboard.types()

// Write multiple representations at once
hs.pasteboard.writeObjects({
    "public.utf8-plain-text": "Hello",
    "public.html": "<b>Hello</b>"
})

// Watch for pasteboard changes
const handler = (changeCount) => {
    console.log("Pasteboard changed, count:", changeCount)
    console.log("New text:", hs.pasteboard.readString())
}
hs.pasteboard.addWatcher(handler)
// Later: hs.pasteboard.removeWatcher(handler)
```
## Pasteboard Conventions (nspasteboard.org)
macOS has no built-in notification API for transient or confidential clipboard content, so a
community convention has emerged (see [nspasteboard.org](https://nspasteboard.org)) around four
`org.nspasteboard.*` UTI marker types. These markers carry no payload — their mere presence on
the pasteboard signals intent to other applications.
### Standard marker UTIs
| UTI | Meaning |
|-----|---------|
| `org.nspasteboard.TransientType` | Content is temporary; it will be removed or overwritten shortly. Clipboard historians should **not** record this change. |
| `org.nspasteboard.ConcealedType` | Content is sensitive (e.g. a password). Historians should obfuscate it if displayed and ideally encrypt it if stored. |
| `org.nspasteboard.AutoGeneratedType` | Content was placed by an application without any user Copy action. Historians should generally skip recording it. |
| `org.nspasteboard.source` | The bundle identifier of the application that placed the content. Use an empty string when the source is unknown. |
### Legacy proprietary markers
Several apps defined their own markers before the `org.nspasteboard.*` standard existed.
| UTI | Application |
|-----|-------------|
| `de.petermaurer.TransientPasteboardType` | TextExpander, Butler |
| `com.typeit4me.clipping` | TypeIt4Me |
| `Pasteboard generator type` | Typinator |
| `com.agilebits.onepassword` | 1Password (confidential) |
| `com.apple.is-remote-clipboard` | macOS (remote content) |
### For scripts that write to the pasteboard
If your script temporarily commandeers the pasteboard (e.g. to trigger a paste), add
```js
hs.pasteboard.writeObjects({
    "public.utf8-plain-text": "temporary value",
    "org.nspasteboard.TransientType": ""
})
```
```js
hs.pasteboard.writeObjects({
    "public.utf8-plain-text": "s3cr3t!",
    "org.nspasteboard.ConcealedType": ""
})
```
### For scripts that monitor the pasteboard
If you are building a clipboard history tool with `addWatcher`, skip or obfuscate entries that
```js
const SKIP_TYPES = [
    "org.nspasteboard.TransientType",
    "org.nspasteboard.AutoGeneratedType",
    "de.petermaurer.TransientPasteboardType",
    "com.typeit4me.clipping",
    "Pasteboard generator type",
]
const CONCEAL_TYPES = [
    "org.nspasteboard.ConcealedType",
    "com.agilebits.onepassword",
]

hs.pasteboard.addWatcher((changeCount) => {
    const types = hs.pasteboard.types()
    if (SKIP_TYPES.some(t => types.includes(t))) return        // ignore transient
    const conceal = CONCEAL_TYPES.some(t => types.includes(t)) // handle sensitively
    // … record or display the pasteboard contents …
})
```
 */
declare namespace hs.pasteboard {
    /**
     * Read plain text from the pasteboard
     * @returns The plain text string, or null if not available
     */
    function readString(): string | null;

    /**
     * Read HTML from the pasteboard
     * @returns The HTML string, or null if not available
     */
    function readHTML(): string | null;

    /**
     * Read RTF from the pasteboard
     * @returns The RTF string, or null if not available
     */
    function readRTF(): string | null;

    /**
     * Read a URL from the pasteboard
     * @returns The URL as a string, or null if not available
     */
    function readURL(): string | null;

    /**
     * Read an image from the pasteboard
     * @returns An HSImage, or null if not available
     */
    function readImage(): HSImage | null;

    /**
     * Read raw data for a specific UTI type, returned as a base64-encoded string.
Use this for types not covered by the convenience read methods.
     * @param uti A UTI type string (e.g. "com.adobe.pdf")
     * @returns A base64-encoded string, or null if the type is not available
     */
    function readData(uti: string): string | null;

    /**
     * Write plain text to the pasteboard, replacing all current contents
     * @param str The text string to write
     * @returns true if the write succeeded
     */
    function writeString(str: string): boolean;

    /**
     * Write HTML to the pasteboard, replacing all current contents
     * @param html The HTML string to write
     * @returns true if the write succeeded
     */
    function writeHTML(html: string): boolean;

    /**
     * Write RTF to the pasteboard, replacing all current contents
     * @param rtf The RTF string to write
     * @returns true if the write succeeded
     */
    function writeRTF(rtf: string): boolean;

    /**
     * Write a URL to the pasteboard, replacing all current contents
     * @param url The URL string to write
     * @returns true if the write succeeded
     */
    function writeURL(url: string): boolean;

    /**
     * Write an image to the pasteboard, replacing all current contents
     * @param image An HSImage to write
     * @returns true if the write succeeded
     */
    function writeImage(image: HSImage): boolean;

    /**
     * Write raw base64-encoded data for a specific UTI type, replacing all current contents.
Use this for types not covered by the convenience write methods.
     * @param base64 The data encoded as a base64 string
     * @param uti A UTI type string (e.g. "com.adobe.pdf")
     * @returns true if the write succeeded
     */
    function writeData(base64: string, uti: string): boolean;

    /**
     * Write multiple type representations to the pasteboard atomically, replacing all current contents.
Keys must be UTI type strings; values must be strings. This is how you provide both a plain-text
fallback and a richer representation (such as HTML) in a single clipboard operation.
     * @param representations A JavaScript object whose keys are UTI strings and values are strings
     * @returns true if the write succeeded
     */
    function writeObjects(representations: Record<string, any>): boolean;

    /**
     * Get all UTI type strings currently on the pasteboard, across all items
     * @returns An array of UTI strings (e.g. ["public.utf8-plain-text", "public.html"])
     */
    function types(): string[];

    /**
     * Check whether a specific UTI type is currently available on the pasteboard
     * @param uti A UTI type string to check for
     * @returns true if the type is available
     */
    function hasType(uti: string): boolean;

    /**
     * Clear all contents from the pasteboard
     */
    function clear(): void;

    /**
     * Add a watcher that is called whenever the pasteboard contents change.
Multiple watchers may be registered; they are each called independently.
Because macOS provides no pasteboard change notification API, this is implemented
by polling `changeCount` at the interval specified by `watcherInterval`.
     * @param listener A function called with the new `changeCount` integer whenever the pasteboard changes
     */
    function addWatcher(listener: (changeCount: number) => void): void;

    /**
     * Remove a previously registered pasteboard watcher
     * @param listener The function previously passed to `addWatcher`
     */
    function removeWatcher(listener: (...args: any[]) => any): void;

    /**
     * The pasteboard change count. Increments each time any application writes to the pasteboard.
Comparing a saved value to the current value is the standard way to detect external changes.
     */
    const changeCount: number;

    /**
     * The polling interval for the pasteboard watcher, in seconds. Defaults to 0.5.
Changes take effect the next time a watcher is started (i.e. after removing and re-adding).
     */
    let watcherInterval: number;

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
     * @remarks This will trigger a screen capture which prompts the system dialog
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

    /**
     * Check if the app has permission to display notifications.
The result is cached from the last request or check; the cache is refreshed asynchronously,
so the very first call in a session may return `false` before the cached value is populated.
Use `requestNotifications()` on first launch to ensure the result is accurate.
     * @returns true if notification permission is granted
     */
    function checkNotifications(): boolean;

    /**
     * Request notification permission (shows the system dialog if the user has not yet decided).
It is safe to call this on every launch — the dialog only appears once; subsequent calls
resolve immediately with the previously granted or denied state.
     * @returns A Promise that resolves to true if granted, false if denied
     */
    function requestNotifications(): Promise<boolean>;

    /**
     * Check if the app has Location permission.
     * @returns true if permission is granted, false otherwise
     */
    function checkLocation(): boolean;

    /**
     * Request Location permission (shows the system dialog if the user has not yet decided).
     * @returns A Promise that resolves to true if granted, false if denied
     */
    function requestLocation(): Promise<boolean>;

}

/**
 * Monitor and control system power: prevent sleep, read battery state, respond to
power events, and lock or sleep the machine.
## Preventing sleep
```js
// Prevent the display from sleeping while a task runs
hs.power.preventSleep("display")
// ... do work ...
hs.power.allowSleep("display")
```
## Watching for system events
```js
hs.power.addEventWatcher(event => {
    if (event === "screensDidLock") console.log("Screen locked!")
})
```
## Reading battery state
```js
const info = hs.power.batteryInfo()
if (info) {
    console.log(`Battery: ${info.percentage}%, ${info.timeRemaining} minutes remaining`)
}
```
 */
declare namespace hs.power {
    /**
     * Prevents the specified type of system sleep.
Creates an IOKit power assertion that stops macOS from allowing the specified
type of sleep. Call `allowSleep` with the same type to release the assertion.
idle sleep), `"systemIdle"` (prevent system idle sleep), `"system"` (prevent
all system sleep, including from power button or lid close).
     * @param type The sleep type to prevent. One of: `"display"` (prevent display
     * @returns `true` if the assertion was created successfully.
     */
    function preventSleep(type: string): boolean;

    /**
     * Releases a previously created sleep prevention assertion.
     * @param type The sleep type to allow again. One of: `"display"`, `"systemIdle"`, `"system"`.
     * @returns `true` if an assertion existed and was released, `false` if none was active.
     */
    function allowSleep(type: string): boolean;

    /**
     * Returns whether Hammerspoon is currently preventing the specified type of sleep.
     * @param type The sleep type to check. One of: `"display"`, `"systemIdle"`, `"system"`.
     * @returns `true` if this sleep type is currently being prevented.
     */
    function isSleepPrevented(type: string): boolean;

    /**
     * Simulates user activity, briefly resetting the display idle timer.
Equivalent to moving the mouse — does not create a persistent assertion.
     */
    function declareActivity(): void;

    /**
     * Returns the active power management assertions from all processes on the system.
     * @returns An array of objects with `pid` (number), `name` (string), and `type` (string) properties.
     */
    function currentAssertions(): Record<string, any>[];

    /**
     * Puts the system to sleep immediately.
Requires the Automation permission for System Events.
     */
    function systemSleep(): void;

    /**
     * Locks the screen immediately.
     */
    function lockScreen(): void;

    /**
     * Starts the screensaver immediately.
     */
    function startScreensaver(): void;

    /**
     * Returns a snapshot of all available battery information, or `null` if no battery is present.
     * @returns An object with battery fields, or `null` if no battery is present.
     */
    function batteryInfo(): Record<string, any> | null;

    /**
     * Registers a listener that fires when system power events occur.
`"screensDidSleep"`, `"screensDidWake"`, `"screensDidLock"`, `"screensDidUnlock"`,
`"screensaverDidStart"`, `"screensaverDidStop"`, `"screensaverWillStop"`,
`"systemWillSleep"`, `"systemDidWake"`, `"systemWillPowerOff"`,
`"sessionDidBecomeActive"`, `"sessionDidResignActive"`.
The OS notification subscription starts lazily on the first listener and
is released automatically when the last listener is removed.
     * @param listener A function called with the power event name string.
     */
    function addEventWatcher(listener: (eventName: string) => void): void;

    /**
     * Removes a previously registered power event listener.
     * @param listener The function originally passed to `addEventWatcher`.
     */
    function removeEventWatcher(listener: (...args: any[]) => any): void;

    /**
     * Registers a listener that fires whenever battery state changes.
The listener receives no arguments; call `batteryInfo()` or read individual
properties inside the callback to determine what changed.
The OS notification subscription starts lazily on the first listener and
is released automatically when the last listener is removed.
     * @param listener A function called with no arguments on battery state change.
     */
    function addBatteryWatcher(listener: () => void): void;

    /**
     * Removes a previously registered battery change listener.
     * @param listener The function originally passed to `addBatteryWatcher`.
     */
    function removeBatteryWatcher(listener: (...args: any[]) => any): void;

    /**
     * The current battery charge percentage (0–100), or `-1` if no battery is present.
     */
    const percentage: number;

    /**
     * Whether the battery is currently charging.
Returns `false` when no battery is present.
     */
    const isCharging: boolean;

    /**
     * The current power source.
Returns `"ac"` when plugged in, `"battery"` when on battery power, `"ups"` when
powered by a UPS, or `"unknown"` if the source cannot be determined.
     */
    const powerSource: string;

    /**
     * Whether Low Power Mode is currently active.
     */
    const isLowPowerMode: boolean;

    /**
     * The current thermal state of the system.
Returns one of: `"nominal"`, `"fair"`, `"serious"`, `"critical"`.
     */
    const thermalState: string;

}

/**
 * Inspect and control the displays attached to the system.
## Obtaining screens
```javascript
const all    = hs.screen.all();   // [HSScreen, ...]
const main   = hs.screen.main();   // screen containing the focused window
const primary = hs.screen.primary(); // screen with the global menu bar
```
## Navigation
```javascript
const right = hs.screen.main().toEast();
if (right) console.log("Screen to the right:", right.name);
```
## Display modes
```javascript
const s = hs.screen.primary();
console.log(s.mode);
// → { width: 1440, height: 900, scale: 2, frequency: 60 }

s.setMode(1920, 1080, 1, 60);
```
## Screenshots
```javascript
const img = await hs.screen.main().snapshot();
img.saveToFile("/tmp/screen.png");
```
 */
declare namespace hs.screen {
    /**
     * All connected screens.
     * @returns An array of HSScreen objects
     */
    function all(): HSScreen[];

    /**
     * The screen that currently contains the focused window, or the screen
with the keyboard focus if no window is focused.
     * @returns An HSScreen object or `null` if no main screen can be determined.
     */
    function main(): HSScreen | null;

    /**
     * The primary display — the one that contains the global menu bar.
     * @returns An HSScreen object or `null` if no primary screen can be determined.
     */
    function primary(): HSScreen | null;

}

/**
 * An object representing a single display attached to the system.
## Coordinate system
All geometry is returned in **Hammerspoon screen coordinates**: the origin `(0, 0)`
is at the top-left of the primary display, and `y` increases downward.
This matches Hammerspoon v1 and is the inverse of the raw macOS/CoreGraphics convention.
## Examples
```javascript
const s = hs.screen.main();
console.log(s.name);               // e.g. "Built-in Retina Display"
console.log(s.frame.w);            // usable width in points

console.log(s.mode.width, s.mode.scale); // e.g. 1440, 2

s.desktopImage = "/Users/me/wallpaper.jpg";
```
 */
declare class HSScreen {
    /**
     * Switch to the given display mode.
Pass `0` for `scale` or `frequency` to match any value.
     * @param width Horizontal resolution in pixels.
     * @param height Vertical resolution in pixels.
     * @param scale Backing scale factor (e.g. `2` for HiDPI, `1` for non-HiDPI). Pass `0` to ignore.
     * @param frequency Refresh rate in Hz. Pass `0` to ignore.
     * @returns `true` on success.
     */
    setMode(width: number, height: number, scale: number, frequency: number): boolean;

    /**
     * Capture the current contents of this screen as an image.
Requires **Screen Recording** permission.
     * @returns Resolves with the captured image, or rejects if the capture fails (e.g. permission denied).
     */
    snapshot(): Promise<HSImage>;

    /**
     * The next screen in `hs.screen.all()` order, wrapping around.
     * @returns An HSScreen object
     */
    next(): HSScreen;

    /**
     * The previous screen in `hs.screen.all()` order, wrapping around.
     * @returns An HSScreen object
     */
    previous(): HSScreen;

    /**
     * The nearest screen whose left edge is at or beyond this screen's right edge, or `null`.
     * @returns An HSScreen object
     */
    toEast(): HSScreen | null;

    /**
     * The nearest screen whose right edge is at or before this screen's left edge, or `null`.
     * @returns An HSScreen object
     */
    toWest(): HSScreen | null;

    /**
     * The nearest screen that is physically above this screen, or `null`.
     * @returns An HSScreen object
     */
    toNorth(): HSScreen | null;

    /**
     * The nearest screen that is physically below this screen, or `null`.
     * @returns An HSScreen object
     */
    toSouth(): HSScreen | null;

    /**
     * Move this screen so its top-left corner is at the given position in global Hammerspoon coordinates.
     * @param x The X coordinate to move to
     * @param y The Y coordinate to move to
     * @returns `true` on success.
     */
    setOrigin(x: number, y: number): boolean;

    /**
     * Designate this screen as the primary display (moves the menu bar here).
     * @returns `true` on success.
     */
    setPrimary(): boolean;

    /**
     * Configure this screen to mirror another screen.
     * @param screen The screen to mirror.
     * @returns `true` on success.
     */
    mirrorOf(screen: HSScreen): boolean;

    /**
     * Stop mirroring, restoring this screen to an independent display.
     * @returns `true` on success.
     */
    mirrorStop(): boolean;

    /**
     * Convert a rect in global Hammerspoon coordinates to coordinates local to this screen.
The result origin is relative to this screen's top-left corner.
     * @param rect An `HSRect` in global Hammerspoon coordinates.
     * @returns The rect offset to be relative to this screen's top-left, or `null` if the input is invalid.
     */
    absoluteToLocal(rect: HSRect): HSRect;

    /**
     * Convert a rect in local screen coordinates to global Hammerspoon coordinates.
     * @remarks This uses private macOS APIs to set rotation.
     * @param rect An `HSRect` relative to this screen's top-left corner.
     * @returns The rect in global Hammerspoon coordinates, or `null` if the input is invalid.
     */
    localToAbsolute(rect: HSRect): HSRect;

    /**
     * Unique display identifier (matches `CGDirectDisplayID`).
     */
    readonly id: number;

    /**
     * The manufacturer-assigned localized display name.
     */
    readonly name: string;

    /**
     * The display's UUID string.
     */
    readonly uuid: string;

    /**
     * The usable screen area in Hammerspoon coordinates, excluding the menu bar and Dock.
     */
    readonly frame: HSRect;

    /**
     * The full screen area in Hammerspoon coordinates, including menu bar and Dock regions.
     */
    readonly fullFrame: HSRect;

    /**
     * The screen's top-left corner in global Hammerspoon coordinates.
     */
    readonly position: HSPoint;

    /**
     * The currently active display mode.
An object with keys: `width`, `height`, `scale`, `frequency`.
     */
    readonly mode: Record<string, any>;

    /**
     * All display modes supported by this screen.
Each element has keys: `width`, `height`, `scale`, `frequency`.
     */
    readonly availableModes: Record<string, any>[];

    /**
     * The current screen rotation in degrees (0, 90, 180, or 270).
Assign one of `0`, `90`, `180`, or `270` to rotate the display.
     */
    rotation: number;

    /**
     * The URL string of the current desktop background image for this screen, or `null`.
Assign a new absolute file path or `file://` URL string to change the wallpaper.
     */
    desktopImage: string | null;

}

/**
 * Query the macOS Spotlight metadata database.
`hs.spotlight` wraps `NSMetadataQuery` to let you search for files and other
metadata objects indexed by Spotlight. Queries use `NSPredicate` syntax with
`kMDItem*` attribute keys (see `hs.spotlight.attribute` for common shortcuts).
## Quick start
```js
// Find all PDFs in the home directory and log their paths
const q = hs.spotlight.create()
q.setQuery("kMDItemContentType == 'com.adobe.pdf'")
 .setScopes([hs.spotlight.scope.home])
 .setCallback((event) => {
     if (event === 'didFinish') {
         console.log('Found ' + q.count + ' PDFs')
         q.results().forEach(item =>
             console.log(item.valueForAttribute(hs.spotlight.attribute.path))
         )
         q.stop()
     }
 })
 .start()
```
## One-shot search convenience
```js
const q = hs.spotlight.search(
    "kMDItemDisplayName BEGINSWITH 'Invoice'",
    (event) => {
        if (event === 'didFinish') {
            console.log('Found ' + q.count + ' invoices')
            q.stop()
        }
    }
)
```
## Grouping results by attribute
```js
const q = hs.spotlight.create()
q.setQuery("kMDItemContentTypeTree == 'public.image'")
 .setScopes([hs.spotlight.scope.home])
 .setGroupingAttributes([hs.spotlight.attribute.kind])
 .setCallback((event) => {
     if (event === 'didFinish') {
         q.groups().forEach(g =>
             console.log(g.value() + ': ' + g.count + ' images')
         )
         q.stop()
     }
 })
 .start()
```
## Monitoring for live changes
```js
// Keep the query running to receive live-update events
const q = hs.spotlight.create()
q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
 .setScopes(['/Applications'])
 .setCallback((event, update) => {
     if (event === 'didFinish') {
         console.log('Initial scan: ' + q.count + ' apps')
     } else if (event === 'didUpdate') {
         console.log('App list changed — now ' + q.count + ' apps')
         if (update) console.log('Added: ' + update.added.length)
     }
 })
 .start()
// Call q.stop() when you no longer want live updates
```
 */
declare namespace hs.spotlight {
    /**
     * Creates and returns a new, unconfigured Spotlight query.
Configure it with `setQuery()`, `setScopes()`, and `setCallback()`, then call `start()`.
The query is automatically stopped and released when the module shuts down.
     * @returns A new `HSSpotlightQuery`
     */
    function create(): HSSpotlightQuery;

    /**
     * Convenience helper that creates, configures, and starts a query in one call.
Equivalent to `create().setQuery(predicate).setCallback(callback).start()`.
Call `q.stop()` from inside `callback` (when `event === 'didFinish'`) to end
the search once you have what you need.
     * @param predicate An NSPredicate-format query string
     * @param callback A function called with lifecycle event name and optional update data
     * @returns The `HSSpotlightQuery` object (use to stop the search early)
     */
    function search(predicate: string, callback: (event: string, update?: Record<string, any>) => void): HSSpotlightQuery;

    /**
     * Predefined search scope constants for use with `HSSpotlightQuery.setScopes()`.
| Key | Description |
|-----|-------------|
| `home` | The current user's home directory |
| `computer` | All locally mounted volumes |
| `network` | Network-mounted volumes |
| `applications` | Common locations for .app bundles |
| `icloud` | iCloud Documents |
| `icloudData` | iCloud Data (non-document ubiquitous files) |
     */
    const scope: Record<string, string[]>;

    /**
     * Common Spotlight metadata attribute key shortcuts.
These are plain `kMDItem*` string values — using them is equivalent to typing
the raw key name, but they provide autocomplete and avoid typos.
| Key | Attribute | Description |
|-----|-----------|-------------|
| `path` | `kMDItemPath` | Absolute filesystem path |
| `displayName` | `kMDItemDisplayName` | User-visible display name |
| `fsName` | `kMDItemFSName` | Filename on disk |
| `contentType` | `kMDItemContentType` | UTI content type |
| `contentTypeTree` | `kMDItemContentTypeTree` | Full UTI conformance tree |
| `kind` | `kMDItemKind` | Finder "Kind" string |
| `fileSize` | `kMDItemFSSize` | File size in bytes |
| `creationDate` | `kMDItemFSCreationDate` | Filesystem creation date |
| `modifiedDate` | `kMDItemFSContentChangeDate` | Last content modification date |
| `lastUsedDate` | `kMDItemLastUsedDate` | Last time the item was opened |
| `useCount` | `kMDItemUseCount` | Number of times opened |
| `authors` | `kMDItemAuthors` | Document authors |
| `title` | `kMDItemTitle` | Document title |
| `comment` | `kMDItemComment` | User comment |
| `keywords` | `kMDItemKeywords` | Tags/keywords |
| `durationSeconds` | `kMDItemDurationSeconds` | Media duration in seconds |
| `pixelWidth` | `kMDItemPixelWidth` | Image/video width in pixels |
| `pixelHeight` | `kMDItemPixelHeight` | Image/video height in pixels |
| `whereFroms` | `kMDItemWhereFroms` | Download source URLs |
| `bundleIdentifier` | `kMDItemCFBundleIdentifier` | App bundle identifier |
     */
    const attribute: Record<string, string>;

}

/**
 * A grouped set of Spotlight results that share a common metadata attribute value.
Groups are returned by `HSSpotlightQuery.groups()` when grouping attributes have been
configured with `setGroupingAttributes()`. Do not instantiate `HSSpotlightGroup` directly.
When multiple grouping attributes are specified, groups nest: each group has `subgroups()`
containing the next level of grouping.
 */
declare class HSSpotlightGroup {
    /**
     * The shared value of the grouping attribute for all results in this group.
Returns `null` only in the unlikely case that the underlying value cannot be bridged.
     * @returns The attribute value (string, number, Date, etc.) or null
     */
    value(): any | null;

    /**
     * Returns the items contained in this group as an array of `HSSpotlightItem` objects.
     * @returns An array of `HSSpotlightItem` objects
     */
    results(): HSSpotlightItem[];

    /**
     * Returns nested subgroups when multiple grouping attributes were specified.
Returns an empty array if no subgroups exist for this group.
     * @returns An array of `HSSpotlightGroup` objects
     */
    subgroups(): HSSpotlightGroup[];

    /**
     * A unique identifier for this group object (UUID string).
     */
    readonly identifier: string;

    /**
     * The metadata attribute name by which results in this group are clustered.
     */
    readonly attribute: string;

    /**
     * The number of results contained in this group.
     */
    readonly count: number;

}

/**
 * An individual result returned by a Spotlight query.
Instances are returned by `HSSpotlightQuery.results()` and related methods.
Do not instantiate `HSSpotlightItem` directly.
Metadata values are read via `valueForAttribute()` using standard `kMDItem*` keys.
Call `attributes()` to discover which keys are populated on a particular item.
Common attribute key shortcuts live in `hs.spotlight.attribute`.
 */
declare class HSSpotlightItem {
    /**
     * Returns the list of metadata attribute names present on this item.
The list is typically not exhaustive — some attributes (such as `kMDItemPath`)
may be readable via `valueForAttribute()` even when absent from this list.
     * @returns An array of attribute name strings
     */
    attributes(): string[];

    /**
     * Returns the value for a specific metadata attribute, or `null` if absent.
The return type depends on the attribute: common types include strings, numbers,
dates, and arrays of strings. `NSURL`-typed values are automatically converted
to their string representation.
     * @param key An attribute key such as `"kMDItemPath"` or `hs.spotlight.attribute.path`
     * @returns The attribute value, or null
     */
    valueForAttribute(key: string): any | null;

    /**
     * A unique identifier for this result object (UUID string).
     */
    readonly identifier: string;

}

/**
 * A configurable Spotlight search query that can be started, stopped, and queried for results.
Create instances via `hs.spotlight.create()` or the convenience helper `hs.spotlight.search()`.
Configure the query with chainable setter methods, register a callback, then call `start()`.
Results accumulate during the initial gathering phase (`"didStart"` → `"inProgress"` → `"didFinish"`)
and continue to update during the live-monitoring phase (`"didUpdate"`). Stop explicitly
with `stop()` when you no longer need live updates.
 */
declare class HSSpotlightQuery {
    /**
     * Sets the NSPredicate query string for this search.
The string must be a valid `NSPredicate` format expression using `kMDItem*` attribute
keys and MDQuery operators (`==`, `!=`, `<`, `>`, `BEGINSWITH`, `CONTAINS`, etc.).
If the query is already running when this is called, it is stopped and restarted
automatically.
     * @param predicate An NSPredicate-format query string
     * @returns this query, for chaining
     */
    setQuery(predicate: string): HSSpotlightQuery;

    /**
     * Sets the search scopes that restrict where Spotlight looks.
Pass an array of predefined scope strings from `hs.spotlight.scope`, absolute
directory paths, or a mix of both. Paths beginning with `~` are expanded to the
user's home directory.
When not set, the query defaults to `hs.spotlight.scope.computer`.
     * @param scopes An array of scope-constant strings or absolute directory paths
     * @returns this query, for chaining
     */
    setScopes(scopes: string[]): HSSpotlightQuery;

    /**
     * Sets sort descriptors that control the order of results.
     * @param descriptors An array of sort descriptor objects
     * @returns this query, for chaining
     */
    setSortDescriptors(descriptors: Record<string, any>[]): HSSpotlightQuery;

    /**
     * Sets the attributes by which results will be grouped.
When grouping attributes are set, use `groups()` to retrieve results organised into
`HSSpotlightGroup` objects. Specifying multiple attributes creates nested subgroups
accessible via `group.subgroups()`.
     * @param attrs An array of attribute name strings
     * @returns this query, for chaining
     */
    setGroupingAttributes(attrs: string[]): HSSpotlightQuery;

    /**
     * Sets the attributes for which aggregate value-list summaries are computed.
After the query finishes, `valueLists()` returns aggregate data for each specified
attribute: distinct values and the number of results carrying each value.
     * @param attrs An array of attribute name strings
     * @returns this query, for chaining
     */
    setValueListAttributes(attrs: string[]): HSSpotlightQuery;

    /**
     * Registers a callback that receives query lifecycle events.
of `HSSpotlightItem` objects describing what changed in this update cycle
     * @param fn Called with lifecycle event name and optional update data containing added/changed/removed item arrays
     * @returns this query, for chaining
     */
    setCallback(fn: (event: string, update?: Record<string, any>) => void): HSSpotlightQuery;

    /**
     * Starts the query.
The query must have a predicate set (via `setQuery()`) before calling `start()`.
Calling `start()` on an already-running query is a no-op.
     * @returns this query, for chaining
     */
    start(): HSSpotlightQuery;

    /**
     * Stops the query while preserving accumulated results.
After stopping, `results()`, `count`, `groups()`, and `valueLists()` continue to
return the last gathered data. Call `start()` again to resume.
     * @returns this query, for chaining
     */
    stop(): HSSpotlightQuery;

    /**
     * Returns the current results as an array of `HSSpotlightItem` objects.
The result set is briefly frozen during access to ensure consistency. Safe to call
from within a query callback.
     * @returns An array of `HSSpotlightItem` objects (may be empty if the query has not run)
     */
    results(): HSSpotlightItem[];

    /**
     * Returns grouped results when grouping attributes have been configured.
Returns an empty array if `setGroupingAttributes()` was not called.
     * @returns An array of `HSSpotlightGroup` objects
     */
    groups(): HSSpotlightGroup[];

    /**
     * Returns aggregate value-list summaries for attributes set via `setValueListAttributes()`.
Returns an empty array if `setValueListAttributes()` was not called.
     * @returns An array of summary objects
     */
    valueLists(): Record<string, any>[];

    /**
     * A unique identifier for this query object (UUID string).
     */
    readonly identifier: string;

    /**
     * The number of results gathered so far.
     */
    readonly count: number;

    /**
     * Whether the query is currently running (gathering or monitoring for live updates).
     */
    readonly isRunning: boolean;

    /**
     * Whether the query is in the initial gathering phase.
`true` from `"didStart"` until `"didFinish"`; `false` thereafter while live-monitoring.
     */
    readonly isGathering: boolean;

}

/**
 * Module for running external processes
 */
declare namespace hs.task {
    /**
     * Create a new task
     * @param launchPath The full path to the executable to run
     * @param arguments An array of arguments to pass to the executable
     * @param completionCallback Optional callback called when the task terminates with exit code and reason
     * @param environment Optional dictionary of environment variables for the task
     * @param streamingCallback Optional callback called when the task produces output; stream is "stdout" or "stderr"
     * @returns A task object. Call start() to begin execution.
     */
    function create(launchPath: string, arguments: string[], completionCallback: ((exitCode: number, exitReason: string) => void) | null, environment: Record<string, string> | null, streamingCallback: ((stream: string, data: string) => void) | null): HSTask;

    /**
     * Create and run a task asynchronously
     * @param launchPath - Full path to the executable
     * @param args - Array of arguments
     * @param options - Options object or legacy callback
     * @param legacyStreamCallback - Legacy streaming callback (optional)
     * @returns {Promise<{exitCode: number, stdout: string, stderr: string}>}
     */
    function runAsync(launchPath: string, args: string[], options: Object|Function, legacyStreamCallback: Function): any;

    /**
     * Run a shell command asynchronously
     * @param command - Shell command to execute
     * @param options - Options (same as run)
     * @returns {Promise<{exitCode: number, stdout: string, stderr: string}>}
     */
    function shell(command: string, options: Object): any;

    /**
     * Run multiple tasks in parallel
     * @returns {Promise<Array<{exitCode: number, stdout: string, stderr: string}>>} Array of results
     */
    function parallel(): any;

    /**
     * Create a task builder for fluent API
     * @param launchPath - Full path to the executable
     * @returns {TaskBuilder}
     */
    function builder(launchPath: string): any;

    /**
     * Run multiple tasks in sequence. Swift-retained storage for the JS implementation.
     */
    let sequence: ((...args: any[]) => any) | null;

    /**
     * TaskBuilder class. Swift-retained storage for the JS implementation.
     */
    let TaskBuilder: ((...args: any[]) => any) | null;

}

/**
 * Object representing an external process task
 */
declare class HSTask {
    /**
     * Start the task
     * @returns The task object for chaining
     */
    start(): HSTask;

    /**
     * Terminate the task (send SIGTERM)
     */
    terminate(): void;

    /**
     * Terminate the task with extreme prejudice (send SIGKILL)
     */
    kill9(): void;

    /**
     * Interrupt the task (send SIGINT)
     */
    interrupt(): void;

    /**
     * Pause the task (send SIGSTOP)
     */
    pause(): void;

    /**
     * Resume the task (send SIGCONT)
     */
    resume(): void;

    /**
     * Wait for the task to complete (blocking)
     */
    waitUntilExit(): void;

    /**
     * Write data to the task's stdin
     * @param data The string data to write
     */
    sendInput(data: string): void;

    /**
     * Close the task's stdin
     */
    closeInput(): void;

    /**
     * Check if the task is currently running
     * @remarks true if the task is running, false otherwise
     */
    readonly isRunning: boolean;

    /**
     * The process ID of the running task
     * @remarks The value will be -1 if the task is not running
     */
    readonly pid: number;

    /**
     * The environment variables for the task
     * @remarks Can only be modified before calling start()
     */
    environment: Record<string, string>;

    /**
     * The working directory for the task
     * @remarks Can only be modified before calling start()
     */
    workingDirectory: string | null;

    /**
     * The termination status of the task
     * @remarks Returns the exit code, or nil if the task hasn't terminated
     */
    readonly terminationStatus: number | null;

    /**
     * The termination reason
     * @remarks Returns a string describing why the task terminated, or nil if still running
     */
    readonly terminationReason: string | null;

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
    function create(interval: number, callback: () => void, continueOnError?: boolean): HSTimer;

    /**
     * Create and start a one-shot timer
     * @param seconds Number of seconds to wait before firing
     * @param callback A JavaScript function to call when the timer fires
     * @returns A timer object (already started)
     */
    function doAfter(seconds: number, callback: () => void): HSTimer;

    /**
     * Create and start a repeating timer
     * @param interval The interval in seconds at which the timer should fire
     * @param callback A JavaScript function to call when the timer fires
     * @returns A timer object (already started)
     */
    function doEvery(interval: number, callback: () => void): HSTimer;

    /**
     * Create and start a timer that fires at a specific time
     * @param time Seconds since midnight (local time) when the timer should first fire
     * @param repeatInterval If provided, the timer will repeat at this interval. Pass 0 for one-shot.
     * @param callback A JavaScript function to call when the timer fires
     * @param continueOnError If true, the timer will continue running even if the callback throws an error
     * @returns A timer object (already started)
     */
    function doAt(time: number, repeatInterval: number, callback: () => void, continueOnError?: boolean): HSTimer;

    /**
     * Block execution for a specified number of microseconds (strongly discouraged)
     * @remarks This blocks the entire application and should be avoided. Use timers instead.
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
    function absoluteTime(): number;

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

}

/**
 * Object representing a timer. You should not instantiate these yourself, but rather, use the methods in hs.timer to create them for you.
 */
declare class HSTimer {
    /**
     * Start the timer
     */
    start(): void;

    /**
     * Stop the timer
     */
    stop(): void;

    /**
     * Immediately fire the timer's callback
     */
    fire(): void;

    /**
     * Check if the timer is currently running
     * @returns true if the timer is running, false otherwise
     */
    running(): boolean;

    /**
     * Get the number of seconds until the timer next fires
     * @returns Seconds until next trigger, or a negative value if the timer is not running
     */
    nextTrigger(): number;

    /**
     * Set when the timer should next fire
     * @param seconds Number of seconds from now when the timer should fire
     */
    setNextTrigger(seconds: number): void;

    /**
     * The timer's interval in seconds
     */
    readonly interval: number;

    /**
     * Whether the timer repeats
     */
    readonly repeats: boolean;

}

/**
 * Translate text between languages using the macOS on-device Translation framework.
Language identifiers use BCP-47 format (e.g. `"en"`, `"fr"`, `"zh-Hans"`).
Call `hs.translation.supportedLanguages()` to list every language the framework
recognises, and `hs.translation.status()` to check whether a specific pair is
installed and ready for offline use.
Language packs are downloaded through
**System Settings → General → Language & Region → Translation Languages**.
`hs.translation` cannot trigger downloads programmatically; `session()` returns
`null` when the requested pair is not yet installed.
## Quick start
```js
hs.translation.status("en", "fr").then(s => {
    if (s === "installed") {
        const session = hs.translation.session("en", "fr")
        session.translate("Good morning").then(r => console.log(r))
    } else {
        console.log("Install en→fr in System Settings → Language & Region → Translation Languages")
    }
})
```
 */
declare namespace hs.translation {
    /**
     * All language codes supported by the on-device translation engine.
Resolves to an array of BCP-47 identifiers (e.g. `["ar", "de", "en", "es", "fr"]`).
This covers every language the framework knows about, regardless of whether
the packs are installed locally. Use `status()` to distinguish installed
pairs from merely supported ones.
     * @returns Resolves to an array of BCP-47 language code strings.
     */
    function supportedLanguages(): Promise<string[]>;

    /**
     * Check the installation status of a language pair.
     * @param sourceLanguage BCP-47 code of the source language (e.g. `"en"`).
     * @param targetLanguage BCP-47 code of the target language (e.g. `"fr"`).
     * @returns Resolves to `"installed"`, `"supported"`, or `"unsupported"`.
     */
    function status(sourceLanguage: string, targetLanguage: string): Promise<string>;

    /**
     * Create a translation session for a language pair.
Returns an `HSTranslationSession`, or `null` if the system is running macOS
older than 26.0.
     * @param sourceLanguage BCP-47 code of the source language (e.g. `"en"`).
     * @param targetLanguage BCP-47 code of the target language (e.g. `"fr"`).
     * @returns An `HSTranslationSession`, or `null` on unsupported versions of macOS.
     */
    function session(sourceLanguage: string, targetLanguage: string): HSTranslationSession | null;

}

/**
 * JavaScript-visible API for a translation session bound to a specific language pair.
 */
declare class HSTranslationSession {
    /**
     * Translate a string from the session's source language to its target language.
     * @param text The text to translate.
     * @returns A Promise resolving to the translated string,
     */
    translate(text: string): Promise<string>;

    /**
     * The Swift type name, for JavaScript introspection.
     */
    readonly typeName: string;

    /**
     * BCP-47 identifier of the source language (e.g. `"en"`).
     */
    readonly sourceLanguage: string;

    /**
     * BCP-47 identifier of the target language (e.g. `"fr"`).
     */
    readonly targetLanguage: string;

}

/**
 * # hs.ui
**Create custom user interfaces, alerts, dialogs, and file pickers**
The `hs.ui` module provides a set of tools for creating custom user interfaces
in Hammerspoon with SwiftUI-like declarative syntax.
## Key Features
then call `.replaceWithColor()` or `.replaceWithHex()` on it from any callback to re-render the canvas automatically
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
        if (index === 0) console.log("Saving...");
    })
    .show();
```
### Text Input Prompt
```javascript
hs.ui.textPrompt("Enter your name")
    .defaultText("John Doe")
    .onButton((buttonIndex, text) => {
        console.log("User entered: " + text);
    })
    .show();
```
### File Picker
```javascript
hs.ui.filePicker()
    .message("Choose a file")
    .allowedFileTypes(["txt", "md"])
    .onSelection((path) => {
        if (path) console.log("Selected: " + path);
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
            btnColor.replaceWithHex(isHovered ? "#E24A4A" : "#4A90E2");
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
            const next = (icon.name === "NSStatusAvailable")
                ? HSImage.fromName("NSStatusUnavailable")
                : HSImage.fromName("NSStatusAvailable");
            icon.replaceWithImage(next);
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
                cardColor.replaceWithHex(isHovered ? "#E74C3C" : "#3498DB");
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

    /**
     * Create a web browser element for embedding in `hs.ui.window` (macOS 26+)
Returns a `UIWebView` element that you configure and then embed in any `hs.ui.window`
via `.webview(element)`. The element fills the available space inside the window layout.
Keep a reference to call navigation methods after the window is shown.
     * @returns A `UIWebView` element for configuration and embedding
     */
    function webview(): UIWebView;

}

/**
 * # HSUIWindow
**A custom window with declarative UI building**
`HSUIWindow` allows you to create custom windows with a SwiftUI-like
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
    show(): HSUIWindow;

    /**
     * Hide the window (keeps it in memory)
     */
    hide(): void;

    /**
     * Close and destroy the window
     */
    close(): void;

    /**
     * Show or hide the window's title bar
By default windows have a title bar. Pass `false` to create a borderless window.
`.closable()`, `.miniaturizable()`, and `.allowResize()` only take visual effect
when the window is titled.
     * @param show Pass `false` to make the window borderless
     * @returns Self for chaining
     */
    titled(show: boolean): HSUIWindow;

    /**
     * Show or hide the close button on the window
Requires `.titled(true)` to be visible. Enabled by default.
     * @param show Pass `false` to hide the close button
     * @returns Self for chaining
     */
    closable(show: boolean): HSUIWindow;

    /**
     * Show or hide the miniaturize (yellow) button on the window
Requires `.titled(true)` to be visible. Enabled by default.
     * @param show Pass `false` to hide the miniaturize button
     * @returns Self for chaining
     */
    miniaturizable(show: boolean): HSUIWindow;

    /**
     * Allow or prevent the user from resizing the window
Enabled by default. Only has a visual effect when `.titled(true)` is also set.
     * @param enable Pass `false` to prevent the user from resizing the window
     * @returns Self for chaining
     */
    allowResize(enable: boolean): HSUIWindow;

    /**
     * Set the text shown in the window's title bar
Only visible when `.titled(true)` is set (the default).
     * @param text The title bar text
     * @returns Self for chaining
     */
    windowTitle(text: string): HSUIWindow;

    /**
     * Set the window stacking level
Controls where this window sits in the macOS window hierarchy.
     * @param name The level name
     * @returns Self for chaining
     */
    level(name: '"normal"' | '"floating"' | '"screenSaver"' | '"dock"' | '"status"' | '"popUpMenu"'): HSUIWindow;

    /**
     * Set the window's background color
     * @param colorValue Color as an HSColor object
     * @returns Self for chaining
     */
    backgroundColor(colorValue: HSColor): HSUIWindow;

    /**
     * Add a rectangle shape
     * @returns Self for chaining (apply modifiers like `fill()`, `frame()`)
     */
    rectangle(): HSUIWindow;

    /**
     * Add a circle shape
     * @returns Self for chaining (apply modifiers like `fill()`, `frame()`)
     */
    circle(): HSUIWindow;

    /**
     * Add a text element
or an `HSString` object (from `hs.ui.string()`) for reactive text
     * @param content The text to display — a plain JS string for static text,
     * @returns Self for chaining (apply modifiers like `font()`, `foregroundColor()`)
     */
    text(content: string | HSString): HSUIWindow;

    /**
     * Add an image element
     * @param imageValue Image as HSImage object
     * @returns Self for chaining (apply modifiers like `resizable()`, `aspectRatio()`, `frame()`)
     */
    image(imageValue: HSImage): HSUIWindow;

    /**
     * Add a button element
or an `HSString` object (from `hs.ui.string()`) for reactive text
     * @param label The button label — a plain JS string for static text,
     * @returns Self for chaining (apply `.fill()`, `.cornerRadius()`, `.font()`,
     */
    button(label: string | HSString): HSUIWindow;

    /**
     * Begin a vertical stack (elements arranged top to bottom)
     * @returns Self for chaining (call `end()` when done)
     */
    vstack(): HSUIWindow;

    /**
     * Begin a horizontal stack (elements arranged left to right)
     * @returns Self for chaining (call `end()` when done)
     */
    hstack(): HSUIWindow;

    /**
     * Begin a z-stack (overlapping elements)
     * @returns Self for chaining (call `end()` when done)
     */
    zstack(): HSUIWindow;

    /**
     * Add flexible spacing that expands to fill available space
     * @returns Self for chaining
     */
    spacer(): HSUIWindow;

    /**
     * Embed a web browser element created with `hs.ui.webview()` (macOS 26+)
The element fills the available space in the window layout.
Keep a reference to the element to call navigation methods after the window is shown.
     * @param element A `UIWebView` created via `hs.ui.webview()`
     * @returns Self for chaining
     */
    webview(element: UIWebView): HSUIWindow;

    /**
     * End the current layout container
     * @returns Self for chaining
     */
    end(): HSUIWindow;

    /**
     * Fill a shape with a color
     * @param colorValue Color as an HSColor
     * @returns Self for chaining
     */
    fill(colorValue: HSColor): HSUIWindow;

    /**
     * Add a stroke (border) to a shape
     * @param colorValue Color as an HSColor
     * @returns Self for chaining
     */
    stroke(colorValue: HSColor): HSUIWindow;

    /**
     * Set the stroke width
     * @param width Width in points
     * @returns Self for chaining
     */
    strokeWidth(width: number): HSUIWindow;

    /**
     * Round the corners of a shape
     * @param radius Corner radius in points
     * @returns Self for chaining
     */
    cornerRadius(radius: number): HSUIWindow;

    /**
     * Set the frame (size) of an element
     * @param dict Dictionary with `w` and/or `h` (can be numbers or percentage strings like "50%")
     * @returns Self for chaining
     */
    frame(dict: Record<string, any>): HSUIWindow;

    /**
     * Set the opacity of an element
     * @param value Opacity from 0.0 (transparent) to 1.0 (opaque)
     * @returns Self for chaining
     */
    opacity(value: number): HSUIWindow;

    /**
     * Set the font for a text element
     * @param font An HSFont object (e.g., `HSFont.title()`)
     * @returns Self for chaining
     */
    font(font: HSFont): HSUIWindow;

    /**
     * Set the text color
     * @param colorValue Color as HSColor
     * @returns Self for chaining
     */
    foregroundColor(colorValue: HSColor): HSUIWindow;

    /**
     * Make an image resizable (allows it to scale with frame size)
     * @returns Self for chaining
     */
    resizable(): HSUIWindow;

    /**
     * Set the aspect ratio mode for an image
     * @param mode "fit" (scales to fit within frame) or "fill" (scales to fill frame)
     * @returns Self for chaining
     */
    aspectRatio(mode: string): HSUIWindow;

    /**
     * Add padding around a layout container
     * @param value Padding in points
     * @returns Self for chaining
     */
    padding(value: number): HSUIWindow;

    /**
     * Set spacing between elements in a stack
     * @param value Spacing in points
     * @returns Self for chaining
     */
    spacing(value: number): HSUIWindow;

    /**
     * Set a callback to fire when the element is clicked
     * @param callback A JavaScript function to call on click
     * @returns Self for chaining
     */
    onClick(callback: () => void): HSUIWindow;

    /**
     * Set a callback to fire when the cursor enters or leaves the element
     * @param callback A JavaScript function called with `true` when the cursor enters and `false` when it leaves
     * @returns Self for chaining
     */
    onHover(callback: (isHovering: boolean) => void): HSUIWindow;

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
    font(font: HSFont): HSUIAlert;

    /**
     * Set how long the alert is displayed
     * @param seconds Duration in seconds (default: 5.0)
     * @returns Self for chaining
     */
    duration(seconds: number): HSUIAlert;

    /**
     * Set the padding around the alert text
     * @param points Padding in points (default: 20)
     * @returns Self for chaining
     */
    padding(points: number): HSUIAlert;

    /**
     * Set a custom position for the alert
     * @param dict Dictionary with `x` and `y` coordinates
     * @returns Self for chaining
     */
    position(dict: Record<string, any>): HSUIAlert;

    /**
     * Show the alert
     * @returns Self for chaining (can store reference to close manually)
     */
    show(): HSUIAlert;

    /**
     * Close the alert immediately
     */
    close(): void;

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
            console.log("Saving...");
        } else if (index === 1) {
            console.log("Discarding changes...");
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
    informativeText(text: string): HSUIDialog;

    /**
     * Set custom button labels
     * @param labels Array of button labels (default: ["OK"])
     * @returns Self for chaining
     */
    buttons(labels: string[]): HSUIDialog;

    /**
     * Set the dialog style
     * @param style Style name (e.g., "informational", "warning", "critical")
     * @returns Self for chaining
     */
    style(style: string): HSUIDialog;

    /**
     * Set the callback for button presses
     * @param callback Function receiving the 0-based index of the button the user pressed
     * @returns Self for chaining
     */
    onButton(callback: (buttonIndex: number) => void): HSUIDialog;

    /**
     * Show the dialog
     * @returns Self for chaining
     */
    show(): HSUIDialog;

    /**
     * Close the dialog programmatically
     */
    close(): void;

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
            console.log("Selected: " + path);
        } else {
            console.log("User cancelled");
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
            paths.forEach(p => console.log("Dir: " + p));
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
    message(text: string): HSUIFilePicker;

    /**
     * Set the starting directory
     * @param path Path to directory (supports `~` for home)
     * @returns Self for chaining
     */
    defaultPath(path: string): HSUIFilePicker;

    /**
     * Set whether files can be selected
     * @param value true to allow file selection (default: true)
     * @returns Self for chaining
     */
    canChooseFiles(value: boolean): HSUIFilePicker;

    /**
     * Set whether directories can be selected
     * @param value true to allow directory selection (default: false)
     * @returns Self for chaining
     */
    canChooseDirectories(value: boolean): HSUIFilePicker;

    /**
     * Set whether multiple items can be selected
     * @param value true to allow multiple selection (default: false)
     * @returns Self for chaining
     */
    allowsMultipleSelection(value: boolean): HSUIFilePicker;

    /**
     * Restrict to specific file types
     * @param types Array of file extensions (e.g., ["txt", "md"])
     * @returns Self for chaining
     */
    allowedFileTypes(types: string[]): HSUIFilePicker;

    /**
     * Set whether to resolve symbolic links
     * @param value true to resolve aliases (default: true)
     * @returns Self for chaining
     */
    resolvesAliases(value: boolean): HSUIFilePicker;

    /**
     * Set the callback for file selection
     * @param callback Function receiving the selected path(s) or null if cancelled. Single selection receives a string; multiple selection receives an array of strings.
     * @returns Self for chaining
     */
    onSelection(callback: (paths: string | string[] | null) => void): HSUIFilePicker;

    /**
     * Show the file picker dialog
     */
    show(): void;

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
            console.log("User entered: " + text);
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
    informativeText(text: string): HSUITextPrompt;

    /**
     * Set the default text in the input field
     * @param text Default text value
     * @returns Self for chaining
     */
    defaultText(text: string): HSUITextPrompt;

    /**
     * Set custom button labels
     * @param labels Array of button labels (default: ["OK", "Cancel"])
     * @returns Self for chaining
     */
    buttons(labels: string[]): HSUITextPrompt;

    /**
     * Set the callback for button presses
     * @param callback Function receiving the 0-based button index and the text the user entered
     * @returns Self for chaining
     */
    onButton(callback: (buttonIndex: number, inputText: string) => void): HSUITextPrompt;

    /**
     * Show the prompt dialog
     */
    show(): void;

}

/**
 * # hs.ui.webview
**A web browser element for embedding in `hs.ui.window` layouts**
Available on macOS 26.0 or later, `hs.ui.webview()` creates a web browser element backed
by a SwiftUI `WebView` and `WebPage`. Embed it in any `hs.ui.window` using
`.webview(element)` — it fills the available space and can sit alongside other elements in
stacks.
```javascript
const wv = hs.ui.webview()
    .toolbar(["back", "forward", "reload", "url"])
    .loadURL("https://apple.com")

hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
    .titled(true)
    .closable(true)
    .allowResize(true)
    .level("normal")
    .webview(wv)
    .show()
```
Because `wv` is a regular JavaScript object you can keep a reference and call navigation
```javascript
wv.loadURL("https://google.com")
wv.goBack()
```
## Custom Toolbar Example
```javascript
const wv = hs.ui.webview()
    .toolbar([
        "back", "forward", "reload", "url",
        {title: "Home", systemImage: "house", callback: () => wv.loadURL("https://apple.com")},
        {title: "Reload HS", callback: () => hs.reload()}
    ])
    .loadURL("https://apple.com")

hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
    .webview(wv)
    .show()
```
## Full Example with Callbacks
```javascript
const wv = hs.ui.webview()
    .toolbar(["back", "forward", "reload", "url"])
    .inspectable(true)
    .onNavigate((url) => console.log("Navigated to: " + url))
    .onTitleChange((title) => console.log("Title: " + title))
    .onLoadChange((loading, url, title, progress) => {
        if (!loading) console.log("Page ready: " + url)
    })
    .loadURL("https://apple.com")

hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
    .webview(wv)
    .show()
```
## Navigation Policy Example
```javascript
const wv = hs.ui.webview()
    .toolbar(["back", "forward", "reload", "url"])
    .onNavigationDecision((url) => {
        return !url.includes("evil.com")
    })
    .loadURL("https://apple.com")

hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
    .webview(wv)
    .show()
```
## JavaScript Evaluation Example
```javascript
const wv = hs.ui.webview().loadURL("https://apple.com")
hs.ui.window({x: 100, y: 100, w: 1024, h: 768}).webview(wv).show()

// Fire and forget
wv.execJS("document.body.style.backgroundColor = 'lightyellow'")

// With result (note the JS method name is evalJSResult)
wv.evalJSResult("document.title", (result, error) => {
    if (error) { console.log("Error: " + error) }
    else { console.log("Title: " + result) }
})
```
 */
declare class UIWebView {
    /**
     * Load a URL in the web view
     * @param urlString The URL to load (e.g. "https://apple.com")
     * @returns Self for chaining
     */
    loadURL(urlString: string): UIWebView;

    /**
     * Load an HTML string directly into the web view
     * @param html The HTML content to display
     * @returns Self for chaining
     */
    loadHTML(html: string): UIWebView;

    /**
     * Navigate back in the browser history
     * @returns Self for chaining
     */
    goBack(): UIWebView;

    /**
     * Navigate forward in the browser history
     * @returns Self for chaining
     */
    goForward(): UIWebView;

    /**
     * Reload the current page
     * @returns Self for chaining
     */
    reload(): UIWebView;

    /**
     * Stop loading the current page
     * @returns Self for chaining
     */
    stopLoading(): UIWebView;

    /**
     * Set a custom User-Agent string for HTTP requests
     * @param ua The User-Agent string
     * @returns Self for chaining
     */
    userAgent(ua: string): UIWebView;

    /**
     * Enable or disable the Safari Web Inspector for this web view
When enabled, the web view appears in Safari → Develop menu.
     * @param value Pass `true` to enable the Web Inspector
     * @returns Self for chaining
     */
    inspectable(value: boolean): UIWebView;

    /**
     * Configure the toolbar with a list of standard and custom items
The toolbar renders above the web view. Each element of the array is either a string
naming a standard control or a dictionary describing a custom button.
An empty array (or omitting this call) hides the toolbar.
Standard string items: `"back"`, `"forward"`, `"reload"`, `"url"`, `"spacer"`.
     * @remarks The toolbar will not be shown if the web view is in a borderless window
     * @param items Toolbar items in display order
     * @returns Self for chaining
     */
    toolbar(items: Array<string | {title?: string, systemImage?: string, callback: () => void}>): UIWebView;

    /**
     * Enable or disable the macOS back/forward trackpad swipe gestures
Gestures are enabled by default. Pass `false` to disable them.
     * @param enabled Pass `false` to disable back/forward swipe gestures
     * @returns Self for chaining
     */
    backForwardGestures(enabled: boolean): UIWebView;

    /**
     * Enable or disable the trackpad pinch-to-zoom magnification gesture
The gesture is enabled by default. Pass `false` to disable it.
     * @param enabled Pass `false` to disable pinch-to-zoom
     * @returns Self for chaining
     */
    magnificationGestures(enabled: boolean): UIWebView;

    /**
     * Enable or disable link preview popovers shown on force-click
Link previews are enabled by default. Pass `false` to disable them.
     * @param enabled Pass `false` to disable link previews
     * @returns Self for chaining
     */
    linkPreviews(enabled: boolean): UIWebView;

    /**
     * Control whether the web page background is visible
Pass `false` to make the web view background transparent. Enabled (visible) by default.
     * @param visible Pass `false` to hide the web content background
     * @returns Self for chaining
     */
    contentBackground(visible: boolean): UIWebView;

    /**
     * Register a callback that fires when loading state or progress changes
Called whenever `isLoading`, `url`, `title`, or `estimatedProgress` changes.
     * @param callback Called with current loading state
     * @returns Self for chaining
     */
    onLoadChange(callback: (isLoading: boolean, url: string | null, title: string, progress: number) => void): UIWebView;

    /**
     * Register a callback that fires when navigation to a new page completes
     * @param callback Called with the final URL
     * @returns Self for chaining
     */
    onNavigate(callback: (url: string) => void): UIWebView;

    /**
     * Register a callback that fires when the page title changes
     * @param callback Called with the new title
     * @returns Self for chaining
     */
    onTitleChange(callback: (title: string) => void): UIWebView;

    /**
     * Register a callback that controls whether navigation is allowed
Called before each navigation. Return `true` to allow or `false` to block.
     * @param callback Return `true` to allow, `false` to block
     * @returns Self for chaining
     */
    onNavigationDecision(callback: (url: string) => boolean): UIWebView;

    /**
     * Execute JavaScript in the web page without capturing the result
     * @param script The JavaScript code to execute
     * @returns Self for chaining
     */
    execJS(script: string): UIWebView;

    /**
     * Execute JavaScript in the web page and deliver the result to a callback
The JavaScript method name is `evalJSResult` — it derives from the internal
Objective-C selector `evalJS:result:`.
     * @param script The JavaScript expression to evaluate
     * @param callback Called with the result or an error message
     * @returns Self for chaining
     */
    evalJSResult(script: string, callback: (result: any, error: string | null) => void): UIWebView;

    /**
     * The URL of the current page, or `null` if no page is loaded
     */
    readonly url: string | null;

    /**
     * The title of the current page
     */
    readonly title: string;

    /**
     * Whether the web view is currently loading a page
     */
    readonly isLoading: boolean;

    /**
     * The estimated loading progress from 0.0 to 1.0
     */
    readonly estimatedProgress: number;

    /**
     * Whether the web view can navigate back in history
     */
    readonly canGoBack: boolean;

    /**
     * Whether the web view can navigate forward in history
     */
    readonly canGoForward: boolean;

}

/**
 * Handle URL events received by Hammerspoon 2.
The module responds to `hammerspoon2://` URLs and, when Hammerspoon 2 is
configured as the system default handler, also to `http://`, `https://`,
and `mailto:` URLs.
## Responding to custom hammerspoon2:// events
URLs take the form `hammerspoon2://eventName?key=value&key2=value2`.
The host component (`eventName`) selects the registered callback.
```js
hs.urlevent.bind("myEvent", (eventName, params, pid, url) => {
    console.log("param foo = " + params["foo"])
})

// Remove a binding
hs.urlevent.bind("myEvent", null)
```
## Intercepting http / https / mailto URLs
Set `hs.urlevent.httpCallback` (or `mailtoCallback`) to a function.
You must also set Hammerspoon 2 as the system default handler for the
relevant scheme — see `setDefaultHandler(_:_:)`.
```js
hs.urlevent.httpCallback = (scheme, host, params, fullURL, pid) => {
    // Forward to a real browser rather than swallowing the link
    hs.urlevent.openURLWithBundle(fullURL, "com.apple.safari")
}
```
## Querying and changing default handlers
```js
const current = hs.urlevent.getDefaultHandler("https")
console.log("Current HTTPS handler: " + current)

const all = hs.urlevent.getAllHandlersForScheme("https")
console.log("Available: " + all.join(", "))

hs.urlevent.setDefaultHandler("https", "com.apple.safari")
```
 */
declare namespace hs.urlevent {
    /**
     * Register or remove a callback for a named `hammerspoon2://` URL event.
The URL format is `hammerspoon2://eventName?key=value`. The host
component (`eventName`) selects the callback to invoke.
     * @param eventName The URL host component identifying the event.
     * @param callback A function receiving `(eventName, params, senderPID, fullURL)`, or `null` to remove any existing binding.
     */
    function bind(eventName: string, callback: ((eventName: string, params: Record<string, string>, senderPID: number, fullURL: string) => void) | null): void;

    /**
     * Open a URL using the system default application for its scheme.
     * @param urlString The URL to open.
     * @returns `true` if the URL was successfully dispatched.
     */
    function openURL(urlString: string): boolean;

    /**
     * Open a URL with a specific application identified by bundle ID.
     * @param urlString The URL to open.
     * @param bundleID Bundle identifier of the application to use.
     * @returns `true` if the URL was dispatched to the application.
     */
    function openURLWithBundle(urlString: string, bundleID: string): boolean;

    /**
     * Returns the bundle identifier of the default application for a URL scheme.
     * @param scheme The scheme to query, without `://` (e.g. `"https"`, `"mailto"`).
     * @returns The bundle identifier string, or `null` if none is registered.
     */
    function getDefaultHandler(scheme: string): string | null;

    /**
     * Returns all bundle identifiers capable of handling a URL scheme.
     * @param scheme The scheme to query, without `://` (e.g. `"https"`, `"mailto"`).
     * @returns An array of bundle identifier strings.
     */
    function getAllHandlersForScheme(scheme: string): string[];

    /**
     * Set the default application for a URL scheme.
macOS may display a confirmation dialog for sensitive schemes such as
`http` and `https`. For custom schemes (`hammerspoon2`) no dialog is shown.
     * @param scheme The scheme to configure, without `://` (e.g. `"https"`, `"mailto"`).
     * @param bundleID Bundle identifier of the application to set as default.
     * @returns `true` if the change was accepted by the system.
     */
    function setDefaultHandler(scheme: string, bundleID: string): boolean;

    /**
     * Callback invoked when Hammerspoon 2 receives an `http://` or `https://` URL.
Fires only when Hammerspoon 2 is the system default handler for `http`/`https`.
Assign `null` to remove the callback.
     */
    let httpCallback: ((scheme: string, host: string, params: Record<string, string>, fullURL: string, senderPID: number) => void) | null;

    /**
     * Callback invoked when Hammerspoon 2 receives a `mailto:` URL.
Fires only when Hammerspoon 2 is the system default handler for `mailto`.
Assign `null` to remove the callback.
     */
    let mailtoCallback: ((scheme: string, host: string, params: Record<string, string>, fullURL: string, senderPID: number) => void) | null;

}

/**
 * Module for interacting with windows
 */
declare namespace hs.window {
    /**
     * Get the currently focused window
     * @returns The focused window, or nil if none
     */
    function focusedWindow(): HSWindow | null;

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
    function windowAtPoint(point: HSPoint): HSWindow | null;

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
Note that this type uses private macOS APIs
 */
declare class HSWindow {
    /**
     * Focus this window
     * @returns true if successful
     */
    focus(): boolean;

    /**
     * Minimize this window
     * @returns true if successful
     */
    minimize(): boolean;

    /**
     * Unminimize this window
     * @returns true if successful
     */
    unminimize(): boolean;

    /**
     * Raise this window to the front
     * @returns true if successful
     */
    raise(): boolean;

    /**
     * Toggle fullscreen mode
     * @returns true if successful
     */
    toggleFullscreen(): boolean;

    /**
     * Close this window
     * @returns true if successful
     */
    close(): boolean;

    /**
     * Center the window on the screen
     */
    centerOnScreen(): void;

    /**
     * Get the underlying AXElement
     * @returns The accessibility element for this window
     */
    axElement(): HSAXElement;

    /**
     * The window's title
     */
    readonly title: string | null;

    /**
     * The application that owns this window
     */
    readonly application: HSApplication | null;

    /**
     * The process ID of the application that owns this window
     */
    readonly pid: number;

    /**
     * The window's underlying ID.
A value of 0 or -1 likely means no window ID could be determined.
     */
    readonly id: number;

    /**
     * Whether the window is minimized
     */
    isMinimized: boolean;

    /**
     * Whether the window is visible (not minimized or hidden)
     */
    readonly isVisible: boolean;

    /**
     * Whether the window is focused
     */
    readonly isFocused: boolean;

    /**
     * Whether the window is fullscreen
     */
    isFullscreen: boolean;

    /**
     * Whether the window is standard (has a titlebar)
     */
    readonly isStandard: boolean;

    /**
     * The window's position on screen {x: Int, y: Int}
     */
    position: HSPoint | null;

    /**
     * The window's size {w: Int, h: Int}
     */
    size: HSSize | null;

    /**
     * The window's frame {x: Int, y: Int, w: Int, h: Int}
     */
    frame: HSRect | null;

    /**
     * The screen that contains the largest portion of this window.
     */
    readonly screen: HSScreen | null;

}

