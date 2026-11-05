"use strict";

// Hammerspoon 2 — CommonJS module system
//
// Six primitives are installed by Swift before this file is evaluated.
// They are captured in the IIFE closure and then deleted from global scope
// so user code cannot reach or replace them.
//
// This is a plain CommonJS loader with no Hammerspoon-specific behavior - it doesn't know
// anything about Spoons. Spoons are loaded by hs.loadSpoon(), which validates a Spoon
// directory and then hands its init.js to this same require() by absolute path; the module
// wrapper below (see makeRequire) gives that file its own require() bound to its own
// directory automatically, the same way it does for any other file.
//
// Bare specifiers (eg. require('util')) first resolve against _builtinModules, a hard-coded
// registry of Node built-ins Hammerspoon 2 currently implements. Anything else is looked up
// Node-style in node_modules/<name>, walking up from the requiring file's directory (so the
// config directory's node_modules, populated by hs.npm.install(), is found from anywhere),
// honouring the package's "main" entry.

(function () {
    const _readFile   = globalThis._hs_readFile;
    const _fileExists = globalThis._hs_fileExists;
    const _expandPath = globalThis._hs_expandPath;
    const _evalScript = globalThis._hs_eval;
    const _configDir  = globalThis._hs_configDir;
    const _builtinModules = globalThis._hs_node_builtins;

    delete globalThis._hs_readFile;
    delete globalThis._hs_fileExists;
    delete globalThis._hs_expandPath;
    delete globalThis._hs_eval;
    delete globalThis._hs_configDir;
    delete globalThis._hs_node_builtins;

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
        return resolvePackage(id, fromFile);
    }

    // The "main" entry of <dir>/package.json, if any.
    function packageMain(dir) {
        const src = _readFile(dir + '/package.json');
        if (src == null) return null;
        try {
            const main = JSON.parse(src).main;
            return typeof main === 'string' ? main : null;
        } catch (e) {
            return null;
        }
    }

    // Node-style bare specifier lookup: node_modules/<id> in the requiring file's directory,
    // then each parent directory. <id> may include a subpath (eg. 'pkg/lib/util').
    // ponytail: no package.json "exports" map support, add when a wanted package needs it.
    function resolvePackage(id, fromFile) {
        let dir = dirname(fromFile);
        while (true) {
            const pkgDir = dir + '/node_modules/' + id;
            const main = packageMain(pkgDir);
            const found = (main && tryExtensions(joinPath(pkgDir, main))) || tryExtensions(pkgDir);
            if (found) return found;
            if (dir === '/') return null;
            dir = dirname(dir);
        }
    }

    function makeRequire(currentFile) {
        function require(id) {
            const name = String(id);
            if (Object.prototype.hasOwnProperty.call(_builtinModules, name)) {
                return _builtinModules[name];
            }

            const resolved = resolvePath(name, currentFile);
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
                try {
                    mod.exports = JSON.parse(src);
                    mod.loaded  = true;
                    return mod.exports;
                } catch (e) {
                    delete _cache[resolved];
                    throw e;
                }
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

    // The top-level require treats the user's config directory as the base directory so
    // that require('./utils') in init.js resolves to <configDir>/utils.js.
    globalThis.require = makeRequire(_configDir + "/<init>");
}());
