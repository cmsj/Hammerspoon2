#!/usr/bin/env node

/**
 * Event Name Consistency Check
 *
 * Watcher modules declare the event names they emit as a Swift enum conforming to
 * `HSEventName` (see "Hammerspoon 2/Engine/HSEventName.swift"). At runtime that enum is the
 * list on()/once() validate against; in the docs, each on()/off()/once() docstring repeats the
 * names as a literal union for the TypeScript definitions. This checks the two agree:
 *
 *  1. Every on/off/once `event` union in a module with HSEventName enums matches one of them,
 *     and none of an object's on/off/once has lost its union while its siblings kept theirs.
 *  2. Every HSEventName enum is matched by at least one documented union.
 *  3. Every LazyWatcherEmitter/KeyedLazyWatcherEmitter in a module's JS is given a module's
 *     `_eventNames` as its known-events list, unless it's explicitly exempted below.
 *
 * Reads the extracted docs JSON, so run `npm run docs:extract` first (test-docs.sh does).
 */

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..');
const JSON_DIR = path.join(REPO_ROOT, 'docs', 'json');
const MODULES_DIR = path.join(REPO_ROOT, 'Hammerspoon 2', 'Modules');

// Emitters that legitimately accept any event name, keyed by their label (first constructor arg).
const UNVALIDATED_EMITTERS = new Set([
    'hs.userdefaults',   // event names are arbitrary user-chosen preference keys
    'hs.camera device',  // per-camera on/off/once take no event name; Swift passes a fixed one
]);

const EVENT_METHODS = new Set(['on', 'off', 'once']);

/**
 * Parse every `enum Foo: String, HSEventName { ... }` in a Swift source, returning
 * [{ name, values: Set<string> }]. Only `case` lines at the enum's own top level are read, so a
 * `switch` inside a computed property (e.g. HSWifiEvent.cwEventType) is ignored.
 */
function parseSwiftEventEnums(source) {
    const enums = [];
    const header = /enum\s+(\w+)\s*:\s*String\s*,\s*HSEventName\s*\{/g;
    let match;
    while ((match = header.exec(source)) !== null) {
        let depth = 1;
        let i = header.lastIndex;
        let lineStart = i;
        const values = new Set();
        const readLine = (line) => {
            const caseMatch = line.match(/^\s*case\s+(.+)$/);
            if (!caseMatch) return;
            for (const part of caseMatch[1].split(',')) {
                const m = part.trim().match(/^(\w+)(?:\s*=\s*"((?:[^"\\]|\\.)*)")?/);
                if (m) values.add(m[2] !== undefined ? m[2] : m[1]);
            }
        };
        while (i < source.length && depth > 0) {
            const ch = source[i];
            if (ch === '{') depth++;
            else if (ch === '}') depth--;
            else if (ch === '\n') {
                if (depth === 1) readLine(source.slice(lineStart, i));
                lineStart = i + 1;
            }
            i++;
        }
        enums.push({ name: match[1], values });
    }
    return enums;
}

/**
 * Collect every documented on/off/once `event` union in a module's docs JSON, as { unions, missing }.
 *
 * An object (the module, or one of its types) whose on/off/once take an event name must document
 * a union on EVERY one of them: otherwise a single method losing its union would be skipped here
 * while its siblings still satisfied rule 2, and its generated declaration would silently degrade
 * to a plain string. Those methods are returned in `missing`. Objects whose on/off/once take no
 * event name at all (e.g. HSCamera, which has a single implicit event) are left alone.
 */
function collectDocumentedUnions(moduleJSON) {
    const unions = [];
    const missing = [];
    const visit = (owner, methods) => {
        const eventMethods = (methods ?? []).filter((m) => EVENT_METHODS.has(m.name));
        const takesEventName = (m) => (m.params ?? []).some((p) => p.name === 'event');
        if (!eventMethods.some(takesEventName)) return;
        for (const method of eventMethods) {
            const where = owner + '.' + method.name + '()';
            const param = (method.params ?? []).find((p) => p.name === 'event');
            const literals = param && typeof param.tsType === 'string'
                ? [...param.tsType.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => m[1])
                : [];
            if (literals.length === 0) {
                missing.push(where);
                continue;
            }
            unions.push({ where, values: new Set(literals) });
        }
    };
    visit(moduleJSON.name, moduleJSON.methods);
    for (const type of moduleJSON.types ?? []) {
        visit(type.name, type.methods);
    }
    return { unions, missing };
}

/**
 * Find every `new LazyWatcherEmitter(...)`/`new KeyedLazyWatcherEmitter(...)` in a JS source and
 * return { label, args } for each, where `args` is the source text of each top-level argument
 * (split by bracket matching, skipping string contents).
 */
function findEmitterConstructions(source) {
    const results = [];
    const pattern = /new\s+(?:Keyed)?LazyWatcherEmitter\s*\(/g;
    let match;
    while ((match = pattern.exec(source)) !== null) {
        let depth = 1;
        let i = pattern.lastIndex;
        let argStart = i;
        const args = [];
        let quote = null;
        while (i < source.length && depth > 0) {
            const ch = source[i];
            if (quote) {
                if (ch === '\\') i++;
                else if (ch === quote) quote = null;
            } else if (ch === '"' || ch === "'" || ch === '`') {
                quote = ch;
            } else if ('([{'.includes(ch)) {
                depth++;
            } else if (')]}'.includes(ch)) {
                depth--;
                if (depth === 0) args.push(source.slice(argStart, i).trim());
            } else if (ch === ',' && depth === 1) {
                args.push(source.slice(argStart, i).trim());
                argStart = i + 1;
            }
            i++;
        }
        const labelMatch = source.slice(pattern.lastIndex).match(/^\s*(["'])(.*?)\1/);
        results.push({ label: labelMatch ? labelMatch[2] : '<unknown>', args: args.filter((a) => a.length > 0) });
    }
    return results;
}

// The known-events argument must be derived from a Swift-backed `_eventNames` list (e.g.
// `hs.usb._eventNames`, `device._eventNames`, or a `.filter(...)` of one) - merely passing a 4th
// argument isn't enough, since `undefined`/`null` there silently disables validation again.
const KNOWN_EVENTS_ARG = /^[\w$.]+\._eventNames\b/;

function formatSet(values) {
    return [...values].map((v) => '"' + v + '"').join(', ');
}

function setsEqual(a, b) {
    return a.size === b.size && [...a].every((v) => b.has(v));
}

function main() {
    if (!fs.existsSync(JSON_DIR)) {
        console.error('❌ docs/json not found - run `npm run docs:extract` first');
        process.exit(1);
    }

    const errors = [];
    let checkedModules = 0;

    for (const moduleDirName of fs.readdirSync(MODULES_DIR).sort()) {
        const moduleDir = path.join(MODULES_DIR, moduleDirName);
        if (!fs.statSync(moduleDir).isDirectory()) continue;
        const files = fs.readdirSync(moduleDir);

        // Rule 3: every watcher emitter must be given a known-events list.
        for (const file of files.filter((f) => f.endsWith('.js'))) {
            const source = fs.readFileSync(path.join(moduleDir, file), 'utf8');
            for (const { label, args } of findEmitterConstructions(source)) {
                if (UNVALIDATED_EMITTERS.has(label)) continue;
                if (args.length < 4 || !KNOWN_EVENTS_ARG.test(args[3])) {
                    const got = args.length < 4 ? 'no 4th argument' : `4th argument is \`${args[3]}\``;
                    errors.push(`${moduleDirName}/${file}: emitter '${label}' is not given a known-events list - ${got} ` +
                                `(pass the module's _eventNames as the 4th argument, or exempt it in scripts/check-event-names.js)`);
                }
            }
        }

        const enums = files
            .filter((f) => f.endsWith('.swift'))
            .flatMap((f) => parseSwiftEventEnums(fs.readFileSync(path.join(moduleDir, f), 'utf8')));
        if (enums.length === 0) continue;

        const jsonFile = path.join(JSON_DIR, moduleDirName + '.json');
        if (!fs.existsSync(jsonFile)) {
            errors.push(`${moduleDirName}: has HSEventName enums but no extracted docs at docs/json/${moduleDirName}.json`);
            continue;
        }
        checkedModules++;
        const { unions, missing } = collectDocumentedUnions(JSON.parse(fs.readFileSync(jsonFile, 'utf8')));
        for (const where of missing) {
            errors.push(`${where}: takes an event name but documents no event union ` +
                        `(its siblings do - list the names as {"a" | "b"} in the event parameter)`);
        }
        const matchedEnums = new Set();

        // Rule 1: each documented union matches one of the module's enums.
        for (const union of unions) {
            const match = enums.find((e) => setsEqual(e.values, union.values));
            if (match) {
                matchedEnums.add(match.name);
                continue;
            }
            const closest = enums
                .map((e) => ({ e, overlap: [...union.values].filter((v) => e.values.has(v)).length }))
                .sort((a, b) => b.overlap - a.overlap)[0].e;
            const missing = [...closest.values].filter((v) => !union.values.has(v));
            const extra = [...union.values].filter((v) => !closest.values.has(v));
            errors.push(`${union.where}: documented event names don't match ${closest.name}` +
                        (missing.length ? `; missing from docs: ${formatSet(missing)}` : '') +
                        (extra.length ? `; not in enum: ${formatSet(extra)}` : ''));
        }

        // Rule 2: each enum is documented somewhere.
        for (const e of enums) {
            if (!matchedEnums.has(e.name)) {
                errors.push(`${moduleDirName}: no on/off/once docstring documents the event names of ${e.name} (${formatSet(e.values)})`);
            }
        }
    }

    if (errors.length > 0) {
        for (const error of errors) {
            console.error('❌ ' + error);
        }
        process.exit(1);
    }
    console.log(`✓ Event names consistent between Swift and docs (${checkedModules} modules checked)`);
}

main();
