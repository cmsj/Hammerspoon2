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
 * Usage:
 *   changelog.js notes --from <ref> [--to <ref>] [--repo owner/name] [--version <tag>]
 *       Print release notes (markdown) for the commits in <from>..<to>.
 *       Without --from, every commit up to <to> is included.
 *   changelog.js check --from <ref> [--to <ref>] [--json]
 *       Report the entries and any malformed or misplaced trailers in
 *       <from>..<to>. Exits 0 either way; --json prints a machine-readable
 *       result for the PR workflow.
 */

const { execFileSync } = require('node:child_process');

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

function parseLog(output) {
    return output.split(RECORD).map((record) => record.replace(/^\n/, '')).filter(Boolean).map((record) => {
        const [sha, parents, subject, body, trailers] = record.split(FIELD);
        return {
            sha,
            parents: parents ? parents.split(' ') : [],
            subject,
            body,
            trailers: (trailers || '').split('\0').map((line) => line.trim()).filter(Boolean).map((line) => {
                const colon = line.indexOf(':');
                return { key: line.slice(0, colon).trim(), value: line.slice(colon + 1).trim() };
            }),
        };
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
    const mainline = parseLog(git(['log', '--first-parent', `--format=${LOG_FORMAT}`, range(from, to)]));
    for (const commit of mainline) {
        const merge = commit.subject.match(/^Merge pull request #(\d+)\b/);
        if (merge && commit.parents.length > 1) {
            prs.set(commit.sha, merge[1]);
            const branch = git(['rev-list', `${commit.parents[0]}..${commit.parents[1]}`]).split('\n').filter(Boolean);
            for (const sha of branch) prs.set(sha, merge[1]);
            continue;
        }
        const squash = commit.subject.match(/\(#(\d+)\)$/);
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
        // Changelog lines that git didn't parse as trailers, usually because
        // they're not in the message's last paragraph.
        for (const line of commit.body.split('\n')) {
            const match = line.match(/^\s*(changelog[\w-]*)\s*:(.*)$/i);
            if (match && !changelogTrailers.some(({ key, value }) =>
                key.toLowerCase() === match[1].toLowerCase() && value.startsWith(match[2].trim()))) {
                problems.push(`${short} has a "${match[1]}:" line that isn't a trailer, so it will be ignored; move it into the last paragraph of the commit message, with no blank lines between it and any Co-Authored-By lines`);
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
            case '--json': options.json = true; break;
            default: throw new Error(`unknown argument: ${arg}`);
        }
    }
    if (command !== 'notes' && command !== 'check') throw new Error('usage: changelog.js notes|check [options]');
    return options;
}

function main(argv) {
    const options = parseArgs(argv);
    const { entries, problems } = collectEntries(readCommits(options.from, options.to));

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

module.exports = { parseLog, collectEntries, formatNotes, LOG_FORMAT };
