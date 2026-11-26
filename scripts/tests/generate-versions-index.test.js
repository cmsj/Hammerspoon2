/**
 * Tests for scripts/generate-versions-index.js.
 *
 * Run with: npm run test:scripts
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const { comparePrerelease, sortVersions, groupVersions } = require('../generate-versions-index');

test('prereleases of the same version sort newest first', () => {
    assert.deepEqual(
        sortVersions(['1.0.0-beta.1', '1.0.0-beta.3', '1.0.0-beta.2']),
        ['1.0.0-beta.3', '1.0.0-beta.2', '1.0.0-beta.1']
    );
});

test('numeric prerelease identifiers compare numerically', () => {
    assert.deepEqual(sortVersions(['1.0.0-beta.2', '1.0.0-beta.10']), ['1.0.0-beta.10', '1.0.0-beta.2']);
});

test('a release outranks its prereleases, and main stays first', () => {
    assert.deepEqual(
        sortVersions(['1.0.0-beta.1', 'feature-x', '1.0.0', 'main', '1.0.0-rc.1', '0.9.0']),
        ['main', '1.0.0', '1.0.0-rc.1', '1.0.0-beta.1', '0.9.0', 'feature-x']
    );
});

test('comparePrerelease follows semver precedence', () => {
    assert.ok(comparePrerelease('alpha', 'alpha.1') < 0);
    assert.ok(comparePrerelease('alpha.1', 'alpha.beta') < 0);
    assert.ok(comparePrerelease('beta', 'rc') < 0);
    assert.ok(comparePrerelease('rc.1', undefined) < 0);
    assert.equal(comparePrerelease('beta.1', 'beta.1'), 0);
});

test('versions are grouped into latest, developer and previous sections', () => {
    const sorted = sortVersions(['main', '1.0.0-beta.1', '1.0.0-beta.2', '1.0.0-beta.3', 'feature-x']);
    assert.deepEqual(groupVersions(sorted), {
        latest: ['1.0.0-beta.3'],
        developer: ['main'],
        previous: ['1.0.0-beta.2', '1.0.0-beta.1', 'feature-x']
    });
});

test('sections without versions are empty', () => {
    assert.deepEqual(groupVersions(['main']), { latest: [], developer: ['main'], previous: [] });
    assert.deepEqual(groupVersions(['1.0.0']), { latest: ['1.0.0'], developer: [], previous: [] });
});
