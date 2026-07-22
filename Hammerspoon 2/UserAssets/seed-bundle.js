#!/usr/bin/env node
//
// bundle.js — Hammerspoon 2 npm library bundler
//
// Bundles every package listed in package.json "dependencies" into a single
// CommonJS file under lib/, which Hammerspoon's require() can load directly.
//
// Usage:
//   npm install <package-name>   # add a package
//   npm run bundle               # (re)build all packages into lib/
//
// Then in your init.js:
//   var pkg = require('./lib/<package-name>');
//
// Requires: node (https://nodejs.org) and npx (bundled with npm).
// esbuild is downloaded automatically by npx on first use.
//
// Note: pure JS libraries (math, strings, data) work well. Libraries that
// depend on Node built-ins (fs, crypto, Buffer, process) or browser globals
// (window, document, setTimeout) may fail at runtime even if they bundle
// successfully.

'use strict';

const { execFileSync } = require('child_process');
const fs   = require('fs');
const path = require('path');

const pkgPath = path.join(__dirname, 'package.json');
const pkg     = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
const deps    = Object.keys(pkg.dependencies || {});

if (deps.length === 0) {
    console.log('No dependencies to bundle.');
    console.log('Run `npm install <package>` first, then `npm run bundle`.');
    process.exit(0);
}

const libDir = path.join(__dirname, 'lib');
if (!fs.existsSync(libDir)) {
    fs.mkdirSync(libDir);
}

let errors = 0;

for (const dep of deps) {
    // Flatten scoped package names: @anthropic-ai/sdk → anthropic-ai-sdk
    const safeName = dep.replace(/^@/, '').replace(/\//g, '-');
    const outfile  = path.join(libDir, safeName + '.js');

    console.log(`Bundling ${dep} → lib/${safeName}.js ...`);
    try {
        execFileSync('npx', [
            '--yes',
            'esbuild',
            dep,
            '--bundle',
            '--platform=neutral',
            '--format=cjs',
            `--outfile=${outfile}`,
        ], { stdio: 'inherit' });
        console.log(`  ✓ ${dep}`);
    } catch (_) {
        console.error(`  ✗ ${dep} failed to bundle`);
        errors++;
    }
}

if (errors === 0) {
    console.log(`\nDone. Load packages in Hammerspoon with require('./lib/<name>').`);
} else {
    console.error(`\n${errors} package(s) failed. See output above for details.`);
    process.exit(1);
}
