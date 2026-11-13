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
    codeBlock,
    COMMENT_MARKER,
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
    const report = await findReport(body, async url => {
        fetched.push(url);
        return exceptionText;
    });
    assert.deepEqual(fetched, ['https://github.com/user-attachments/files/1/log.txt']);
    assert.equal(report.body.procName, 'HammerspoonIPCBroker');
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
    const comment = buildComment({
        report: parseIPS(compact(abortText)),
        version: '0.1.0',
        dsymsDirectory: DSYMS,
        releaseNote: 'From the fixture.',
    });
    assert.match(comment, /3 +Hammerspoon 2 +0x[0-9a-f]{16} parseConfig \(main\.m:7\)/);
    assert.match(comment, /4 +Hammerspoon 2 +0x[0-9a-f]{16} main \(main\.m:24\)/);
    assert.match(comment, /__main_block_invoke \(main\.m:17\)/);
    assert.doesNotMatch(comment, /No dSYM in that release matches/);
});

test('symbolicates an uncaught exception backtrace', onMac, () => {
    const comment = buildComment({
        report: parseIPS(exceptionText),
        version: '0.1.0',
        dsymsDirectory: DSYMS,
        releaseNote: 'From the fixture.',
    });
    assert.match(comment, /Last Exception Backtrace:\n(.*\n){2}2 +HammerspoonIPCBroker +0x[0-9a-f]{16} raiseException \(main\.m:13\)/);
});

test("says when the release's dSYMs don't match the crashed build", onMac, () => {
    const text = abortText.replace(/9d32208f-a3ce-3b44-b752-1fb780078e7b/g, '11111111-2222-3333-4444-555555555555');
    const comment = buildComment({ report: parseIPS(text), version: '0.1.0', dsymsDirectory: DSYMS, releaseNote: 'x' });
    assert.match(comment, /No dSYM in that release matches `Hammerspoon 2`/);
    assert.match(comment, /Symbolicated 0 frames/);
});
