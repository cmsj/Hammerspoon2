/**
 * Tests for scripts/release/update-appcast.js.
 *
 * Run with: npm run test:scripts
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const { updateAppcast } = require('../release/update-appcast');

const PREFIX = 'https://github.com/cmsj/Hammerspoon2/releases/download/0.0.16/';

function metadata(overrides = {}) {
    return {
        version: '0.0.16',
        build: '2100',
        minimumSystemVersion: '26.0',
        archive: { name: 'Hammerspoon-2-0.0.16.zip', length: 9000000, edSignature: 'ARCHIVESIG==' },
        deltas: [
            { from: '2050', name: 'Hammerspoon-2-2100-2050.delta', length: 120000, edSignature: 'DELTASIG==' },
        ],
        ...overrides,
    };
}

function update(existing, { metadata: metadataOverrides, ...overrides } = {}) {
    return updateAppcast(existing, {
        metadata: metadata(metadataOverrides),
        notesHtml: '<h2>Fixed</h2><ul><li>Things</li></ul>',
        downloadPrefix: PREFIX,
        releaseUrl: 'https://github.com/cmsj/Hammerspoon2/releases/tag/0.0.16',
        pubDate: '2026-10-16T12:00:00Z',
        ...overrides,
    });
}

test('creates a feed from nothing with the archive and its deltas', () => {
    const xml = update('');

    assert.match(xml, /^<\?xml version="1.0" encoding="utf-8"\?>/);
    assert.match(xml, /xmlns:sparkle="http:\/\/www.andymatuschak.org\/xml-namespaces\/sparkle"/);
    assert.match(xml, /<sparkle:version>2100<\/sparkle:version>/);
    assert.match(xml, /<sparkle:shortVersionString>0.0.16<\/sparkle:shortVersionString>/);
    assert.match(xml, /<sparkle:minimumSystemVersion>26.0<\/sparkle:minimumSystemVersion>/);
    assert.match(xml, /<pubDate>Fri, 16 Oct 2026 12:00:00 GMT<\/pubDate>/);
    assert.match(xml, new RegExp(
        `<enclosure url="${PREFIX}Hammerspoon-2-0.0.16.zip" length="9000000" type="application/octet-stream" sparkle:edSignature="ARCHIVESIG=="/>`
    ));
    assert.match(xml, /sparkle:deltaFrom="2050" length="120000"/);
    assert.match(xml, /<description><!\[CDATA\[<h2>Fixed<\/h2><ul><li>Things<\/li><\/ul>\]\]><\/description>/);
});

test('puts the newest release first and keeps older ones', () => {
    const first = update('', { metadata: { version: '0.0.15', build: '2050', deltas: [] } });
    const second = update(first);

    assert.equal((second.match(/<item>/g) ?? []).length, 2);
    assert.ok(second.indexOf('<sparkle:version>2100<') < second.indexOf('<sparkle:version>2050<'));
});

test('replaces an existing item for the same build instead of duplicating it', () => {
    const first = update('', { notesHtml: 'first notes' });
    const second = update(first, { notesHtml: 'second notes' });

    assert.equal((second.match(/<item>/g) ?? []).length, 1);
    assert.doesNotMatch(second, /first notes/);
    assert.match(second, /second notes/);
});

test('is stable when re-run with identical input', () => {
    const once = update('');
    assert.equal(update(once), once);
});

test('puts prereleases in their channel and leaves releases in the default one', () => {
    assert.match(
        update('', { metadata: { version: '0.0.16-beta.1', channel: 'beta' } }),
        /<sparkle:channel>beta<\/sparkle:channel>/
    );
    assert.doesNotMatch(update(''), /sparkle:channel/);
});

test('omits the deltas element when there are none', () => {
    assert.doesNotMatch(update('', { metadata: { deltas: [] } }), /sparkle:deltas/);
});

test('escapes XML in attributes and keeps CDATA intact', () => {
    const xml = update('', {
        notesHtml: 'a ]]> b',
        metadata: { archive: { name: 'Hammerspoon 2 & co.zip', length: 1, edSignature: 'S"G' } },
    });

    assert.match(xml, /Hammerspoon%202%20%26%20co.zip/);
    assert.match(xml, /sparkle:edSignature="S&quot;G"/);
    assert.match(xml, /<!\[CDATA\[a ]]]]><!\[CDATA\[> b\]\]>/);
});

test('rejects incomplete metadata', () => {
    assert.throws(() => update('', { metadata: { build: '' } }), /"build" must be a non-empty string/);
    assert.throws(
        () => update('', { metadata: { archive: { name: 'x.zip', length: 0, edSignature: 'S' } } }),
        /"length" must be a positive integer/
    );
    assert.throws(
        () => update('', { metadata: { deltas: [{ name: 'x.delta', length: 1, edSignature: 'S' }] } }),
        /deltas\[0\]: "from"/
    );
});
