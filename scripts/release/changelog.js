#!/usr/bin/env node
/**
 * Build release notes from changelog trailers in commit messages, or check
 * that a pull request's commits carry well-formed ones.
 *
 * A commit adds an entry to the release notes with a trailer in the last
 * paragraph of its message (alongside any Co-Authored-By lines):
 *
 *   Changelog-Added: hs.foo.bar(), which does a thing
 *   Changelog-Changed: hs.foo.baz() now returns null instead of false
 *   Changelog-Fixed: hs.foo.qux() no longer crashes on an empty string
 *
 * A squash merge's message is its pull request's commit messages one after
 * another, and GitHub adds its own Co-authored-by paragraph at the end, so
 * there the trailers in every paragraph count.
 *
 * Usage:
 *   changelog.js notes --from <ref> [--to <ref>] [--repo owner/name] [--version <tag>]
 *       Print release notes (markdown) for the commits in <from>..<to>.
 *       Without --from, every commit up to <to> is included.
 *   changelog.js check --from <ref> [--to <ref>] [--json]
 *   changelog.js check --commits <file> [--json]
 *       Report the entries and any malformed or misplaced trailers in
 *       <from>..<to>, or in the commits listed in <file> (a JSON array of
 *       { sha, message }, e.g. from the GitHub API). Exits 0 either way;
 *       --json prints a machine-readable result for the PR workflow.
 */

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');

const SECTIONS = [
    { key: 'changelog-added', title: 'Added' },
    { key: 'changelog-changed', title: 'Changed' },
    { key: 'changelog-fixed', title: 'Fixed' },
];

const FIELD = '\x1f';
const RECORD = '\x1e';

function git(args) {
    return execFileSync('git', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
}

function range(from, to) {
    return from ? `${from}..${to}` : to;
}

/**
 * Parse the output of `git log --format=<LOG_FORMAT>` into commits.
 * Trailers come from git's own parser, so they're found exactly when git
 * (and `git interpret-trailers`) considers them trailers.
 */
const LOG_FORMAT = ['%H', '%P', '%s', '%B', '%(trailers:only,unfold,separator=%x00)'].join('%x1f') + '%x1e';

function parseTrailers(lines) {
    return lines.map((line) => line.trim()).filter(Boolean).map((line) => {
        const colon = line.indexOf(':');
        return { key: line.slice(0, colon).trim(), value: line.slice(colon + 1).trim() };
    });
}

// GitHub squash merges are titled "... (#N)".
const SQUASH_SUBJECT = /\(#(\d+)\)$/;

/**
 * The trailers of a squash merge: those in every paragraph of its message,
 * each parsed by git as if it ended a message, since each of the squashed
 * commits' trailer blocks ends up in a paragraph of its own.
 */
function squashTrailers(body) {
    return body.split(/\n[ \t]*\n/)
        .filter((paragraph) => /^[\w-]+[ \t]*:/m.test(paragraph))
        .flatMap((paragraph) => {
            // git never reads a message's first paragraph (its subject) as
            // trailers, so give each paragraph one.
            const message = `subject\n\n${paragraph}\n`;
            const parsed = execFileSync('git', ['interpret-trailers', '--parse', '--no-divider'], { input: message, encoding: 'utf8' });
            return parseTrailers(parsed.split('\n'));
        });
}

function parseLog(output) {
    return output.split(RECORD).map((record) => record.replace(/^\n/, '')).filter(Boolean).map((record) => {
        const [sha, parents, subject, body, trailers] = record.split(FIELD);
        return {
            sha,
            parents: parents ? parents.split(' ') : [],
            subject,
            body,
            trailers: SQUASH_SUBJECT.test(subject) ? squashTrailers(body) : parseTrailers((trailers || '').split('\0')),
        };
    });
}

/**
 * Parse commits given as { sha, message } records, without needing them in
 * the repository. The PR workflow gets them from the GitHub API, so it never
 * fetches a pull request's commits. --no-divider matches %(trailers) in
 * parseLog, which doesn't stop at a "---" line.
 */
function parseMessages(records) {
    if (!Array.isArray(records)) throw new Error('commits must be a JSON array');
    return records.map((record) => {
        const { sha, message } = record || {};
        if (typeof sha !== 'string' || !/^[0-9a-f]{40,64}$/.test(sha) || typeof message !== 'string') {
            throw new Error('each commit must have a hex "sha" and a string "message"');
        }
        const subject = message.split('\n')[0];
        if (SQUASH_SUBJECT.test(subject)) {
            return { sha, parents: [], subject, body: message, trailers: squashTrailers(message) };
        }
        const trailers = execFileSync('git', ['interpret-trailers', '--parse', '--no-divider'], { input: message, encoding: 'utf8' });
        return { sha, parents: [], subject, body: message, trailers: parseTrailers(trailers.split('\n')) };
    });
}

function readCommits(from, to) {
    return parseLog(git(['log', '--reverse', `--format=${LOG_FORMAT}`, range(from, to)]));
}

/**
 * Map each commit to the pull request that brought it in, from GitHub's merge
 * commits ("Merge pull request #N from ...") and squash merges ("... (#N)")
 * on the first-parent line.
 */
function pullRequestsByCommit(from, to) {
    const prs = new Map();
    // Only the subjects and parents are needed, so don't parse any trailers.
    const mainline = git(['log', '--first-parent', '--format=%H%x1f%P%x1f%s%x1e', range(from, to)])
        .split(RECORD).map((record) => record.replace(/^\n/, '')).filter(Boolean).map((record) => {
            const [sha, parents, subject] = record.split(FIELD);
            return { sha, parents: parents ? parents.split(' ') : [], subject };
        });
    for (const commit of mainline) {
        const merge = commit.subject.match(/^Merge pull request #(\d+)\b/);
        if (merge && commit.parents.length > 1) {
            prs.set(commit.sha, merge[1]);
            const branch = git(['rev-list', `${commit.parents[0]}..${commit.parents[1]}`]).split('\n').filter(Boolean);
            for (const sha of branch) prs.set(sha, merge[1]);
            continue;
        }
        const squash = commit.subject.match(SQUASH_SUBJECT);
        if (squash) prs.set(commit.sha, squash[1]);
    }
    return prs;
}

/**
 * Collect changelog entries from commits, and the problems with any trailers
 * that look like changelog entries but won't be picked up.
 */
function collectEntries(commits) {
    const entries = Object.fromEntries(SECTIONS.map(({ title }) => [title, []]));
    const problems = [];

    for (const commit of commits) {
        const short = commit.sha.slice(0, 8);
        const changelogTrailers = commit.trailers.filter(({ key }) => /^changelog/i.test(key));
        for (const { key, value } of changelogTrailers) {
            const section = SECTIONS.find((s) => s.key === key.toLowerCase());
            if (!section) {
                problems.push(`${short} has an unknown changelog trailer "${key}:" (use Changelog-Added, Changelog-Changed or Changelog-Fixed)`);
            } else if (!value) {
                problems.push(`${short} has an empty ${key}: trailer`);
            } else {
                entries[section.title].push({ text: value, sha: commit.sha });
            }
        }
        // Changelog lines that git didn't parse as trailers, e.g. because
        // they're not in the trailer block at the end of the message. Rather
        // than second-guess where git found that block, count each kind of
        // line against the trailers git parsed. An indented line is only a
        // changelog line if it isn't continuing a parsed trailer's value.
        const ignored = new Map();
        for (const line of commit.body.split('\n')) {
            const match = line.match(/^\s*(changelog[\w-]*)\s*:/i);
            if (!match) continue;
            if (/^\s/.test(line) && changelogTrailers.some(({ value }) => value.includes(line.trim()))) continue;
            const key = match[1].toLowerCase();
            const { count = 0 } = ignored.get(key) || {};
            ignored.set(key, { name: match[1], count: count + 1 });
        }
        for (const [key, { name, count }] of ignored) {
            const unparsed = count - changelogTrailers.filter((trailer) => trailer.key.toLowerCase() === key).length;
            if (unparsed > 0) {
                problems.push(`${short} has ${unparsed === 1 ? 'a' : unparsed} "${name}:" line${unparsed === 1 ? '' : 's'} that git doesn't read as a trailer, so ${unparsed === 1 ? "it'll" : "they'll"} be ignored; put changelog lines in the last paragraph of the commit message, unindented, with no blank lines between them and any Co-Authored-By lines`);
            }
        }
    }

    // A rebased or cherry-picked commit can carry the same entry twice.
    for (const title of Object.keys(entries)) {
        const seen = new Set();
        entries[title] = entries[title].filter(({ text }) => !seen.has(text) && seen.add(text));
    }
    return { entries, problems };
}

function formatNotes(entries, { prs = new Map(), repo, from, version } = {}) {
    const sections = [];
    for (const { title } of SECTIONS) {
        if (entries[title].length === 0) continue;
        const lines = entries[title].map(({ text, sha }) => {
            const pr = prs.get(sha);
            return pr ? `- ${text} (#${pr})` : `- ${text}`;
        });
        sections.push(`## ${title}\n\n${lines.join('\n')}`);
    }
    if (sections.length === 0) sections.push('No user-facing changes.');
    if (repo && from && version) {
        sections.push(`**Full Changelog**: https://github.com/${repo}/compare/${from}...${version}`);
    }
    return sections.join('\n\n') + '\n';
}

function parseArgs(argv) {
    const [command, ...rest] = argv;
    const options = { command, to: 'HEAD' };
    for (let i = 0; i < rest.length; i++) {
        const arg = rest[i];
        const value = () => {
            if (i + 1 >= rest.length) throw new Error(`${arg} needs a value`);
            return rest[++i];
        };
        switch (arg) {
            case '--from': options.from = value(); break;
            case '--to': options.to = value(); break;
            case '--repo': options.repo = value(); break;
            case '--version': options.version = value(); break;
            case '--commits': options.commits = value(); break;
            case '--json': options.json = true; break;
            default: throw new Error(`unknown argument: ${arg}`);
        }
    }
    if (command !== 'notes' && command !== 'check') throw new Error('usage: changelog.js notes|check [options]');
    if (options.commits && (command !== 'check' || options.from || rest.includes('--to'))) {
        throw new Error('--commits only works with check, instead of --from and --to');
    }
    return options;
}

function main(argv) {
    const options = parseArgs(argv);
    const commits = options.commits
        ? parseMessages(JSON.parse(fs.readFileSync(options.commits, 'utf8')))
        : readCommits(options.from, options.to);
    const { entries, problems } = collectEntries(commits);

    if (options.command === 'notes') {
        for (const problem of problems) process.stderr.write(`warning: ${problem}\n`);
        const prs = pullRequestsByCommit(options.from, options.to);
        process.stdout.write(formatNotes(entries, { prs, ...options }));
        return;
    }

    const count = Object.values(entries).reduce((sum, list) => sum + list.length, 0);
    if (options.json) {
        process.stdout.write(JSON.stringify({ count, entries, problems, preview: count ? formatNotes(entries) : '' }) + '\n');
        return;
    }
    process.stdout.write(count ? formatNotes(entries) : 'No changelog entries.\n');
    for (const problem of problems) process.stdout.write(`warning: ${problem}\n`);
}

if (require.main === module) {
    try {
        main(process.argv.slice(2));
    } catch (error) {
        process.stderr.write(`error: ${error.message}\n`);
        process.exit(1);
    }
}

module.exports = { parseLog, parseMessages, collectEntries, formatNotes, LOG_FORMAT };
