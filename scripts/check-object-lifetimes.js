#!/usr/bin/env node

/**
 * Object Lifetime Check
 *
 * A module's child objects must be retained from Swift in exactly one way: an HSObjectTracker
 * (see "Hammerspoon 2/Engine/HSObjectTracker.swift"), which tracks them weakly and pins the
 * active ones. Other retention mechanisms keep the Swift object alive but let its JSCallbacks be
 * collected, or keep it alive after it should have become garbage. This fails on:
 *
 *  1. `selfRetain = self`
 *  2. A `private var` stored property that's a strong collection of HS* objects
 *     (`[HSFoo]`, `Set<HSFoo>`, `[Key: HSFoo]`)
 *
 * Existing uses are listed in ALLOWED below: either awaiting migration (see the pending-activity
 * rollout), or justified because the objects are owned by the module rather than handed to JS
 * for the user to drop. Entries that no longer match anything also fail the check, so the list
 * only ever shrinks.
 */

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..');
const MODULES_DIR = path.join(REPO_ROOT, 'Hammerspoon 2', 'Modules');

// "<file relative to Modules/>:<property name, or selfRetain>" → reason
const ALLOWED = {
    // Awaiting migration to HSObjectTracker (pending-activity rollout)
    'hs.audiodevice/HSAudioDevice.swift:selfRetain': 'rollout',
    'hs.camera/HSCamera.swift:selfRetain': 'rollout',
    'hs.eventtap/HSEventTap.swift:selfRetain': 'rollout',
    'hs.filesystem/HSPathWatcher.swift:selfRetain': 'rollout',
    'hs.network/HSNetworkConfiguration.swift:selfRetain': 'rollout',
    'hs.network/HSNetworkReachability.swift:selfRetain': 'rollout',
    'hs.serial/HSSerialPort.swift:selfRetain': 'rollout',
    'hs.streamdeck/HSStreamDeckDevice.swift:selfRetain': 'rollout',
    'hs.eventtap/HSEventTapModule.swift:taps': 'rollout',
    'hs.eventtap/HSEventTapModule.swift:enabledTapHotkeys': 'rollout',
    'hs.sharing/HSSharingModule.swift:activeShares': 'rollout',
    'hs.ui/HSUIModule.swift:activeWindows': 'rollout',
    'hs.ui/HSUIModule.swift:activeAlerts': 'rollout',
    'hs.ui/HSUIModule.swift:activeDialogs': 'rollout',
    'hs.hotkey/HSHotkey.swift:hotkeys': 'rollout',
    'hs.canvas/HSCanvasModule.swift:activeCanvases': 'rollout',

    // Justified: module-owned objects, or transient lookups that aren't the objects' lifetime
    'hs.camera/HSCameraModule.swift:cameraCache': 'one object per physical camera, owned by the module so JS always gets the same one',
    'hs.streamdeck/HSStreamDeckModule.swift:devices': 'one object per connected device, owned by the module while it is connected',
    'hs.eventtap/HSEventTapModule.swift:heldTapHotkeys': 'routes a held key\'s key-up; entries only live while the key is down',
    'hs.bonjour/HSBonjourSearch.swift:serviceTable': 'keeps found services\' identity stable for their "removed" event, while the search runs',
    'hs.ax/HSAXModule.swift:watchers': 'internal watcher records, not objects handed to JS',
};

const COLLECTION = /^\s*private\s+var\s+(\w+)\s*(?::\s*(?:\[[\w.]+\s*:\s*HS\w+\]|Set<HS\w+>|\[HS\w+\])|=\s*(?:\[[\w.]+\s*:\s*HS\w+\]|Set<HS\w+>|\[HS\w+\])\(\))/;
const SELF_RETAIN = /\bselfRetain\s*=\s*self\b/;

function swiftFiles(dir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) return swiftFiles(full);
        return entry.name.endsWith('.swift') ? [full] : [];
    });
}

const found = new Map(); // key → "file:line"
for (const file of swiftFiles(MODULES_DIR)) {
    const rel = path.relative(MODULES_DIR, file).split(path.sep).join('/');
    fs.readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
        if (/^\s*\/\//.test(line)) return;
        const where = `${rel}:${i + 1}`;
        if (SELF_RETAIN.test(line)) found.set(`${rel}:selfRetain`, where);
        const match = COLLECTION.exec(line);
        if (match) found.set(`${rel}:${match[1]}`, where);
    });
}

const errors = [];
for (const [key, where] of found) {
    if (!(key in ALLOWED)) {
        const what = key.endsWith(':selfRetain') ? '`selfRetain = self`' : `strong collection \`${key.split(':')[1]}\``;
        errors.push(`${where}: ${what}. Track child objects with HSObjectTracker instead (see the HSModule skill, "Object lifetime").`);
    }
}
for (const key of Object.keys(ALLOWED)) {
    if (!found.has(key)) {
        errors.push(`${key}: listed in ALLOWED in scripts/check-object-lifetimes.js but no longer present. Remove the entry.`);
    }
}

if (errors.length) {
    for (const error of errors) console.error(`❌ ${error}`);
    process.exit(1);
}
const rollout = Object.values(ALLOWED).filter(reason => reason === 'rollout').length;
console.log(`✓ No new object retention mechanisms (${rollout} awaiting migration to HSObjectTracker)`);
