/**
 * Tests for scripts/release/changelog.js.
 *
 * Run with: npm run test:scripts
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { parseLog, parseMessages, collectEntries, formatNotes, LOG_FORMAT } = require('../release/changelog');

const SCRIPT = path.join(__dirname, '../release/changelog.js');

// A scratch repository, so trailers go through git's own parser.
function makeRepo() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'changelog-test-'));
    const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8' });
    git('init', '-q', '-b', 'main');
    git('config', 'user.email', 'test@example.com');
    git('config', 'user.name', 'Test');
    git('config', 'commit.gpgsign', 'false');
    const commit = (message) => {
        execFileSync('git', ['commit', '-q', '--allow-empty', '-F', '-'], { cwd: dir, input: message });
        return git('rev-parse', 'HEAD').trim();
    };
    commit('Initial commit');
    git('tag', 'v1');
    return { dir, git, commit, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}

// Collects entries both from git log and from the commits' messages, the way
// the PR workflow gets them from the GitHub API (without a trailing newline),
// and checks that the two agree.
function entriesFor(repo, ...messages) {
    for (const message of messages) repo.commit(message);
    const log = execFileSync('git', ['log', '--reverse', `--format=${LOG_FORMAT}`, 'v1..HEAD'], { cwd: repo.dir, encoding: 'utf8' });
    const commits = parseLog(log);
    const result = collectEntries(commits);
    const fromMessages = collectEntries(parseMessages(commits.map(({ sha, body }) => ({ sha, message: body.replace(/\n+$/, '') }))));
    assert.deepEqual(fromMessages, result, 'parsing the commit messages should match git log');
    return result;
}

function texts(entries) {
    return Object.fromEntries(Object.entries(entries).map(([title, list]) => [title, list.map(({ text }) => text)]));
}

test('collects each kind of trailer alongside Co-Authored-By', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries, problems } = entriesFor(repo, [
        'Add hs.foo',
        '',
        'Body text.',
        '',
        'Changelog-Added: hs.foo.bar()',
        'Changelog-Changed: hs.foo.baz() returns null',
        'Changelog-Fixed: hs.foo.qux() no longer crashes',
        'Co-Authored-By: Someone <someone@example.com>',
    ].join('\n'));
    assert.deepEqual(problems, []);
    assert.deepEqual(texts(entries), {
        Added: ['hs.foo.bar()'],
        Changed: ['hs.foo.baz() returns null'],
        Fixed: ['hs.foo.qux() no longer crashes'],
    });
});

test('accepts any case and joins continuation lines', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries } = entriesFor(repo, 'Subject\n\nchangelog-added: a long entry\n  that wraps\n');
    assert.deepEqual(texts(entries).Added, ['a long entry that wraps']);
});

test('keeps entries in commit order and drops duplicates', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries } = entriesFor(repo,
        'One\n\nChangelog-Fixed: first\n',
        'Two\n\nChangelog-Fixed: second\n',
        'Three\n\nChangelog-Fixed: first\n');
    assert.deepEqual(texts(entries).Fixed, ['first', 'second']);
});

test('reports a changelog line outside the trailer block', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries, problems } = entriesFor(repo,
        'Subject\n\nChangelog-Added: misplaced\n\nCo-Authored-By: Someone <someone@example.com>\n');
    assert.deepEqual(texts(entries).Added, []);
    assert.equal(problems.length, 1);
    assert.match(problems[0], /a "Changelog-Added:" line that git doesn't read as a trailer/);
});

test('reports a misplaced line even when a trailer starts the same way', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries, problems } = entriesFor(repo,
        'Subject\n\nChangelog-Fixed: Fix crash\n\nChangelog-Fixed: Fix crash on startup\n');
    assert.deepEqual(texts(entries).Fixed, ['Fix crash on startup']);
    assert.equal(problems.length, 1);
    assert.match(problems[0], /a "Changelog-Fixed:" line that git doesn't read as a trailer/);
});

test('reports changelog lines in a last paragraph git rejects as trailers', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries, problems } = entriesFor(repo, 'Subject\n\nSome prose.\nChangelog-Added: lost\n');
    assert.deepEqual(texts(entries).Added, []);
    assert.equal(problems.length, 1);
});

test('reports an indented changelog line outside the trailer block', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { problems } = entriesFor(repo,
        'Subject\n\n  Changelog-Added: lost feature\n\nChangelog-Fixed: a bug\n');
    assert.equal(problems.length, 1);
    assert.match(problems[0], /"Changelog-Added:"/);
});

test('accepts a continuation line that looks like a changelog line', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries, problems } = entriesFor(repo,
        'Subject\n\nChangelog-Changed: hs.foo now reads\n  Changelog-Added: lines literally\n');
    assert.deepEqual(problems, []);
    assert.deepEqual(texts(entries).Changed, ['hs.foo now reads Changelog-Added: lines literally']);
});

// git interpret-trailers stops at a "---" line, but %(trailers) in git log
// doesn't, so a trailer above one isn't parsed and must be reported.
test('reports trailers followed by a --- separator', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries, problems } = entriesFor(repo,
        'Subject\n\nChangelog-Fixed: a bug\n\n---\nNotes after the separator.\n');
    assert.deepEqual(texts(entries).Fixed, []);
    assert.equal(problems.length, 1);
});

test('reports unknown and empty changelog trailers', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { problems } = entriesFor(repo, 'Subject\n\nChangelog-Add: typo\nChangelog-Fixed:\n');
    assert.equal(problems.length, 2);
    assert.match(problems.join('\n'), /unknown changelog trailer "Changelog-Add:"/);
    assert.match(problems.join('\n'), /empty Changelog-Fixed: trailer/);
});

test('ignores commits without changelog trailers', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    const { entries, problems } = entriesFor(repo, 'Refactor\n\nNothing user-facing.\n\nCo-Authored-By: Someone <someone@example.com>\n');
    assert.deepEqual(problems, []);
    assert.deepEqual(texts(entries), { Added: [], Changed: [], Fixed: [] });
});

test('formats sections in order, omitting empty ones', () => {
    const notes = formatNotes({
        Added: [{ text: 'new thing', sha: 'a' }],
        Changed: [],
        Fixed: [{ text: 'old bug', sha: 'b' }],
    }, { prs: new Map([['a', '12']]), repo: 'owner/repo', from: '0.1', version: '0.2' });
    assert.equal(notes, [
        '## Added',
        '',
        '- new thing (#12)',
        '',
        '## Fixed',
        '',
        '- old bug',
        '',
        '**Full Changelog**: https://github.com/owner/repo/compare/0.1...0.2',
        '',
    ].join('\n'));
});

test('says so when there are no entries', () => {
    assert.equal(formatNotes({ Added: [], Changed: [], Fixed: [] }), 'No user-facing changes.\n');
});

test('notes links entries to the pull requests that merged them', (t) => {
    const repo = makeRepo();
    t.after(repo.cleanup);
    repo.git('checkout', '-q', '-b', 'feature');
    repo.commit('Feature\n\nChangelog-Added: from a merged PR\n');
    repo.git('checkout', '-q', 'main');
    repo.git('merge', '-q', '--no-ff', 'feature', '-m', 'Merge pull request #7 from someone/feature');
    repo.commit('Squashed fix (#8)\n\nChangelog-Fixed: from a squashed PR\n');
    repo.commit('Direct\n\nChangelog-Fixed: from a direct push\n');

    const notes = execFileSync('node', [SCRIPT, 'notes', '--from', 'v1'], { cwd: repo.dir, encoding: 'utf8' });
    assert.equal(notes, [
        '## Added',
        '',
        '- from a merged PR (#7)',
        '',
        '## Fixed',
        '',
        '- from a squashed PR (#8)',
        '- from a direct push',
        '',
    ].join('\n'));
});

test('rejects malformed commit records', () => {
    assert.throws(() => parseMessages({}), /JSON array/);
    assert.throws(() => parseMessages([{ sha: 'not-a-sha', message: 'x' }]), /hex "sha"/);
    assert.throws(() => parseMessages([{ sha: 'a'.repeat(40) }]), /string "message"/);
});

test('check reads commits from a file', (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'changelog-test-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'commits.json');
    fs.writeFileSync(file, JSON.stringify([
        { sha: 'a'.repeat(40), message: 'One\n\nChangelog-Added: new thing' },
        { sha: 'b'.repeat(40), message: 'Two\n\nChangelog-Add: typo' },
    ]));
    const result = JSON.parse(execFileSync('node', [SCRIPT, 'check', '--json', '--commits', file], { cwd: dir, encoding: 'utf8' }));
    assert.equal(result.count, 1);
    assert.deepEqual(result.entries.Added, [{ text: 'new thing', sha: 'a'.repeat(40) }]);
    assert.equal(result.problems.length, 1);
    assert.match(result.problems[0], /^bbbbbbbb has an unknown changelog trailer/);
});

test('--commits replaces --from and --to', () => {
    for (const args of [['check', '--commits', 'x', '--from', 'v1'], ['check', '--commits', 'x', '--to', 'HEAD'], ['notes', '--commits', 'x']]) {
        assert.throws(() => execFileSync('node', [SCRIPT, ...args], { stdio: 'pipe' }), /--commits only works with check/);
    }
});

const { changelogComment, quote, MARKER } = require('../release/changelog-comment');

test('quoting breaks mentions of users and teams', () => {
    assert.equal(quote('ping @octocat and @org/team, mail a@b.com, lone @ sign'),
        'ping @\u200boctocat and @\u200borg/team, mail a@\u200bb.com, lone @ sign');
});

test('quoting clips long lines and long lists', () => {
    const [line] = quote('x'.repeat(600)).split('\n');
    assert.equal(line, `${'x'.repeat(500)}…`);
    const lines = quote(Array.from({ length: 100 }, (_, i) => `- ${i}`).join('\n')).split('\n');
    assert.equal(lines.length, 61);
    assert.equal(lines[60], '…and 40 more lines');
});

test('comment quotes entries and problems', () => {
    const preview = changelogComment({ count: 1, problems: [], preview: '## Fixed\n\n- thanks @someone\n' }, 'octocat');
    assert.match(preview.body, /- thanks @\u200bsomeone/);
    const problems = changelogComment({ count: 0, problems: ['abc pings @someone'], preview: '' }, 'octocat');
    assert.match(problems.body, /^@octocat, /m);
    assert.match(problems.body, /- abc pings @\u200bsomeone/);
});

test('comment asks the author for entries when there are none', () => {
    const { body, create } = changelogComment({ count: 0, problems: [], preview: '' }, 'octocat');
    assert.equal(create, true);
    assert.ok(body.startsWith(MARKER));
    assert.match(body, /@octocat, none of the commits/);
    assert.match(body, /Changelog-Added: /);
});

test('comment lists problems even when there are entries', () => {
    const { body, create } = changelogComment({ count: 1, problems: ['abc has a typo'], preview: '## Fixed\n\n- x\n' }, 'octocat');
    assert.equal(create, true);
    assert.match(body, /- abc has a typo/);
});

test('comment only previews valid entries, without creating a new comment', () => {
    const { body, create } = changelogComment({ count: 1, problems: [], preview: '## Fixed\n\n- x\n' }, 'octocat');
    assert.equal(create, false);
    assert.match(body, /## Fixed\n\n- x/);
});
