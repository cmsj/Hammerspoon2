#!/usr/bin/env node
/**
 * Sanity-check a signed appcast before the appcast workflow publishes it.
 *
 * scripts/release/release.sh builds and signs appcast.xml locally and attaches
 * it to the GitHub release. CI can't re-sign it, so all it can do is refuse to
 * publish one that's stale. This catches:
 *
 *   - an appcast that doesn't contain the release it's attached to
 *   - an appcast built before another release was published, which would drop
 *     that release from the live feed
 *   - an appcast built before another release's item was updated (say by
 *     `--update-appcast` after its notes were corrected), which would revert
 *     that item
 *   - release notes edited on GitHub after the appcast was signed, which would
 *     leave the old notes in Sparkle's update window
 *   - an appcast with no signature at all
 *
 * The fix for each is to run `scripts/release/release.sh --update-appcast <tag>`
 * and re-run the workflow.
 *
 * Usage:
 *   node scripts/release/check-appcast.js \
 *     --candidate appcast.xml \
 *     --live site/appcast.xml \
 *     --metadata sparkle.json \
 *     --signed-notes release-notes.md \
 *     --release-notes release-body.md
 */

'use strict';

const fs = require('fs');
const { parseArgs } = require('util');

const SIGNATURE_PREFIX = '<!-- sparkle-signatures:\n';

function itemVersions(appcastXml) {
    const versions = [];
    for (const match of (appcastXml ?? '').matchAll(/<sparkle:version>([\s\S]*?)<\/sparkle:version>/g)) {
        versions.push(match[1].trim());
    }
    return versions;
}

/** Map each item's sparkle:version to the item's XML. */
function itemsByVersion(appcastXml) {
    const items = new Map();
    for (const item of (appcastXml ?? '').match(/<item>[\s\S]*?<\/item>/g) ?? []) {
        const version = itemVersions(item)[0];
        if (version !== undefined) {
            items.set(version, item);
        }
    }
    return items;
}

function normaliseNotes(text) {
    // GitHub stores notes edited in its web UI with CRLF line endings and may
    // drop the trailing newline, neither of which is a real change.
    return (text ?? '').replace(/\r\n?/g, '\n').trim();
}

/** Return a list of human-readable problems; empty means the candidate is fine to publish. */
function checkAppcast({ candidate, live, build, signedNotes, releaseNotes }) {
    const problems = [];

    if (!candidate.includes(SIGNATURE_PREFIX)) {
        problems.push('appcast.xml is not signed');
    }

    const candidateItems = itemsByVersion(candidate);
    if (!candidateItems.has(build)) {
        problems.push(`appcast.xml has no item for build ${build}`);
    }

    // Every other release must come through exactly as it is live.
    const missing = [];
    const changed = [];
    for (const [version, item] of itemsByVersion(live)) {
        if (version === build) {
            continue;
        }
        if (!candidateItems.has(version)) {
            missing.push(version);
        } else if (candidateItems.get(version).trim() !== item.trim()) {
            changed.push(version);
        }
    }
    if (missing.length > 0) {
        problems.push(
            `appcast.xml would drop build(s) ${missing.join(', ')} from the live feed; ` +
            'it was probably built before another release was published'
        );
    }
    if (changed.length > 0) {
        problems.push(
            `appcast.xml would revert build(s) ${changed.join(', ')} to an older version of their items; ` +
            'it was probably built before they were updated'
        );
    }

    if (normaliseNotes(signedNotes) !== normaliseNotes(releaseNotes)) {
        problems.push('the release notes on GitHub differ from the notes signed into appcast.xml');
    }

    return problems;
}

function main() {
    const { values } = parseArgs({
        options: {
            candidate: { type: 'string' },
            live: { type: 'string' },
            metadata: { type: 'string' },
            'signed-notes': { type: 'string' },
            'release-notes': { type: 'string' },
        },
    });

    for (const required of ['candidate', 'metadata', 'signed-notes', 'release-notes']) {
        if (!values[required]) {
            console.error(`Missing required option --${required}`);
            process.exit(2);
        }
    }

    const read = (path) => fs.readFileSync(path, 'utf8');
    const metadata = JSON.parse(read(values.metadata));
    const problems = checkAppcast({
        candidate: read(values.candidate),
        live: values.live && fs.existsSync(values.live) ? read(values.live) : '',
        build: metadata.build,
        signedNotes: read(values['signed-notes']),
        releaseNotes: read(values['release-notes']),
    });

    if (problems.length > 0) {
        for (const problem of problems) {
            console.error(`::error::${problem}`);
        }
        console.error(
            `Run \`scripts/release/release.sh --update-appcast ${metadata.version}\` to rebuild and re-sign it, ` +
            'then re-run this workflow.'
        );
        process.exit(1);
    }
    console.log(`appcast.xml for ${metadata.version} (build ${metadata.build}) is ready to publish`);
}

if (require.main === module) {
    main();
}

module.exports = { checkAppcast, itemVersions, itemsByVersion, normaliseNotes };
