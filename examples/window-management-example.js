// window-management-example.js
// Example usage of hs.ax and hs.window modules

console.info("=== Window Management Examples ===");

// Check accessibility permissions first
if (!hs.ax.isAccessibilityEnabled()) {
    console.error("Accessibility permissions required!");
    console.info("Requesting permissions...");
    hs.ax.requestAccessibility();
    // User will need to grant permissions in System Preferences
}

// ============================================
// BASIC WINDOW OPERATIONS
// ============================================

console.info("\n--- Basic Window Operations ---");

// Get the focused window
const focusedWin = hs.window.focusedWindow();
if (focusedWin) {
    console.info(`Focused window: "${focusedWin.title}"`);
    console.info(`  App: ${focusedWin.application.title} (pid: ${focusedWin.pid})`);
    console.info(`  Frame: ${JSON.stringify(focusedWin.frame)}`);
    console.info(`  Is minimized: ${focusedWin.isMinimized}`);
    console.info(`  Is fullscreen: ${focusedWin.isFullscreen}`);
}

// Get all windows
const allWindows = hs.window.allWindows();
console.info(`\nTotal windows: ${allWindows.length}`);

// Get visible windows only
const visibleWindows = hs.window.visibleWindows();
console.info(`Visible windows: ${visibleWindows.length}`);

// ============================================
// WINDOW MANIPULATION
// ============================================

console.info("\n--- Window Manipulation Examples ---");

// Center the focused window
if (focusedWin) {
    console.info("Centering focused window...");
    focusedWin.centerOnScreen();
}

// Move window to specific position
if (focusedWin) {
    console.info("Moving window to (100, 100)...");
    focusedWin.moveTo(100, 100);
}

// Resize window
if (focusedWin) {
    console.info("Resizing window to 800x600...");
    focusedWin.resize(800, 600);
}

// Set exact frame
if (focusedWin) {
    console.info("Setting window frame to (0, 0, 1000, 800)...");
    focusedWin.setFrame(0, 0, 1000, 800);
}

// ============================================
// WINDOW TILING
// ============================================

console.info("\n--- Window Tiling Examples ---");

// Tile window to left half
if (focusedWin) {
    console.info("Tiling to left half...");
    hs.window.tiling.left(focusedWin);
}

// Tile to right half
if (focusedWin) {
    console.info("Tiling to right half...");
    hs.window.tiling.right(focusedWin);
}

// Quarter screen tiling
if (focusedWin) {
    console.info("Tiling to top-left quarter...");
    hs.window.tiling.topLeft(focusedWin);
}

// ============================================
// FINDING WINDOWS
// ============================================

console.info("\n--- Finding Windows ---");

// Find windows by title
const safariWindows = hs.window.findByTitle("Safari");
console.info(`Windows with 'Safari' in title: ${safariWindows.length}`);

// Get windows for specific app
const frontApp = hs.application.frontmost();
if (frontApp) {
    const appWindows = hs.window.windowsForApp(frontApp.pid);
    console.info(`Windows for ${frontApp.title}: ${appWindows.length}`);
}

// Get window at specific position
const winAtPos = hs.window.windowAtPosition(500, 500);
if (winAtPos) {
    console.info(`Window at (500, 500): "${winAtPos.title}"`);
}

// ============================================
// USING THE LOW-LEVEL AX API
// ============================================

console.info("\n--- Low-Level Accessibility API ---");

// Get the system-wide AX element
const systemWide = hs.ax.systemWideElement();
if (systemWide) {
    console.info("System-wide element acquired");
    console.info(`  Role: ${systemWide.role}`);
    console.info(`  Available attributes: ${systemWide.attributeNames().join(", ")}`);
}

// Get AX element for focused window
if (focusedWin) {
    const axElement = focusedWin.axElement();
    console.info(`\nAX element for focused window:`);
    console.info(`  Role: ${axElement.role}`);
    console.info(`  Subrole: ${axElement.subrole}`);
    console.info(`  Title: ${axElement.title}`);
    console.info(`  Available actions: ${axElement.actionNames().join(", ")}`);

    // Explore the window's child elements
    const children = axElement.children();
    console.info(`  Child elements: ${children.length}`);

    children.slice(0, 5).forEach((child, i) => {
        console.info(`    Child ${i}: ${child.role} - "${child.title || "(no title)"}"`);
    });
}

// Get element at mouse position
const elementAtMouse = hs.ax.elementAtPosition(500, 500);
if (elementAtMouse) {
    console.info(`\nElement at (500, 500):`);
    console.info(`  Role: ${elementAtMouse.role}`);
    console.info(`  Title: ${elementAtMouse.title}`);
    console.info(`  Parent: ${elementAtMouse.parent?.role}`);
}

// ============================================
// ADVANCED: FINDING SPECIFIC UI ELEMENTS
// ============================================

console.info("\n--- Finding Specific UI Elements ---");

// Find all buttons in the focused window
if (focusedWin) {
    const axElement = focusedWin.axElement();
    const buttons = hs.ax.findByRole("AXButton", axElement);
    console.info(`Buttons in focused window: ${buttons.length}`);

    buttons.slice(0, 3).forEach((button, i) => {
        console.info(`  Button ${i}: "${button.title || "(no title)"}"`);
    });
}

// ============================================
// WINDOW CYCLING
// ============================================

console.info("\n--- Window Cycling ---");

// Set up a simple window cycling function
// (In practice, you'd bind this to a hotkey)
function cycleThroughWindows() {
    hs.window.cycleWindows();
}

// Example: cycle through windows (uncomment to test)
// cycleThroughWindows();
// hs.timer.doAfter(1, cycleThroughWindows);
// hs.timer.doAfter(2, cycleThroughWindows);

// ============================================
// GRID-BASED WINDOW MANAGEMENT
// ============================================

console.info("\n--- Grid-Based Layout ---");

// Define a 2x2 grid
if (focusedWin) {
    const grid = { rows: 2, cols: 2 };

    // Place window in top-left cell
    const topLeft = { row: 0, col: 0, rowSpan: 1, colSpan: 1 };
    console.info("Placing window in top-left grid cell...");
    hs.window.grid.setGrid(focusedWin, grid, topLeft);

    // Wait 2 seconds, then move to bottom-right
    hs.timer.doAfter(2, () => {
        const bottomRight = { row: 1, col: 1, rowSpan: 1, colSpan: 1 };
        console.info("Moving window to bottom-right grid cell...");
        hs.window.grid.setGrid(focusedWin, grid, bottomRight);
    });
}

// ============================================
// PRACTICAL EXAMPLE: WINDOW MANAGER
// ============================================

console.info("\n--- Practical Window Manager ---");

// Simple window manager object
const WindowManager = {
    layouts: {
        // Two equal columns
        twoColumn: function() {
            const windows = hs.window.visibleWindows().slice(0, 2);
            if (windows.length >= 1) {
                hs.window.tiling.left(windows[0]);
            }
            if (windows.length >= 2) {
                hs.window.tiling.right(windows[1]);
            }
            console.info(`Applied two-column layout to ${windows.length} windows`);
        },

        // Three column layout
        threeColumn: function() {
            const windows = hs.window.visibleWindows().slice(0, 3);
            const grid = { rows: 1, cols: 3 };

            windows.forEach((win, i) => {
                const cell = { row: 0, col: i, rowSpan: 1, colSpan: 1 };
                hs.window.grid.setGrid(win, grid, cell);
            });

            console.info(`Applied three-column layout to ${windows.length} windows`);
        },

        // Main + sidebar layout
        mainSidebar: function() {
            const windows = hs.window.visibleWindows();
            if (windows.length === 0) return;

            // Main window takes 2/3 of screen
            const grid = { rows: 1, cols: 3 };
            const mainCell = { row: 0, col: 0, rowSpan: 1, colSpan: 2 };
            hs.window.grid.setGrid(windows[0], grid, mainCell);

            // Sidebar windows stack in remaining 1/3
            if (windows.length > 1) {
                const sidebarCell = { row: 0, col: 2, rowSpan: 1, colSpan: 1 };
                hs.window.grid.setGrid(windows[1], grid, sidebarCell);
            }

            console.info(`Applied main+sidebar layout to ${windows.length} windows`);
        }
    },

    // Apply a layout by name
    applyLayout: function(layoutName) {
        if (this.layouts[layoutName]) {
            console.info(`Applying layout: ${layoutName}`);
            this.layouts[layoutName]();
        } else {
            console.error(`Unknown layout: ${layoutName}`);
        }
    }
};

// Example: Apply layouts (uncomment to test)
// WindowManager.applyLayout("twoColumn");
// hs.timer.doAfter(3, () => WindowManager.applyLayout("mainSidebar"));

// ============================================
// WINDOW MONITORING
// ============================================

console.info("\n--- Window Monitoring ---");

// You could set up watchers to respond to window events
// (This would require extending the window module with watchers)

function logWindowInfo() {
    const windows = hs.window.visibleWindows();
    console.info(`Currently ${windows.length} visible windows:`);

    windows.forEach((win, i) => {
        console.info(`  ${i + 1}. "${win.title}" - ${win.application.title}`);
    });
}

// Log window info every 10 seconds
// hs.timer.doEvery(10, logWindowInfo);

console.info("\n=== Examples Complete ===");
console.info("Uncomment the code above to test specific features!");
