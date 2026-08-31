// hs.window.js
// JavaScript enhancements for the hs.window module
//
// The functions/objects below are assigned onto properties that hs.window (HSWindowModule)
// pre-declares in Swift. That's required, not stylistic: JavaScriptCore drops dynamically-added
// properties on a JSExport-wrapped object the first time it garbage collects that object's JS
// wrapper. Pre-declared @objc properties are real Swift-retained storage, so they survive GC.
// See issue #185.

// Convenience function to get the focused window
// (alias for the module method)
hs.window.focused = hs.window.focusedWindow;

// Filter windows by title
/// Find windows by title
/// Parameter title: The window title to search for. All windows with titles that include this string, will be matched
/// Returns: {HSWindow[]} An array of HSWindow objects with matching titles
hs.window.findByTitle = function(title) {
    return hs.window.allWindows().filter(win => {
        return win.title && win.title.includes(title);
    });
};

// Get windows for the current application
/// Get all windows for the current application
/// Returns: {HSWindow[]} An array of HSWindow objects
hs.window.currentWindows = function() {
    const app = hs.application.frontmost();
    if (!app) {
        return [];
    }
    return hs.window.windowsForApp(app.pid);
};

// Get the usable frame of the screen a window is on, falling back to the main screen.
function screenFrameFor(win) {
    const screen = (win && win.screen) || hs.screen.main();
    return screen ? screen.frame : null;
}

/// Move a window to left half of screen
/// Parameter win: An HSWindow object
/// Returns: {boolean} True if the operation was successful, otherwise False
hs.window.moveToLeftHalf = function(win) {
    win = win || hs.window.focusedWindow();
    if (!win) {
        return false;
    }

    const screenFrame = screenFrameFor(win);
    if (!screenFrame) {
        return false;
    }

    return win.setFrame(screenFrame.x, screenFrame.y, Math.floor(screenFrame.w / 2), screenFrame.h);
};

/// Move a window to right half of screen
/// Parameter win: An HSWindow object
/// Returns: {boolean} True if the operation was successful, otherwise False
hs.window.moveToRightHalf = function(win) {
    win = win || hs.window.focusedWindow();
    if (!win) {
        return false;
    }

    const screenFrame = screenFrameFor(win);
    if (!screenFrame) {
        return false;
    }

    const halfWidth = Math.floor(screenFrame.w / 2);
    return win.setFrame(screenFrame.x + halfWidth, screenFrame.y, halfWidth, screenFrame.h);
};

/// Maximize a window
/// Parameter win: An HSWindow object
/// Returns: {boolean} True if the operation was successful, otherwise false
hs.window.maximize = function(win) {
    win = win || hs.window.focusedWindow();
    if (!win) {
        return false;
    }

    const screenFrame = screenFrameFor(win);
    if (!screenFrame) {
        return false;
    }

    return win.setFrame(screenFrame.x, screenFrame.y, screenFrame.w, screenFrame.h);
};

// Cycle through windows
// FIXME: This seems kinda lame, and can only be called by one function at a time. Decide if we want this, most likely remove it.
/// SKIP_DOCS
hs.window.cycleWindows = (function() {
    let cycleIndex = 0;

    return function() {
        const windows = hs.window.orderedWindows().filter(w => w.isVisible);
        if (windows.length === 0) {
            return;
        }

        cycleIndex = (cycleIndex + 1) % windows.length;
        windows[cycleIndex].focus();
    };
})();

// FIXME: Everything below this seems dumb and out of place. Figure out what to do about submodules, since that isn't a concept we've introduced so far.
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

        const screenFrame = screenFrameFor(win);
        if (!screenFrame) {
            return false;
        }

        const cellWidth = Math.floor(screenFrame.w / grid.cols);
        const cellHeight = Math.floor(screenFrame.h / grid.rows);

        const x = screenFrame.x + cell.col * cellWidth;
        const y = screenFrame.y + cell.row * cellHeight;
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

        const screenFrame = screenFrameFor(win);
        if (!screenFrame) {
            return false;
        }

        return win.setFrame(screenFrame.x, screenFrame.y, screenFrame.w, Math.floor(screenFrame.h / 2));
    },

    bottom: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenFrame = screenFrameFor(win);
        if (!screenFrame) {
            return false;
        }

        const halfHeight = Math.floor(screenFrame.h / 2);
        return win.setFrame(screenFrame.x, screenFrame.y + halfHeight, screenFrame.w, halfHeight);
    },

    topLeft: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenFrame = screenFrameFor(win);
        if (!screenFrame) {
            return false;
        }

        return win.setFrame(screenFrame.x, screenFrame.y, Math.floor(screenFrame.w / 2), Math.floor(screenFrame.h / 2));
    },

    topRight: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenFrame = screenFrameFor(win);
        if (!screenFrame) {
            return false;
        }

        const halfWidth = Math.floor(screenFrame.w / 2);
        return win.setFrame(screenFrame.x + halfWidth, screenFrame.y, halfWidth, Math.floor(screenFrame.h / 2));
    },

    bottomLeft: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenFrame = screenFrameFor(win);
        if (!screenFrame) {
            return false;
        }

        const halfHeight = Math.floor(screenFrame.h / 2);
        return win.setFrame(screenFrame.x, screenFrame.y + halfHeight, Math.floor(screenFrame.w / 2), halfHeight);
    },

    bottomRight: function(win) {
        win = win || hs.window.focusedWindow();
        if (!win) {
            return false;
        }

        const screenFrame = screenFrameFor(win);
        if (!screenFrame) {
            return false;
        }

        const halfWidth = Math.floor(screenFrame.w / 2);
        const halfHeight = Math.floor(screenFrame.h / 2);
        return win.setFrame(screenFrame.x + halfWidth, screenFrame.y + halfHeight, halfWidth, halfHeight);
    }
};
