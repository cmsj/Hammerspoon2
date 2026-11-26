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

// Sort: 'main' first, then semver newest-first, then others alphabetically
const semverRe = /^v?(\d+)\.(\d+)\.(\d+)(?:[.-](.+))?$/;

/**
 * Compares two semver prerelease strings (e.g. "beta.2" vs "beta.10") using
 * semver precedence: dot-separated identifiers compared left to right,
 * numeric identifiers numerically and below alphanumeric ones, and a shorter
 * identifier list sorting first when all preceding identifiers are equal.
 * A missing prerelease (a full release) sorts above any prerelease.
 * Returns <0 if a precedes b in ascending order.
 */
function comparePrerelease(a, b) {
    if (a === b) return 0;
    if (a === undefined) return 1;
    if (b === undefined) return -1;

    const pa = a.split('.');
    const pb = b.split('.');
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        if (pa[i] === undefined) return -1;
        if (pb[i] === undefined) return 1;
        const na = /^\d+$/.test(pa[i]);
        const nb = /^\d+$/.test(pb[i]);
        if (na && nb) {
            const d = parseInt(pa[i], 10) - parseInt(pb[i], 10);
            if (d !== 0) return d;
        } else if (na) {
            return -1;
        } else if (nb) {
            return 1;
        } else if (pa[i] !== pb[i]) {
            return pa[i] < pb[i] ? -1 : 1;
        }
    }
    return 0;
}

/** Sorts version names in display order: main, semver newest-first, then the rest alphabetically. */
function sortVersions(versions) {
    return [...versions].sort((a, b) => {
        if (a === 'main') return -1;
        if (b === 'main') return 1;

        const ma = a.match(semverRe);
        const mb = b.match(semverRe);

        if (ma && mb) {
            const diff = (i) => parseInt(mb[i], 10) - parseInt(ma[i], 10);
            return diff(1) || diff(2) || diff(3) || comparePrerelease(mb[4], ma[4]);
        }
        if (ma) return -1;
        if (mb) return 1;

        return a.localeCompare(b);
    });
}

/**
 * Splits sorted version names into the page's sections: the latest release,
 * the developer build from main, and every other published version.
 * A section with nothing in it is an empty array.
 */
function groupVersions(sortedVersions) {
    const latest = sortedVersions.find(v => v !== 'main' && semverRe.test(v));
    return {
        latest: latest ? [latest] : [],
        developer: sortedVersions.filter(v => v === 'main'),
        previous: sortedVersions.filter(v => v !== 'main' && v !== latest)
    };
}

module.exports = { comparePrerelease, sortVersions, groupVersions };

if (require.main === module) {
    main(process.argv[2]);
}

function main(siteDir) {
    if (!siteDir) {
        console.error('Usage: generate-versions-index.js <site-dir>');
        process.exit(1);
    }

    // Collect version subdirectories (skip hidden dirs and non-directories)
    const versions = sortVersions(fs.readdirSync(siteDir, { withFileTypes: true })
        .filter(e => e.isDirectory() && !e.name.startsWith('.'))
        .map(e => e.name));

    if (versions.length === 0) {
        console.log('  ⚠ No version directories found, skipping root index generation');
        process.exit(0);
    }

    const versionItem = (v) => {
        const hasTS = fs.existsSync(path.join(siteDir, v, 'ts'));
        const tsLink = hasTS ? `<a href="${v}/ts/">TypeScript</a>` : '';
        return `                <li>
                    <div class="version-row">
                        <span class="version-name">${v}</span>
                        <div class="version-links">
                            <a href="${v}/js/">JavaScript API</a>
                            ${tsLink}
                        </div>
                    </div>
                </li>`;
    };

    const groups = groupVersions(versions);
    const sections = [
        ['latest', 'Latest release', groups.latest],
        ['developer', 'Developer', groups.developer, 'Built from the latest commit on the main branch'],
        ['previous', 'Previous releases', groups.previous]
    ].filter(([, , items]) => items.length > 0).map(([kind, label, items, note]) => `        <section class="version-section ${kind}">
            <h2 class="section-label">${label}</h2>${note ? `
            <p class="section-note">${note}</p>` : ''}
            <ul class="version-list">
${items.map(versionItem).join('\n')}
            </ul>
        </section>`).join('\n');

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
            max-width: 640px;
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
        .version-section + .version-section {
            margin-top: 1.75rem;
        }
        .section-note {
            color: #8b949e;
            font-size: 0.8125rem;
            margin: -0.375rem 0 0.75rem;
        }
        .version-section.latest .version-list li {
            border-color: rgba(88, 166, 255, 0.45);
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
            flex-wrap: wrap;
            justify-content: space-between;
            gap: 0.5rem 1rem;
        }
        .version-name {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
            font-size: 0.9375rem;
            color: #e6edf3;
            white-space: nowrap;
        }
        .version-links {
            display: flex;
            flex-shrink: 0;
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
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">Hammerspoon 2</div>
        <p class="subtitle">API Documentation</p>
${sections}
    </div>
</body>
</html>
`;

    const outputPath = path.join(siteDir, 'index.html');
    fs.writeFileSync(outputPath, html);
    console.log(`  ✓ Generated root version index (${versions.length} version${versions.length === 1 ? '' : 's'})`);
}
