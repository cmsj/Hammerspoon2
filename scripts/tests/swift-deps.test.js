/**
 * Tests for scripts/swift-deps.js.
 *
 * Run with: npm run test:scripts
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const {
    githubRepo,
    parseResolved,
    parseRequirements,
    parseVersion,
    latestRelease,
    versionAllowed,
    diffPins,
    renderUpdateSummary,
    forkAdvice,
    collectForks,
    collectOutOfRange,
    renderForkReport,
    REPORT_MARKER,
} = require('../swift-deps');

const SHA_A = 'a'.repeat(40);
const SHA_B = 'b'.repeat(40);
const SHA_C = 'c'.repeat(40);

function resolved(pins) {
    return JSON.stringify({
        originHash: 'x',
        pins: pins.map(({ identity, location, ...state }) => ({ identity, kind: 'remoteSourceControl', location, state })),
        version: 3,
    });
}

const PBXPROJ = `
/* Begin XCRemoteSwiftPackageReference section */
		4F463E9E2EA7A669000A2135 /* XCRemoteSwiftPackageReference "AXSwift" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/Hammerspoon/AXSwift";
			requirement = {
				branch = main;
				kind = branch;
			};
		};
		4F488B2E2E97E79800A2B5F4 /* XCRemoteSwiftPackageReference "Sparkle" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sparkle-project/Sparkle.git";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.8.0;
			};
		};
		4F5C1A7E2F00000000000010 /* XCRemoteSwiftPackageReference "Ranged" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/example/Ranged";
			requirement = {
				kind = versionRange;
				maximumVersion = 3.0.0;
				minimumVersion = 1.5.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */
`;

// A fake GitHub API: maps request paths (query strings included) to responses.
function fakeAPI(routes) {
    const requested = [];
    const api = async (apiPath) => {
        requested.push(apiPath);
        if (!(apiPath in routes)) {
            throw new Error(`GET ${apiPath} failed: 404`);
        }
        return routes[apiPath];
    };
    api.requested = requested;
    return api;
}

const tags = (...names) => names.map(name => ({ name }));

test('githubRepo extracts owner/repo from GitHub URLs only', () => {
    assert.equal(githubRepo('https://github.com/Hammerspoon/AXSwift'), 'Hammerspoon/AXSwift');
    assert.equal(githubRepo('https://github.com/sparkle-project/Sparkle.git'), 'sparkle-project/Sparkle');
    assert.equal(githubRepo('https://github.com/a/b/'), 'a/b');
    assert.equal(githubRepo('https://gitlab.com/a/b'), null);
    assert.equal(githubRepo(undefined), null);
});

test('parseResolved reads branch and version pins', () => {
    const pins = parseResolved(resolved([
        { identity: 'axswift', location: 'https://github.com/Hammerspoon/AXSwift', branch: 'main', revision: SHA_A },
        { identity: 'sparkle', location: 'https://github.com/sparkle-project/Sparkle', revision: SHA_B, version: '2.9.6' },
    ]));
    assert.deepEqual(pins, [
        { identity: 'axswift', location: 'https://github.com/Hammerspoon/AXSwift', repo: 'Hammerspoon/AXSwift', branch: 'main', revision: SHA_A, version: null },
        { identity: 'sparkle', location: 'https://github.com/sparkle-project/Sparkle', repo: 'sparkle-project/Sparkle', branch: null, revision: SHA_B, version: '2.9.6' },
    ]);
});

test('parseRequirements reads each package reference, keyed by lowercased repo', () => {
    const requirements = parseRequirements(PBXPROJ);
    assert.deepEqual([...requirements.keys()], ['hammerspoon/axswift', 'sparkle-project/sparkle', 'example/ranged']);
    assert.deepEqual(requirements.get('hammerspoon/axswift'), { branch: 'main', kind: 'branch' });
    assert.deepEqual(requirements.get('sparkle-project/sparkle'), { kind: 'upToNextMajorVersion', minimumVersion: '2.8.0' });
    assert.deepEqual(requirements.get('example/ranged'), { kind: 'versionRange', maximumVersion: '3.0.0', minimumVersion: '1.5.0' });
});

test('parseVersion accepts release tags and rejects pre-releases', () => {
    assert.deepEqual(parseVersion('2.10.1'), [2, 10, 1]);
    assert.deepEqual(parseVersion('v1.5'), [1, 5, 0]);
    assert.equal(parseVersion('2.0.0-beta.1'), null);
    assert.equal(parseVersion('tt-v1.6'), null);
    assert.equal(parseVersion(null), null);
});

test('latestRelease compares numerically, not lexically', () => {
    assert.deepEqual(latestRelease(['2.9.6', 'v1.23.0', '2.10.1', '3.0.0-beta1', 'nightly']), { tag: '2.10.1', version: [2, 10, 1] });
    assert.equal(latestRelease(['nightly']), null);
});

test('versionAllowed follows Xcode requirement kinds', () => {
    const major = { kind: 'upToNextMajorVersion', minimumVersion: '2.8.0' };
    assert.equal(versionAllowed(major, [2, 10, 1]), true);
    assert.equal(versionAllowed(major, [3, 0, 0]), false);
    assert.equal(versionAllowed(major, [2, 7, 0]), false);

    const minor = { kind: 'upToNextMinorVersion', minimumVersion: '1.2.0' };
    assert.equal(versionAllowed(minor, [1, 2, 9]), true);
    assert.equal(versionAllowed(minor, [1, 3, 0]), false);

    const range = { kind: 'versionRange', minimumVersion: '1.5.0', maximumVersion: '3.0.0' };
    assert.equal(versionAllowed(range, [2, 99, 0]), true);
    assert.equal(versionAllowed(range, [3, 0, 0]), false);

    assert.equal(versionAllowed({ kind: 'exactVersion', version: '1.0.0' }, [1, 0, 1]), false);
    assert.equal(versionAllowed({ kind: 'branch', branch: 'main' }, [1, 0, 0]), null);
});

test('diffPins reports updated, added and removed packages, and skips unchanged ones', () => {
    const oldPins = parseResolved(resolved([
        { identity: 'axswift', location: 'https://github.com/Hammerspoon/AXSwift', branch: 'main', revision: SHA_A },
        { identity: 'gone', location: 'https://github.com/x/gone', revision: SHA_A, version: '1.0.0' },
        { identity: 'sparkle', location: 'https://github.com/sparkle-project/Sparkle', revision: SHA_A, version: '2.9.6' },
    ]));
    const newPins = parseResolved(resolved([
        { identity: 'axswift', location: 'https://github.com/Hammerspoon/AXSwift', branch: 'main', revision: SHA_A },
        { identity: 'new', location: 'https://github.com/x/new', revision: SHA_C, version: '0.1.0' },
        { identity: 'sparkle', location: 'https://github.com/sparkle-project/Sparkle', revision: SHA_B, version: '2.10.1' },
    ]));
    const changes = diffPins(oldPins, newPins);
    assert.deepEqual(changes.map(({ identity, from, to }) => [identity, Boolean(from), Boolean(to)]), [
        ['gone', true, false],
        ['new', false, true],
        ['sparkle', true, true],
    ]);

    const summary = renderUpdateSummary(changes);
    assert.match(summary, /\| \[sparkle\]\(https:\/\/github\.com\/sparkle-project\/Sparkle\) \| 2\.9\.6 \| 2\.10\.1 \| \[Diff\]\(https:\/\/github\.com\/sparkle-project\/Sparkle\/compare\/a{40}\.\.\.b{40}\) \|/);
    assert.match(summary, /\| \[new\]\(https:\/\/github\.com\/x\/new\) \| \| 0\.1\.0 \| New dependency \|/);
    assert.match(summary, /\| \[gone\]\(https:\/\/github\.com\/x\/gone\) \| 1\.0\.0 \| \| No longer a dependency \|/);
});

test('renderUpdateSummary shows branch pins as branch@revision', () => {
    const changes = diffPins(
        parseResolved(resolved([{ identity: 'axswift', location: 'https://github.com/Hammerspoon/AXSwift', branch: 'main', revision: SHA_A }])),
        parseResolved(resolved([{ identity: 'axswift', location: 'https://github.com/Hammerspoon/AXSwift', branch: 'main', revision: SHA_B }]))
    );
    assert.match(renderUpdateSummary(changes), /\| main@aaaaaaa \| main@bbbbbbb \|/);
    assert.equal(renderUpdateSummary([]), 'No Swift package updates.');
});

test('forkAdvice suggests re-syncing or dropping the fork only when there is something to do', () => {
    assert.deepEqual(forkAdvice({ ahead: 4, behind: 0 }), { actionable: false, text: 'Up to date' });
    assert.equal(forkAdvice({ ahead: 4, behind: 2 }).text, 'Re-sync: merge upstream into the fork');
    assert.equal(forkAdvice({ ahead: 0, behind: 5 }).actionable, true);
    assert.match(forkAdvice({ ahead: 0, behind: 5 }).text, /upstream directly/);
    assert.match(forkAdvice({ ahead: 0, behind: 0 }).text, /^Identical to upstream/);
});

test('collectForks compares our forks with their parent and root, and ignores everything else', async () => {
    const pins = parseResolved(resolved([
        { identity: 'axswift', location: 'https://github.com/Hammerspoon/AXSwift', branch: 'main', revision: SHA_A },
        { identity: 'mqtt', location: 'https://github.com/Hammerspoon/swift-mqtt', revision: SHA_B, version: '1.0.0' },
        { identity: 'mine', location: 'https://github.com/Hammerspoon/not-a-fork', branch: 'main', revision: SHA_C },
        { identity: 'theirs', location: 'https://github.com/someone/their-fork', branch: 'main', revision: SHA_C },
    ]));
    const api = fakeAPI({
        '/repos/Hammerspoon/AXSwift': {
            full_name: 'Hammerspoon/AXSwift', fork: true,
            parent: { full_name: 'mredig/AXSwift', default_branch: 'main' },
            source: { full_name: 'tmandry/AXSwift', default_branch: 'main' },
        },
        '/repos/Hammerspoon/AXSwift/compare/mredig%3Amain...main': { ahead_by: 4, behind_by: 0 },
        '/repos/Hammerspoon/AXSwift/compare/tmandry%3Amain...main': { ahead_by: 43, behind_by: 2 },
        '/repos/mredig/AXSwift/tags?per_page=100&page=1': tags('0.3.2', '0.3.10'),
        '/repos/tmandry/AXSwift/tags?per_page=100&page=1': [],
        '/repos/Hammerspoon/swift-mqtt': {
            full_name: 'Hammerspoon/swift-mqtt', fork: true,
            parent: { full_name: 'emqx/swift-mqtt', default_branch: 'main' },
            source: { full_name: 'emqx/swift-mqtt', default_branch: 'main' },
        },
        [`/repos/Hammerspoon/swift-mqtt/compare/emqx%3Amain...${SHA_B}`]: { ahead_by: 0, behind_by: 7 },
        '/repos/emqx/swift-mqtt/tags?per_page=100&page=1': tags('v1.5.2'),
        '/repos/Hammerspoon/not-a-fork': { full_name: 'Hammerspoon/not-a-fork', fork: false },
    });

    const forks = await collectForks(api, pins, 'HAMMERSPOON');
    assert.deepEqual(forks, [
        { identity: 'axswift', repo: 'Hammerspoon/AXSwift', ref: 'main', upstream: 'mredig/AXSwift', upstreamBranch: 'main', ahead: 4, behind: 0, latestRelease: '0.3.10' },
        { identity: 'axswift', repo: 'Hammerspoon/AXSwift', ref: 'main', upstream: 'tmandry/AXSwift', upstreamBranch: 'main', ahead: 43, behind: 2, latestRelease: null },
        { identity: 'mqtt', repo: 'Hammerspoon/swift-mqtt', ref: SHA_B, upstream: 'emqx/swift-mqtt', upstreamBranch: 'main', ahead: 0, behind: 7, latestRelease: 'v1.5.2' },
    ]);
    assert.ok(!api.requested.some(apiPath => apiPath.includes('someone')), 'other people\'s forks are never looked up');
});

test('collectOutOfRange lists only newer releases the requirement rules out', async () => {
    const pins = parseResolved(resolved([
        { identity: 'sparkle', location: 'https://github.com/sparkle-project/Sparkle', revision: SHA_A, version: '2.9.6' },
        { identity: 'ranged', location: 'https://github.com/example/Ranged', revision: SHA_A, version: '2.0.0' },
        { identity: 'axswift', location: 'https://github.com/Hammerspoon/AXSwift', branch: 'main', revision: SHA_A },
        { identity: 'transitive', location: 'https://github.com/x/transitive', revision: SHA_A, version: '1.0.0' },
    ]));
    const api = fakeAPI({
        // Sparkle's next release is still in range: re-resolving will get it, so it's not listed.
        '/repos/sparkle-project/Sparkle/tags?per_page=100&page=1': tags('2.10.1', '3.0.0-beta.1', 'v1.23.0'),
        '/repos/example/Ranged/tags?per_page=100&page=1': tags('2.0.0', '3.1.0'),
    });

    assert.deepEqual(await collectOutOfRange(api, pins, parseRequirements(PBXPROJ)), [
        { identity: 'ranged', repo: 'example/Ranged', current: '2.0.0', latest: '3.1.0', requirement: '1.5.0 up to 3.0.0' },
    ]);
    assert.ok(!api.requested.some(apiPath => apiPath.includes('transitive')), 'packages without a requirement are skipped');
});

test('collectOutOfRange follows tag pagination', async () => {
    const pins = parseResolved(resolved([
        { identity: 'sparkle', location: 'https://github.com/sparkle-project/Sparkle', revision: SHA_A, version: '2.9.6' },
    ]));
    const firstPage = Array.from({ length: 100 }, (_, i) => ({ name: `1.0.${i}` }));
    const api = fakeAPI({
        '/repos/sparkle-project/Sparkle/tags?per_page=100&page=1': firstPage,
        '/repos/sparkle-project/Sparkle/tags?per_page=100&page=2': tags('3.0.0'),
    });
    const [entry] = await collectOutOfRange(api, pins, parseRequirements(PBXPROJ));
    assert.equal(entry.latest, '3.0.0');
});

test('renderForkReport is actionable only when a fork or version needs attention', () => {
    const upToDate = { identity: 'axswift', repo: 'Hammerspoon/AXSwift', ref: 'main', upstream: 'mredig/AXSwift', upstreamBranch: 'main', ahead: 4, behind: 0, latestRelease: '0.3.2' };
    const quiet = renderForkReport([upToDate], []);
    assert.equal(quiet.actionable, false);
    assert.ok(quiet.body.startsWith(REPORT_MARKER));
    assert.match(quiet.body, /\| axswift \| \[Hammerspoon\/AXSwift@main\]\(https:\/\/github\.com\/Hammerspoon\/AXSwift\/tree\/main\) \| \[mredig\/AXSwift@main\]\(https:\/\/github\.com\/mredig\/AXSwift\) \| 4 \| 0 \| 0\.3\.2 \| Up to date \|/);

    const behind = { ...upToDate, identity: 'mqtt', repo: 'Hammerspoon/swift-mqtt', ref: SHA_B, upstream: 'emqx/swift-mqtt', ahead: 2, behind: 7, latestRelease: null };
    const resync = renderForkReport([upToDate, behind], [], { runURL: 'https://example.com/run/1' });
    assert.equal(resync.actionable, true);
    assert.match(resync.body, /\[Hammerspoon\/swift-mqtt@bbbbbbb\]/);
    assert.match(resync.body, new RegExp(`\\| \\[7\\]\\(https://github\\.com/Hammerspoon/swift-mqtt/compare/${SHA_B}\\.\\.\\.emqx:main\\) \\| None \\| \\*\\*Re-sync`));
    assert.match(resync.body, /\[this run\]\(https:\/\/example\.com\/run\/1\)/);

    const outOfRange = renderForkReport([], [{ identity: 'ranged', repo: 'example/Ranged', current: '2.0.0', latest: '3.1.0', requirement: '1.5.0 up to 3.0.0' }]);
    assert.equal(outOfRange.actionable, true);
    assert.match(outOfRange.body, /None of the Swift packages are our forks\./);
    assert.match(outOfRange.body, /\| \[ranged\]\(https:\/\/github\.com\/example\/Ranged\/releases\) \| 2\.0\.0 \| 3\.1\.0 \| 1\.5\.0 up to 3\.0\.0 \|/);
});
