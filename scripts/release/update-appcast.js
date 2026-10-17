#!/usr/bin/env node
/**
 * Merge one release into the Sparkle appcast.
 *
 * The release script (scripts/release/release.sh) writes a sparkle.json
 * describing the signed archive and any binary deltas, then feeds it, plus
 * the rendered release notes, through this script to add the release to the
 * appcast.xml served from GitHub Pages, which it then signs.
 *
 * Usage:
 *   node scripts/release/update-appcast.js \
 *     --appcast site/appcast.xml \
 *     --metadata sparkle.json \
 *     --notes-html notes.html \
 *     --download-prefix https://github.com/OWNER/REPO/releases/download/TAG/ \
 *     --release-url https://github.com/OWNER/REPO/releases/tag/TAG \
 *     [--pub-date 2026-10-16T12:00:00Z]
 *
 * Items are keyed by sparkle:version (CFBundleVersion), so re-running for the
 * same release replaces its item rather than duplicating it.
 */

'use strict';

const fs = require('fs');
const { parseArgs } = require('util');

const FEED_TITLE = 'Hammerspoon 2';
const FEED_LINK = 'https://github.com/cmsj/Hammerspoon2';

function escapeXml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}

function cdata(text) {
    // A literal "]]>" would terminate the section early, so split it across two.
    return `<![CDATA[${String(text).replace(/]]>/g, ']]]]><![CDATA[>')}]]>`;
}

function requireString(object, key, context) {
    const value = object[key];
    if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${context}: "${key}" must be a non-empty string`);
    }
    return value;
}

function requireLength(object, context) {
    const value = object.length;
    if (!Number.isInteger(value) || value <= 0) {
        throw new Error(`${context}: "length" must be a positive integer`);
    }
    return value;
}

function validateMetadata(metadata) {
    if (metadata === null || typeof metadata !== 'object') {
        throw new Error('metadata must be a JSON object');
    }
    requireString(metadata, 'version', 'metadata');
    requireString(metadata, 'build', 'metadata');
    requireString(metadata, 'minimumSystemVersion', 'metadata');
    if (metadata.channel !== undefined) {
        requireString(metadata, 'channel', 'metadata');
    }

    if (metadata.archive === null || typeof metadata.archive !== 'object') {
        throw new Error('metadata: "archive" must be an object');
    }
    requireString(metadata.archive, 'name', 'metadata.archive');
    requireString(metadata.archive, 'edSignature', 'metadata.archive');
    requireLength(metadata.archive, 'metadata.archive');

    const deltas = metadata.deltas ?? [];
    if (!Array.isArray(deltas)) {
        throw new Error('metadata: "deltas" must be an array');
    }
    deltas.forEach((delta, index) => {
        const context = `metadata.deltas[${index}]`;
        requireString(delta, 'from', context);
        requireString(delta, 'name', context);
        requireString(delta, 'edSignature', context);
        requireLength(delta, context);
    });
}

function buildItem({ metadata, notesHtml, downloadPrefix, releaseUrl, pubDate }) {
    validateMetadata(metadata);

    const prefix = downloadPrefix.endsWith('/') ? downloadPrefix : `${downloadPrefix}/`;
    const assetUrl = (name) => prefix + encodeURIComponent(name);
    const date = pubDate ? new Date(pubDate) : new Date();
    if (Number.isNaN(date.getTime())) {
        throw new Error(`invalid pub date: ${pubDate}`);
    }

    const lines = [
        '    <item>',
        `      <title>${escapeXml(`${FEED_TITLE} ${metadata.version}`)}</title>`,
        `      <pubDate>${date.toUTCString()}</pubDate>`,
        `      <sparkle:version>${escapeXml(metadata.build)}</sparkle:version>`,
        `      <sparkle:shortVersionString>${escapeXml(metadata.version)}</sparkle:shortVersionString>`,
        `      <sparkle:minimumSystemVersion>${escapeXml(metadata.minimumSystemVersion)}</sparkle:minimumSystemVersion>`,
    ];
    if (metadata.channel) {
        // Only installs that opt in to the channel are offered this item.
        lines.push(`      <sparkle:channel>${escapeXml(metadata.channel)}</sparkle:channel>`);
    }
    if (releaseUrl) {
        lines.push(`      <sparkle:fullReleaseNotesLink>${escapeXml(releaseUrl)}</sparkle:fullReleaseNotesLink>`);
    }
    if (notesHtml && notesHtml.trim().length > 0) {
        lines.push(`      <description>${cdata(notesHtml.trim())}</description>`);
    }
    lines.push(
        `      <enclosure url="${escapeXml(assetUrl(metadata.archive.name))}"` +
        ` length="${metadata.archive.length}"` +
        ' type="application/octet-stream"' +
        ` sparkle:edSignature="${escapeXml(metadata.archive.edSignature)}"/>`
    );

    const deltas = metadata.deltas ?? [];
    if (deltas.length > 0) {
        lines.push('      <sparkle:deltas>');
        for (const delta of deltas) {
            lines.push(
                `        <enclosure url="${escapeXml(assetUrl(delta.name))}"` +
                ` sparkle:deltaFrom="${escapeXml(delta.from)}"` +
                ` length="${delta.length}"` +
                ' type="application/octet-stream"' +
                ` sparkle:edSignature="${escapeXml(delta.edSignature)}"/>`
            );
        }
        lines.push('      </sparkle:deltas>');
    }
    lines.push('    </item>');
    return lines.join('\n');
}

function extractItems(appcastXml) {
    if (!appcastXml) {
        return [];
    }
    return appcastXml.match(/<item>[\s\S]*?<\/item>/g) ?? [];
}

function itemVersion(itemXml) {
    const match = itemXml.match(/<sparkle:version>([\s\S]*?)<\/sparkle:version>/);
    return match ? match[1].trim() : null;
}

function normaliseIndent(itemXml) {
    // Items lifted out of an existing feed lose the indentation before <item>.
    return itemXml.startsWith('    ') ? itemXml : `    ${itemXml}`;
}

/**
 * Return the new appcast XML with the item for `metadata` added at the top,
 * replacing any existing item with the same build number.
 */
function updateAppcast(existingXml, options) {
    const newItem = buildItem(options);
    const build = escapeXml(options.metadata.build);
    const kept = extractItems(existingXml)
        .filter((item) => itemVersion(item) !== build)
        .map(normaliseIndent);

    return [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">',
        '  <channel>',
        `    <title>${escapeXml(FEED_TITLE)}</title>`,
        `    <link>${escapeXml(FEED_LINK)}</link>`,
        `    <description>${escapeXml(`Most recent releases of ${FEED_TITLE}`)}</description>`,
        '    <language>en</language>',
        newItem,
        ...kept,
        '  </channel>',
        '</rss>',
        '',
    ].join('\n');
}

function main() {
    const { values } = parseArgs({
        options: {
            appcast: { type: 'string' },
            metadata: { type: 'string' },
            'notes-html': { type: 'string' },
            'download-prefix': { type: 'string' },
            'release-url': { type: 'string' },
            'pub-date': { type: 'string' },
        },
    });

    for (const required of ['appcast', 'metadata', 'download-prefix']) {
        if (!values[required]) {
            console.error(`Missing required option --${required}`);
            process.exit(2);
        }
    }

    const existingXml = fs.existsSync(values.appcast) ? fs.readFileSync(values.appcast, 'utf8') : '';
    const metadata = JSON.parse(fs.readFileSync(values.metadata, 'utf8'));
    const notesHtml = values['notes-html'] ? fs.readFileSync(values['notes-html'], 'utf8') : '';

    const xml = updateAppcast(existingXml, {
        metadata,
        notesHtml,
        downloadPrefix: values['download-prefix'],
        releaseUrl: values['release-url'],
        pubDate: values['pub-date'],
    });
    fs.writeFileSync(values.appcast, xml);
    console.log(`Updated ${values.appcast} with ${metadata.version} (build ${metadata.build})`);
}

if (require.main === module) {
    try {
        main();
    } catch (error) {
        console.error(`update-appcast: ${error.message}`);
        process.exit(1);
    }
}

module.exports = { updateAppcast, buildItem, validateMetadata };
