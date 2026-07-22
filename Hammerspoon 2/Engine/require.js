"use strict";

// Hammerspoon 2 — CommonJS module system
//
// Four primitives are installed by Swift before this file is evaluated.
// They are captured in the IIFE closure and then deleted from global scope
// so user code cannot reach or replace them.
//
// Spoons are packages installed to ~/.config/hammerspoon2/Spoons/<Name>/
// and loaded with require('Name') or require('Name/lib/something').

(function () {
    const _readFile   = globalThis._hs_readFile;
    const _fileExists = globalThis._hs_fileExists;
    const _expandPath = globalThis._hs_expandPath;
    const _evalScript = globalThis._hs_eval;

    delete globalThis._hs_readFile;
    delete globalThis._hs_fileExists;
    delete globalThis._hs_expandPath;
    delete globalThis._hs_eval;

    const SPOONS_DIR = _expandPath("~/.config/hammerspoon2/Spoons");

    // Resolved absolute path → { exports, loaded, filename, id }
    const _cache = Object.create(null);

    function dirname(p) {
        const i = p.lastIndexOf('/');
        return i > 0 ? p.slice(0, i) : '/';
    }

    // Concatenate base dir and a possibly-relative segment, then normalise . and ..
    function joinPath(base, rel) {
        const parts = (base + '/' + rel).split('/');
        const out = [];
        for (const p of parts) {
            if (p === '..') out.pop();
            else if (p !== '.' && p !== '') out.push(p);
        }
        return '/' + out.join('/');
    }

    // Probe path as-is, then with .js, .json, /index.js suffixes
    function tryExtensions(base) {
        if (_fileExists(base))               return base;
        if (_fileExists(base + '.js'))       return base + '.js';
        if (_fileExists(base + '.json'))     return base + '.json';
        if (_fileExists(base + '/index.js')) return base + '/index.js';
        return null;
    }

    // Bare specifier: look up ~/.config/hammerspoon2/Spoons/<id>/
    function resolveSpoon(id) {
        const spoonDir = SPOONS_DIR + '/' + id;
        const spoonJson = spoonDir + '/spoon.json';
        if (_fileExists(spoonJson)) {
            const src = _readFile(spoonJson);
            if (src) {
                try {
                    const meta = JSON.parse(src);
                    if (meta.main) {
                        const resolved = tryExtensions(spoonDir + '/' + meta.main);
                        if (resolved) return resolved;
                    }
                } catch (_) {}
            }
        }
        return tryExtensions(spoonDir + '/index') || tryExtensions(spoonDir);
    }

    function resolvePath(id, fromFile) {
        if (id.startsWith('/')) {
            return tryExtensions(id);
        }
        if (id.startsWith('./') || id.startsWith('../')) {
            return tryExtensions(joinPath(dirname(fromFile), id));
        }
        if (id.startsWith('~/')) {
            return tryExtensions(_expandPath(id));
        }
        return resolveSpoon(id);
    }

    function makeRequire(currentFile) {
        function require(id) {
            const resolved = resolvePath(String(id), currentFile);
            if (!resolved) {
                throw new Error("Cannot find module '" + id + "' (from: " + currentFile + ")");
            }

            // Return cached exports — handles circular dependencies by returning the
            // partially-populated exports object that was registered before execution began.
            if (_cache[resolved]) {
                return _cache[resolved].exports;
            }

            const src = _readFile(resolved);
            if (src == null) {
                throw new Error("Cannot read module '" + resolved + "'");
            }

            const mod = { exports: {}, filename: resolved, id: resolved, loaded: false };
            _cache[resolved] = mod;

            if (resolved.endsWith('.json')) {
                mod.exports = JSON.parse(src);
                mod.loaded  = true;
                return mod.exports;
            }

            // Wrap in CommonJS function so each module gets its own scope.
            // The newline keeps source line numbers accurate (off by one on line 1 only).
            const wrapper = "(function(module,exports,require,__filename,__dirname){\n" + src + "\n})";
            const fn = _evalScript(wrapper, resolved);

            if (typeof fn !== 'function') {
                delete _cache[resolved];
                throw new Error("Failed to compile '" + resolved + "' (syntax error?)");
            }

            try {
                fn(mod, mod.exports, makeRequire(resolved), resolved, dirname(resolved));
            } catch (e) {
                delete _cache[resolved];
                throw e;
            }

            mod.loaded = true;
            return mod.exports;
        }

        require.resolve = function (id) {
            const resolved = resolvePath(String(id), currentFile);
            if (!resolved) {
                throw new Error("Cannot resolve '" + id + "' (from: " + currentFile + ")");
            }
            return resolved;
        };

        require.cache = _cache;
        return require;
    }

    // The top-level require treats ~/.config/hammerspoon2/ as the base directory so that
    // require('./utils') in a user's init.js resolves to ~/.config/hammerspoon2/utils.js.
    globalThis.require = makeRequire(_expandPath("~/.config/hammerspoon2") + "/<init>");
}());
