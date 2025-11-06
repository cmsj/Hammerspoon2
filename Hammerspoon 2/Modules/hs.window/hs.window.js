// hs.window.js
// JavaScript enhancements for the hs.window module

// Convenience function to get the focused window
// (alias for the module method)
hs.window.focused = hs.window.focusedWindow;

// Filter windows by title
hs.window.findByTitle = function(title) {
    return hs.window.allWindows().filter(win => {
        return win.title && win.title.includes(title);
    });
};

// Get windows for the current application
hs.window.currentWindows = function() {
    const app = hs.application.frontmost();
    if (!app) {
        return [];
    }
    return hs.window.windowsForApp(app.pid);
};

// Move window to left half of screen
hs.window.moveToLeftHalf = function(win) {
    win = win || hs.window.focusedWindow();
    if (!win) {
        return false;
    }

    const frame = win.frame;
    if (!frame) {
        return false;
    }

    // Get screen dimensions (simplified - assumes main screen)
    const screenWidth = 1920; // TODO: Get actual screen width
    const screenHeight = 1080; // TODO: Get actual screen height

    return win.setFrame(0, 0, Math.floor(screenWidth / 2), screenHeight);
};

// Move window to right half of screen
hs.window.moveToRightHalf = function(win) {
    win = win || hs.window.focusedWindow();
    if (!win) {
        return false;
    }

    const frame = win.frame;
    if (!frame) {
        return false;
    }

    // Get screen dimensions (simplified - assumes main screen)
    const screenWidth = 1920; // TODO: Get actual screen width
    const screenHeight = 1080; // TODO: Get actual screen height

    const halfWidth = Math.floor(screenWidth / 2);
    return win.setFrame(halfWidth, 0, halfWidth, screenHeight);
};

// Maximize window
hs.window.maximize = function(win) {
    win = win || hs.window.focusedWindow();
    if (!win) {
        return false;
    }

    // Get screen dimensions (simplified - assumes main screen)
    const screenWidth = 1920; // TODO: Get actual screen width
    const screenHeight = 1080; // TODO: Get actual screen height

    return win.setFrame(0, 0, screenWidth, screenHeight);
};

// Cycle through windows
hs.window._cycleIndex = 0;

hs.window.cycleWindows = function() {
    const windows = hs.window.orderedWindows().filter(w => w.isVisible);
    if (windows.length === 0) {
        return;
    }

    hs.window._cycleIndex = (hs.window._cycleIndex + 1) % windows.length;
    windows[hs.window._cycleIndex].focus();
};

// Window grid functionality
hs.window.grid = {
    // Set window to occupy a grid position
    // grid is {rows: N, cols: M}
    // cell is {row: Y, col: X, rowSpan: H, colSpan: W}
    setGrid: function(win, grid, cell) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        // Get screen dimensions (simplified - assumes main screen)
        const screenWidth = 1920; // TODO: Get actual screen width
        const screenHeight = 1080; // TODO: Get actual screen height

        const cellWidth = Math.floor(screenWidth / grid.cols);
        const cellHeight = Math.floor(screenHeight / grid.rows);

        const x = cell.col * cellWidth;
        const y = cell.row * cellHeight;
        const w = cell.colSpan * cellWidth;
        const h = cell.rowSpan * cellHeight;

        return win.setFrame(x, y, w, h);
    }
};

// Window tiling presets
hs.window.tiling = {
    left: function(win) {
        return hs.window.moveToLeftHalf(win);
    },

    right: function(win) {
        return hs.window.moveToRightHalf(win);
    },

    top: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenWidth = 1920;
        const screenHeight = 1080;

        return win.setFrame(0, 0, screenWidth, Math.floor(screenHeight / 2));
    },

    bottom: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenWidth = 1920;
        const screenHeight = 1080;
        const halfHeight = Math.floor(screenHeight / 2);

        return win.setFrame(0, halfHeight, screenWidth, halfHeight);
    },

    topLeft: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenWidth = 1920;
        const screenHeight = 1080;

        return win.setFrame(0, 0, Math.floor(screenWidth / 2), Math.floor(screenHeight / 2));
    },

    topRight: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenWidth = 1920;
        const screenHeight = 1080;
        const halfWidth = Math.floor(screenWidth / 2);

        return win.setFrame(halfWidth, 0, halfWidth, Math.floor(screenHeight / 2));
    },

    bottomLeft: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenWidth = 1920;
        const screenHeight = 1080;
        const halfHeight = Math.floor(screenHeight / 2);

        return win.setFrame(0, halfHeight, Math.floor(screenWidth / 2), halfHeight);
    },

    bottomRight: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenWidth = 1920;
        const screenHeight = 1080;
        const halfWidth = Math.floor(screenWidth / 2);
        const halfHeight = Math.floor(screenHeight / 2);

        return win.setFrame(halfWidth, halfHeight, halfWidth, halfHeight);
    }
};
