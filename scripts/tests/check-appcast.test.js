/**
 * Tests for scripts/release/check-appcast.js.
 *
 * Run with: npm run test:scripts
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const { checkAppcast } = require('../release/check-appcast');

const SIGNATURE = '<!-- sparkle-signatures:\nedSignature: abc==\nlength: 123\n-->\n';

// Each entry is a build number, or [build, notes] to vary the item's content.
function feed(builds, { signed = true } = {}) {
    const items = builds.map((entry) => {
        const [build, notes = 'notes'] = Array.isArray(entry) ? entry : [entry];
        return `<item><sparkle:version>${build}</sparkle:version><description>${notes}</description></item>`;
    }).join('');
    return `<rss><channel>${items}</channel></rss>${signed ? SIGNATURE : ''}`;
}

function check(overrides = {}) {
    return checkAppcast({
        candidate: feed(['2100', '2050']),
        live: feed(['2050']),
        build: '2100',
        signedNotes: '## Fixed\n- Things\n',
        releaseNotes: '## Fixed\n- Things\n',
        ...overrides,
    });
}

test('accepts a signed feed that adds the release to the live one', () => {
    assert.deepEqual(check(), []);
});

test('accepts the first release when nothing is live yet', () => {
    assert.deepEqual(check({ candidate: feed(['2100']), live: '' }), []);
});

test('rejects an unsigned feed', () => {
    assert.deepEqual(check({ candidate: feed(['2100', '2050'], { signed: false }) }), ['appcast.xml is not signed']);
});

test('rejects a feed without the release in it', () => {
    assert.match(check({ candidate: feed(['2050']) }).join('\n'), /no item for build 2100/);
});

test('rejects a feed that would drop a release published since it was built', () => {
    const problems = check({ live: feed(['2150', '2050']) });
    assert.match(problems.join('\n'), /would drop build\(s\) 2150/);
});

test('rejects notes edited on GitHub after signing', () => {
    const problems = check({ releaseNotes: '## Fixed\n- Different things\n' });
    assert.match(problems.join('\n'), /release notes on GitHub differ/);
});

test("ignores GitHub's CRLF line endings and trailing whitespace in notes", () => {
    assert.deepEqual(check({ releaseNotes: '## Fixed\r\n- Things' }), []);
});

test('rejects a feed that would revert an item updated since it was built', () => {
    const problems = check({ live: feed([['2050', 'corrected notes']]) });
    assert.match(problems.join('\n'), /would revert build\(s\) 2050/);
});

test('allows the release being published to differ from its live item', () => {
    assert.deepEqual(check({ live: feed([['2100', 'old notes'], '2050']) }), []);
});
