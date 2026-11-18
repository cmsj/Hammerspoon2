/**
 * Tests for scripts/symbolicate-crash.js. The crash reports are real ones macOS wrote for a small
 * Objective-C program (scripts/tests/fixtures/crash/CrashFixture.dSYM is its dSYM), renamed to
 * look like Hammerspoon 2 and with our frames' symbols removed, as they are in a release build.
 * They're shared with the Swift tests in Hammerspoon 2Tests/Fixtures/CrashReports.
 *
 * Tests that run atos and dwarfdump only run on macOS.
 *
 * Run with: npm run test:scripts
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const {
    attachmentURLs,
    parseIPS,
    formField,
    crashedVersion,
    backtraces,
    symbolicate,
    renderComment,
    buildComment,
    findReport,
    runForIssue,
    codeBlock,
    COMMENT_AUTHOR,
    COMMENT_MARKER,
    NO_REPORT_COMMENT,
} = require('../symbolicate-crash');

const REPORTS = path.join(__dirname, '..', '..', 'Hammerspoon 2Tests', 'Fixtures', 'CrashReports');
const DSYMS = path.join(__dirname, 'fixtures', 'crash');
const onMac = { skip: process.platform !== 'darwin' && 'needs atos and dwarfdump' };

const abortText = fs.readFileSync(path.join(REPORTS, 'abort.ips'), 'utf8');
const exceptionText = fs.readFileSync(path.join(REPORTS, 'uncaught-exception.ips'), 'utf8');

/** The report the way Hammerspoon 2 writes it: header and body on one line each. */
function compact(text) {
    const { header, body } = parseIPS(text);
    return `${JSON.stringify(header)}\n${JSON.stringify(body)}`;
}

/** An issue body the way GitHub renders the crash report form. */
function issueBody({ version = '0.1.0', crashLog }) {
    return [
        '### What were you doing when it crashed?',
        '',
        '_No response_',
        '',
        '### Hammerspoon 2 version',
        '',
        version,
        '',
        '### Crash log',
        '',
        '```text',
        crashLog,
        '```',
    ].join('\n');
}

test('parses a multi-line .ips file as macOS writes it', () => {
    const report = parseIPS(abortText);
    assert.equal(report.header.app_name, 'Hammerspoon 2');
    assert.equal(report.body.threads.length, 2);
});

test('finds a compact report pasted into the issue form', () => {
    const report = parseIPS(issueBody({ crashLog: compact(abortText) }));
    assert.equal(report.header.incident_id, parseIPS(abortText).header.incident_id);
});

test('finds a full report pasted into the issue form', () => {
    const report = parseIPS(issueBody({ crashLog: abortText.trim() }));
    assert.equal(report.body.procName, 'Hammerspoon 2');
});

test("doesn't mistake other JSON for a report", () => {
    assert.equal(parseIPS('{"not": "a crash"}\n{"threads": []}'), null);
    assert.equal(parseIPS('Hammerspoon 2 crashed, sorry no log'), null);
});

test('finds attachment URLs in both forms GitHub uses', () => {
    const body = issueBody({
        crashLog:
            '[Hammerspoon 2-1.txt](https://github.com/user-attachments/files/123/Hammerspoon.2-1.txt)\n' +
            'https://github.com/cmsj/Hammerspoon2/files/456/crash.txt and ' +
            'https://evil.example.com/user-attachments/files/789/x.txt',
    });
    assert.deepEqual(attachmentURLs(body), [
        'https://github.com/user-attachments/files/123/Hammerspoon.2-1.txt',
        'https://github.com/cmsj/Hammerspoon2/files/456/crash.txt',
    ]);
});

test('prefers an attached report to the text of the issue', async () => {
    const body = issueBody({ crashLog: '[log.txt](https://github.com/user-attachments/files/1/log.txt)' });
    const fetched = [];
    const report = await findReport([body], async url => {
        fetched.push(url);
        return exceptionText;
    });
    assert.deepEqual(fetched, ['https://github.com/user-attachments/files/1/log.txt']);
    assert.equal(report.body.procName, 'HammerspoonIPCBroker');
});

test('finds a report attached to a comment when the issue has none', async () => {
    const body = issueBody({ crashLog: 'The crash log is on your clipboard: select all of this text and paste over it.' });
    const comments = ['Oops, forgot the log', '[log.txt](https://github.com/user-attachments/files/2/log.txt)'];
    const fetched = [];
    const report = await findReport([body, ...comments], async url => {
        fetched.push(url);
        return exceptionText;
    });
    assert.deepEqual(fetched, ['https://github.com/user-attachments/files/2/log.txt']);
    assert.equal(report.body.procName, 'HammerspoonIPCBroker');
    assert.equal(await findReport([body, comments[0]], async () => assert.fail('nothing to download')), null);
});

test('reads the version from the report, or from the form for helpers', () => {
    assert.equal(crashedVersion(parseIPS(abortText), ''), '0.1.0');
    const helper = parseIPS(exceptionText);
    assert.equal(crashedVersion(helper, issueBody({ version: '0.2.0', crashLog: '' })), '0.2.0');
    assert.equal(crashedVersion(helper, issueBody({ version: '_No response_', crashLog: '' })), null);
    assert.equal(crashedVersion(helper, issueBody({ version: '0.2.0; rm -rf /', crashLog: '' })), null);
    assert.equal(formField(issueBody({ crashLog: '' }), 'What were you doing when it crashed?'), null);
    const markdown = parseIPS(abortText);
    markdown.header.app_version = '[0.1.0](https://example.com) @someone';
    assert.equal(crashedVersion(markdown, issueBody({ version: '0.2.0', crashLog: '' })), null);
});

test('lists the exception backtrace and crashed thread before the others', () => {
    const titles = backtraces(parseIPS(exceptionText)).map(trace => trace.title);
    assert.deepEqual(titles, ['Last Exception Backtrace', 'Crashed Thread 0 (com.apple.main-thread)', 'Thread 1 (fixture.worker)']);
});

test('looks up the byte before return addresses, and leaves frames atos can\'t find alone', () => {
    const traces = backtraces(parseIPS(abortText));
    const calls = [];
    symbolicate(traces, new Map([[traces[0].frames[3].image.uuid, { file: '/x.dSYM/Contents/Resources/DWARF/x', arch: 'arm64' }]]), args => {
        calls.push(args);
        return args.addresses.map((address, i) => (i === 0 ? 'parseConfig (in x) (main.m:7)' : address)).join('\n');
    });

    assert.equal(calls.length, 1, 'one atos run per binary');
    const [call] = calls;
    assert.equal(call.arch, 'arm64');
    const first = traces[0].frames[3];
    assert.equal(call.loadAddress, `0x${BigInt(first.image.base).toString(16)}`);
    assert.equal(call.addresses[0], `0x${(first.address - 1n).toString(16)}`);
    assert.equal(first.symbol, 'parseConfig (main.m:7)');
    assert.equal(traces[0].frames[4].symbolicated, undefined);
});

test('keeps issue text from breaking out of its code block', () => {
    assert.equal(codeBlock('a ``` b'), '````text\na ``` b\n````');
});

test('trims other threads to fit in a comment', () => {
    const report = parseIPS(abortText);
    const traces = backtraces(report);
    const other = traces.find(trace => !trace.crashed);
    for (let i = 0; i < 3000; i++) {
        other.frames.push({ ...other.frames[0], index: i });
    }
    const comment = renderComment({ report, traces, version: '0.1.0', notes: ['note'], maxLength: 20000 });
    assert.ok(comment.length <= 20000, `comment is ${comment.length} characters`);
    assert.ok(comment.startsWith(COMMENT_MARKER));
    assert.match(comment, /Crashed Thread 0/);
    assert.match(comment, /cut short to fit/);
});

test('symbolicates our frames with the matching dSYM', onMac, () => {
    const { body: comment, symbolicated } = buildComment({
        report: parseIPS(compact(abortText)),
        version: '0.1.0',
        dsymsDirectory: DSYMS,
        releaseNote: 'From the fixture.',
    });
    assert.ok(symbolicated > 0);
    assert.match(comment, /3 +Hammerspoon 2 +0x[0-9a-f]{16} parseConfig \(main\.m:7\)/);
    assert.match(comment, /4 +Hammerspoon 2 +0x[0-9a-f]{16} main \(main\.m:24\)/);
    assert.match(comment, /__main_block_invoke \(main\.m:17\)/);
    assert.doesNotMatch(comment, /No dSYM in that release matches/);
});

test('symbolicates an uncaught exception backtrace', onMac, () => {
    const { body: comment } = buildComment({
        report: parseIPS(exceptionText),
        version: '0.1.0',
        dsymsDirectory: DSYMS,
        releaseNote: 'From the fixture.',
    });
    assert.match(comment, /Last Exception Backtrace:\n(.*\n){2}2 +HammerspoonIPCBroker +0x[0-9a-f]{16} raiseException \(main\.m:13\)/);
});

test("says when the release's dSYMs don't match the crashed build", onMac, () => {
    const text = abortText.replace(/9d32208f-a3ce-3b44-b752-1fb780078e7b/g, '11111111-2222-3333-4444-555555555555');
    const { body: comment, symbolicated } = buildComment({ report: parseIPS(text), version: '0.1.0', dsymsDirectory: DSYMS, releaseNote: 'x' });
    assert.equal(symbolicated, 0);
    assert.match(comment, /No dSYM in that release matches `Hammerspoon 2`/);
    assert.match(comment, /Symbolicated 0 frames/);
});

/**
 * Replaces fetch with an in-memory GitHub holding issue 7, with `comments` and `labels`, and no
 * releases. Returns the list of write requests made.
 */
function mockGitHub(t, { body = issueBody({ crashLog: 'No log here' }), comments = [], labels = [] } = {}) {
    const writes = [];
    t.mock.method(globalThis, 'fetch', async (url, { method, body: requestBody }) => {
        const { pathname } = new URL(url);
        if (method === 'GET' && pathname === '/repos/o/r/issues/7') {
            return { ok: true, status: 200, json: async () => ({ body, labels: labels.map(name => ({ name })) }) };
        }
        if (method === 'GET' && pathname === '/repos/o/r/issues/7/comments') {
            return { ok: true, status: 200, json: async () => comments };
        }
        if (method === 'GET' && pathname.startsWith('/repos/o/r/releases/tags/')) {
            return { ok: false, status: 404, text: async () => 'Not Found' };
        }
        writes.push({ method, pathname, body: requestBody && JSON.parse(requestBody) });
        return { ok: true, status: method === 'DELETE' ? 204 : 200, json: async () => ({}) };
    });
    return writes;
}

const reporter = { user: { login: 'someone', type: 'User' } };
const ourReply = text => ({ id: 3, user: { login: COMMENT_AUTHOR, type: 'Bot' }, body: `${COMMENT_MARKER}\n${text}` });
const fixtureDSYMs = async () => ({ directory: DSYMS, note: 'From the fixture.' });
const writeSummary = writes => writes.map(write => [write.method, write.pathname]);

test('asks for a crash log once, and leaves a discussion alone after that', async t => {
    let writes = mockGitHub(t);
    await runForIssue({ repo: 'o/r', issueNumber: 7 });
    assert.deepEqual(writeSummary(writes), [['POST', '/repos/o/r/issues/7/comments']]);
    assert.equal(writes[0].body.body, NO_REPORT_COMMENT);

    t.mock.restoreAll();
    writes = mockGitHub(t, { comments: [ourReply('old'), { ...reporter, body: 'Me too!' }] });
    await runForIssue({ repo: 'o/r', issueNumber: 7 });
    assert.deepEqual(writes, []);
});

test("doesn't find the report quoted in its own reply", async t => {
    const writes = mockGitHub(t, { comments: [ourReply(compact(abortText))] });
    await runForIssue({ repo: 'o/r', issueNumber: 7 });
    assert.deepEqual(writes, []);
});

test('updates its failure reply in place when symbolication still fails', async t => {
    const writes = mockGitHub(t, { comments: [ourReply('old'), { ...reporter, body: compact(abortText) }] });
    await runForIssue({ repo: 'o/r', issueNumber: 7 });
    assert.deepEqual(writeSummary(writes), [['PATCH', '/repos/o/r/issues/comments/3']]);
    assert.match(writes[0].body.body, /There's no release tagged `0\.1\.0`/);
});

test('removes the label when a re-run fails', async t => {
    const writes = mockGitHub(t, { body: issueBody({ crashLog: compact(abortText) }), labels: ['crash', 'symbolicated'] });
    await runForIssue({ repo: 'o/r', issueNumber: 7 });
    assert.deepEqual(writeSummary(writes), [
        ['POST', '/repos/o/r/issues/7/comments'],
        ['DELETE', '/repos/o/r/issues/7/labels/symbolicated'],
    ]);
});

test('replaces its failure reply with a new one, and labels the issue, once symbolication works', onMac, async t => {
    const writes = mockGitHub(t, { comments: [ourReply('old'), { ...reporter, body: compact(abortText) }] });
    await runForIssue({ repo: 'o/r', issueNumber: 7, getDSYMs: fixtureDSYMs });
    assert.deepEqual(writeSummary(writes), [
        ['DELETE', '/repos/o/r/issues/comments/3'],
        ['POST', '/repos/o/r/issues/7/comments'],
        ['POST', '/repos/o/r/issues/7/labels'],
    ]);
    assert.match(writes[1].body.body, /parseConfig \(main\.m:7\)/);
    assert.deepEqual(writes[2].body, { labels: ['symbolicated'] });
});

test('leaves an up-to-date symbolicated reply and label alone', onMac, async t => {
    const report = parseIPS(compact(abortText));
    const { body } = buildComment({ report, version: '0.1.0', dsymsDirectory: DSYMS, releaseNote: 'From the fixture.' });
    const writes = mockGitHub(t, {
        body: issueBody({ crashLog: compact(abortText) }),
        comments: [{ ...ourReply(''), body }],
        labels: ['crash', 'symbolicated'],
    });
    await runForIssue({ repo: 'o/r', issueNumber: 7, getDSYMs: fixtureDSYMs });
    assert.deepEqual(writes, []);
});
