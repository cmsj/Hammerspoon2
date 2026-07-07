#!/usr/bin/env node

/**
 * Generates a root index.html for the multi-version docs site.
 *
 * Usage:  node scripts/generate-versions-index.js <site-dir>
 *
 * Scans <site-dir> for subdirectories (each is a published version),
 * sorts them (main first, then semver newest-first, then others alphabetically),
 * and writes <site-dir>/index.html.
 */

const fs = require('fs');
const path = require('path');

const siteDir = process.argv[2];
if (!siteDir) {
    console.error('Usage: generate-versions-index.js <site-dir>');
    process.exit(1);
}

// Collect version subdirectories (skip hidden dirs and non-directories)
const versions = fs.readdirSync(siteDir, { withFileTypes: true })
    .filter(e => e.isDirectory() && !e.name.startsWith('.'))
    .map(e => e.name);

if (versions.length === 0) {
    console.log('  ⚠ No version directories found, skipping root index generation');
    process.exit(0);
}

// Sort: 'main' first, then semver newest-first, then others alphabetically
const semverRe = /^v?(\d+)\.(\d+)\.(\d+)(?:[.-](.+))?$/;

versions.sort((a, b) => {
    if (a === 'main') return -1;
    if (b === 'main') return 1;

    const ma = a.match(semverRe);
    const mb = b.match(semverRe);

    if (ma && mb) {
        const diff = (i) => parseInt(mb[i], 10) - parseInt(ma[i], 10);
        return diff(1) || diff(2) || diff(3);
    }
    if (ma) return -1;
    if (mb) return 1;

    return a.localeCompare(b);
});

// Determine the "latest" label: first semver version in sorted order, or 'main'
const latestVersion = versions.find(v => v !== 'main' && semverRe.test(v)) || versions[0];

const listItems = versions.map(v => {
    const isLatest = v === latestVersion && versions.length > 1;
    const badge = isLatest
        ? ' <span class="badge">latest</span>'
        : v === 'main'
            ? ' <span class="badge dev">dev</span>'
            : '';
    return `            <li>
                <div class="version-row">
                    <span class="version-name">${v}${badge}</span>
                    <div class="version-links">
                        <a href="${v}/js/">JavaScript API</a>
                        <a href="${v}/ts/">TypeScript</a>
                    </div>
                </div>
            </li>`;
}).join('\n');

const html = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hammerspoon 2 — API Documentation</title>
    <style>
        *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            font-size: 14px;
            background: #0d1117;
            color: #e6edf3;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            width: 100%;
            max-width: 480px;
            padding: 2rem;
        }
        .logo {
            font-size: 1.25rem;
            font-weight: 700;
            color: #e6edf3;
            margin-bottom: 0.25rem;
        }
        .subtitle {
            color: #8b949e;
            font-size: 0.9375rem;
            margin-bottom: 2rem;
        }
        .section-label {
            font-size: 0.75rem;
            font-weight: 600;
            color: #8b949e;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            margin-bottom: 0.75rem;
        }
        .version-list {
            list-style: none;
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
        }
        .version-list li {
            padding: 0.75rem 1rem;
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 8px;
        }
        .version-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 1rem;
        }
        .version-name {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
            font-size: 0.9375rem;
            color: #e6edf3;
        }
        .version-links {
            display: flex;
            gap: 0.5rem;
        }
        .version-links a {
            padding: 0.25rem 0.625rem;
            background: rgba(31, 111, 235, 0.1);
            border: 1px solid rgba(88, 166, 255, 0.25);
            border-radius: 5px;
            color: #58a6ff;
            text-decoration: none;
            font-size: 0.8125rem;
            transition: border-color 0.15s, background 0.15s;
        }
        .version-links a:hover {
            background: rgba(31, 111, 235, 0.2);
            border-color: #58a6ff;
        }
        .badge {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            font-size: 0.6875rem;
            font-weight: 500;
            padding: 0.125rem 0.5rem;
            border-radius: 4px;
            background: rgba(31, 111, 235, 0.15);
            color: #58a6ff;
            border: 1px solid rgba(88, 166, 255, 0.3);
        }
        .badge.dev {
            background: rgba(63, 185, 80, 0.1);
            color: #3fb950;
            border-color: rgba(63, 185, 80, 0.3);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">Hammerspoon 2</div>
        <p class="subtitle">API Documentation</p>
        <div class="section-label">Available Versions</div>
        <ul class="version-list">
${listItems}
        </ul>
    </div>
</body>
</html>
`;

const outputPath = path.join(siteDir, 'index.html');
fs.writeFileSync(outputPath, html);
console.log(`  ✓ Generated root version index (${versions.length} version${versions.length === 1 ? '' : 's'})`);
