/**
 * Tests for scripts/xcresult-report.js. The fixtures are real `xcresulttool get test-results
 * summary` output from Xcode 27 (with the device ID anonymised), so these run anywhere Node does.
 *
 * Run with: npm run test:scripts
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const {
    renderReport,
    hasFailures,
    upsertPRComment,
    COMMENT_MARKER,
    COMMENT_AUTHOR,
} = require('../xcresult-report');

function fixture(name) {
    return JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', `xcresult-summary-${name}.json`), 'utf8'));
}

const passed = fixture('passed');
const failed = fixture('failed');
const skippedOnly = { ...passed, result: 'Skipped', passedTests: 0, skippedTests: passed.totalTestCount };

test('reports totals and no failures for a passing run', () => {
    const report = renderReport(passed);
    assert.equal(hasFailures(passed), false);
    assert.match(report, /^## :white_check_mark: Test Results: Passed/);
    assert.match(report, /\| 17 \| 17 \| 0 \| 0 \| 0 \| 25\.4s \|/);
    assert.match(report, /Ran on: Mac mini, macOS 27\.0\.1/);
    assert.doesNotMatch(report, /### Failures/);
});

test('lists each failure with its message for a failing run', () => {
    const report = renderReport(failed);
    assert.equal(hasFailures(failed), true);
    assert.match(report, /^## :x: Test Results: Failed/);
    assert.match(report, /\*\*FailPkgTests › fails\(\)\*\*\n\n```\nExpectation failed: 1 == 2: one is not two\n```/);
    assert.match(report, /\*\*FailPkgTests › LegacyTests\/testXCTFail\(\)\*\*/);
});

test('treats a run where everything was skipped as not failing', () => {
    assert.equal(hasFailures(skippedOnly), false);
    assert.match(renderReport(skippedOnly), /^## :white_check_mark: Test Results: Skipped/);
});

test('explains a missing result bundle', () => {
    assert.equal(hasFailures(null), true);
    assert.match(renderReport(null), /No test results were produced/);
});

test('fences failure text containing backticks with a longer fence', () => {
    const summary = { ...failed, testFailures: [{ ...failed.testFailures[0], failureText: 'has ``` inside' }] };
    assert.match(renderReport(summary), /````\nhas ``` inside\n````/);
});

test('trims a report that is too long and points at the full one', () => {
    const many = Array.from({ length: 50 }, (_, i) => ({
        ...failed.testFailures[0],
        testIdentifierString: `test${i}()`,
        failureText: 'x'.repeat(10000),
    }));
    const report = renderReport({ ...failed, testFailures: many }, { maxLength: 30000, detailsURL: 'https://run' });
    assert.ok(report.length <= 30000, `report is ${report.length} characters`);
    assert.match(report, /… \(truncated\)/);
    assert.match(report, /…and \d+ more failures; see \[the job summary\]\(https:\/\/run\)\./);
    // Without a limit (the job summary), nothing is left out.
    assert.equal(renderReport({ ...failed, testFailures: many }).match(/x{10000}/g).length, 50);
});

/**
 * Replaces fetch with an in-memory GitHub holding `comments` on PR 7, whose head is `headSha`.
 * Returns the list of write requests made.
 */
function mockGitHub(t, { comments = [], headSha = 'abc' } = {}) {
    const writes = [];
    t.mock.method(globalThis, 'fetch', async (url, { method, body }) => {
        const { pathname } = new URL(url);
        let result;
        if (method === 'GET' && pathname === '/repos/o/r/issues/7/comments') {
            result = comments;
        } else if (method === 'GET' && pathname === '/repos/o/r/pulls/7') {
            result = { head: { sha: headSha } };
        } else {
            writes.push({ method, pathname, body: JSON.parse(body).body });
            result = {};
        }
        return { ok: true, json: async () => result };
    });
    return writes;
}

const prArgs = { repo: 'o/r', prNumber: 7, headSha: 'abc', runURL: 'https://github.com/o/r/actions/runs/1' };
const botComment = { id: 3, user: { login: COMMENT_AUTHOR }, body: `${COMMENT_MARKER}\nold` };

test('does not comment on a PR that has only ever passed', async t => {
    const writes = mockGitHub(t);
    assert.equal(await upsertPRComment({ ...prArgs, summary: passed }), 'skipped');
    assert.deepEqual(writes, []);
});

test('creates a comment when tests fail', async t => {
    const writes = mockGitHub(t);
    assert.equal(await upsertPRComment({ ...prArgs, summary: failed }), 'created');
    assert.equal(writes.length, 1);
    assert.equal(writes[0].method, 'POST');
    assert.ok(writes[0].body.startsWith(`${COMMENT_MARKER}\n## :x:`));
    assert.match(writes[0].body, /From \[this run\]\(https:\/\/github\.com\/o\/r\/actions\/runs\/1\) of abc\./);
});

test('updates its earlier comment once tests pass', async t => {
    const writes = mockGitHub(t, { comments: [{ id: 1, user: { login: 'someone' }, body: 'hi' }, botComment] });
    assert.equal(await upsertPRComment({ ...prArgs, summary: passed }), 'updated');
    assert.deepEqual(writes.map(w => [w.method, w.pathname]), [['PATCH', '/repos/o/r/issues/comments/3']]);
    assert.match(writes[0].body, /:white_check_mark:/);
});

test("ignores someone else's comment that contains the marker", async t => {
    const writes = mockGitHub(t, { comments: [{ ...botComment, user: { login: 'someone' } }] });
    assert.equal(await upsertPRComment({ ...prArgs, summary: failed }), 'created');
    assert.equal(writes[0].method, 'POST');
});

test('leaves the comment alone when the run is for an outdated commit', async t => {
    const writes = mockGitHub(t, { comments: [botComment], headSha: 'newer' });
    assert.equal(await upsertPRComment({ ...prArgs, summary: failed }), 'outdated');
    assert.deepEqual(writes, []);
});
