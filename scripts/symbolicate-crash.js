#!/usr/bin/env node

/**
 * Crash Report Symbolicator
 *
 * Replies to a crash report issue (.github/ISSUE_TEMPLATE/crash_report.yml) with a symbolicated
 * copy of its crash log. Run by .github/workflows/crash-report.yml, on a macOS runner since it
 * needs atos and dwarfdump. It:
 *
 *  1. Finds the crash log in the issue: an attached .txt/.ips/.json file, or an .ips report
 *     pasted into the body. Hammerspoon 2 writes a compact .ips (see CrashReport.swift), but a
 *     full one from ~/Library/Logs/DiagnosticReports works too.
 *  2. Downloads Hammerspoon-2-<version>-dSYMs.zip from the release the crash came from, which
 *     scripts/release/release.sh attaches to every release.
 *  3. Symbolicates every frame in a binary whose UUID matches one of those dSYMs, using atos.
 *  4. Posts the result as a comment on the issue, or updates the one it posted before (so
 *     editing the issue to add the crash log gets it symbolicated too).
 *
 * The issue is untrusted input: nothing from it reaches a shell, only github.com attachment URLs
 * are fetched, and everything it contributes to the comment is inside a code block.
 *
 * Usage:
 *   node scripts/symbolicate-crash.js --issue <number>          (in CI, with GITHUB_TOKEN set)
 *   node scripts/symbolicate-crash.js --report <file> [--dsyms <dir>]   (locally; prints Markdown)
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const COMMENT_MARKER = '<!-- crash-symbolication -->';
// Comments posted with the workflow's GITHUB_TOKEN are authored by this bot account.
const COMMENT_AUTHOR = 'github-actions[bot]';
// GitHub rejects comments over 65536 characters; leave room for the notes around the report.
const MAX_REPORT_LENGTH = 60000;
const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;
const VERSION_FIELD = 'Hammerspoon 2 version';
const DSYMS_ASSET = version => `Hammerspoon-2-${version}-dSYMs.zip`;

// Attachments on issues: https://github.com/user-attachments/files/<id>/<name>, or the older
// https://github.com/<owner>/<repo>/files/<id>/<name>.
const ATTACHMENT_PATTERN =
    /https:\/\/github\.com\/(?:user-attachments\/files|[\w.-]+\/[\w.-]+\/files)\/\d+\/[^\s)\]"'<>`]+/g;

// --- Finding and parsing the crash log ---------------------------------------------------------

/** Every attachment URL in `body`, in order, without duplicates. */
function attachmentURLs(body) {
    return [...new Set(body.match(ATTACHMENT_PATTERN) || [])];
}

/**
 * Parses .ips text: a line of JSON metadata, then the report as JSON. The report may follow on
 * one line (Hammerspoon 2's compact form) or many (macOS's own), and may be followed by the end
 * of a Markdown code block. Returns `{ header, body }`, or null if `text` doesn't contain one.
 */
function parseIPS(text) {
    const lines = text.replace(/\r/g, '').split('\n');
    for (let start = 0; start < lines.length; start++) {
        const header = parseJSON(lines[start].trim());
        if (!header || typeof header !== 'object' || !('bug_type' in header)) {
            continue;
        }
        const rest = lines.slice(start + 1);
        const fence = rest.findIndex(line => /^\s*(```|~~~)/.test(line));
        const body = parseJSON((fence === -1 ? rest : rest.slice(0, fence)).join('\n'));
        if (body && typeof body === 'object' && Array.isArray(body.threads)) {
            return { header, body };
        }
    }
    return null;
}

function parseJSON(text) {
    if (!text.startsWith('{')) {
        return null;
    }
    try {
        return JSON.parse(text);
    } catch {
        return null;
    }
}

/** The value of an issue form field, from the "### Label" heading GitHub renders it under. */
function formField(body, label) {
    const lines = body.replace(/\r/g, '').split('\n');
    const start = lines.findIndex(line => line.trim() === `### ${label}`);
    if (start === -1) {
        return null;
    }
    for (const line of lines.slice(start + 1)) {
        if (line.startsWith('### ')) {
            break;
        }
        const value = line.trim();
        if (value && value !== '_No response_') {
            return value;
        }
    }
    return null;
}

/** The version that crashed: the report's own, or (for helpers, which have none) the form's. */
function crashedVersion(report, issueBody) {
    const own = report.header.app_version || (report.body.bundleInfo || {}).CFBundleShortVersionString;
    if (own) {
        return own;
    }
    const field = formField(issueBody || '', VERSION_FIELD);
    return field && /^[0-9A-Za-z.+-]+$/.test(field) ? field : null;
}

// --- Symbolication -----------------------------------------------------------------------------

/** Maps (lowercase) UUIDs to the DWARF files of every dSYM under `directory`. */
function dsymsByUUID(directory, dwarfdump = defaultDwarfdump) {
    const files = [];
    const walk = dir => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else if (entry.isFile() && /\.dSYM\/Contents\/Resources\/DWARF\/[^/]+$/.test(full)) {
                files.push(full);
            }
        }
    };
    walk(directory);

    const map = new Map();
    for (const file of files) {
        for (const line of dwarfdump(file).split('\n')) {
            const match = line.match(/^UUID: ([0-9A-Fa-f-]{36}) \(([^)]+)\)/);
            if (match) {
                map.set(match[1].toLowerCase(), { file, arch: match[2] });
            }
        }
    }
    return map;
}

function defaultDwarfdump(file) {
    return execFileSync('xcrun', ['dwarfdump', '--uuid', file], { encoding: 'utf8' });
}

function defaultAtos({ file, arch, loadAddress, addresses }) {
    return execFileSync('xcrun', ['atos', '-arch', arch, '-o', file, '-l', loadAddress, ...addresses], {
        encoding: 'utf8',
        maxBuffer: 16 * 1024 * 1024,
    });
}

const hex = value => `0x${value.toString(16)}`;

/**
 * Every backtrace in the report, as `{ title, crashed, frames }`. Each frame has the image name,
 * its absolute address, and whatever symbol macOS already found (system libraries have them;
 * our release binaries are stripped, so their frames don't).
 */
function backtraces(report) {
    const { body } = report;
    const images = body.usedImages || [];
    const toFrames = rawFrames =>
        (rawFrames || []).map((frame, index) => {
            const image = images[frame.imageIndex] || {};
            const offset = BigInt(frame.imageOffset || 0);
            const base = image.base === undefined ? null : BigInt(image.base);
            return {
                index,
                image,
                imageName: image.name || (image.path ? path.basename(image.path) : '???'),
                offset,
                address: base === null ? null : base + offset,
                symbol: frame.symbol
                    ? `${frame.symbol} + ${frame.symbolLocation || 0}` +
                      (frame.sourceFile ? ` (${path.basename(frame.sourceFile)}:${frame.sourceLine})` : '')
                    : null,
            };
        });

    const result = [];
    if (Array.isArray(body.lastExceptionBacktrace) && body.lastExceptionBacktrace.length) {
        result.push({ title: 'Last Exception Backtrace', crashed: true, frames: toFrames(body.lastExceptionBacktrace) });
    }
    const threads = body.threads || [];
    const faulting = Number.isInteger(body.faultingThread)
        ? body.faultingThread
        : threads.findIndex(thread => thread.triggered);
    threads.forEach((thread, position) => {
        // Compact reports drop threads, so they record each one's original number.
        const number = Number.isInteger(thread.index) ? thread.index : position;
        const name = thread.name || thread.queue;
        const crashed = position === faulting;
        const title = `${crashed ? 'Crashed Thread' : 'Thread'} ${number}${name ? ` (${name})` : ''}`;
        const frames = toFrames(thread.frames);
        const note = thread.omittedFrames ? `${thread.omittedFrames} more frames weren't included in the report` : null;
        result.push({ title, crashed, frames, note });
    });
    // The crashed thread first, after any exception backtrace.
    return [
        ...result.filter(trace => trace.crashed),
        ...result.filter(trace => !trace.crashed),
    ];
}

/**
 * Fills in `symbol` (and sets `symbolicated`) for every frame in an image that one of `dsyms`
 * matches. Returns the images that are ours but that no dSYM matched.
 */
function symbolicate(traces, dsyms, atos = defaultAtos) {
    // Group the lookups by image, so each binary is a single atos run.
    const lookups = new Map();
    for (const trace of traces) {
        for (const frame of trace.frames) {
            const uuid = (frame.image.uuid || '').toLowerCase();
            const dsym = dsyms.get(uuid);
            if (!dsym || frame.address === null) {
                continue;
            }
            if (!lookups.has(uuid)) {
                lookups.set(uuid, { dsym, image: frame.image, frames: [] });
            }
            lookups.get(uuid).frames.push(frame);
        }
    }

    for (const { dsym, image, frames } of lookups.values()) {
        // Below the top of a backtrace, addresses are where calls return to, which can be past
        // the end of the calling function (when what it calls never returns), so look up the
        // byte before.
        const addresses = frames.map(frame => hex(frame.index === 0 ? frame.address : frame.address - 1n));
        const output = atos({
            file: dsym.file,
            arch: image.arch || dsym.arch,
            loadAddress: hex(BigInt(image.base)),
            addresses,
        }).split('\n');
        frames.forEach((frame, i) => {
            const line = (output[i] || '').trim();
            // atos repeats the address when it can't find a symbol.
            if (line && !/^0x[0-9a-f]+$/i.test(line)) {
                frame.symbol = line.replace(/ \(in [^)]+\)/, '');
                frame.symbolicated = true;
            }
        });
    }
}

// --- Rendering ---------------------------------------------------------------------------------

function frameLine(frame) {
    const address = frame.address === null ? '0x????????????????' : `0x${frame.address.toString(16).padStart(16, '0')}`;
    const symbol = frame.symbol || `${frame.imageName} + ${frame.offset}`;
    return `${String(frame.index).padEnd(4)}${frame.imageName.padEnd(Math.max(30, frame.imageName.length + 1))}${address} ${symbol}`;
}

function summaryLines(report, version) {
    const { header, body } = report;
    const exception = body.exception || {};
    const termination = body.termination;
    const lines = [
        `Process:     ${body.procName || header.name || 'unknown'}`,
        `Version:     ${version || 'unknown'}${header.build_version ? ` (${header.build_version})` : ''}`,
    ];
    if (header.os_version) lines.push(`macOS:       ${header.os_version}`);
    if (body.modelCode) lines.push(`Hardware:    ${body.modelCode}${body.cpuType ? ` (${body.cpuType})` : ''}`);
    if (body.captureTime) lines.push(`Time:        ${body.captureTime}`);
    lines.push(
        `Exception:   ${[exception.type, exception.signal && `(${exception.signal})`, exception.subtype].filter(Boolean).join(' ') || 'unknown'}`
    );
    if (termination) {
        lines.push(`Termination: ${[termination.namespace, termination.code, termination.indicator].filter(v => v !== undefined).join(' ')}`);
    }
    const asi = body.asi || {};
    const asiLines = Object.keys(asi).sort().flatMap(library => [].concat(asi[library]).map(line => `${library}: ${line}`));
    if (asiLines.length) {
        lines.push('', 'Application Specific Information:', ...asiLines);
    }
    return lines;
}

/** A code block that `text` can't break out of. */
function codeBlock(text) {
    const longest = Math.max(2, ...(text.match(/`+/g) || []).map(run => run.length));
    const fence = '`'.repeat(longest + 1);
    return `${fence}text\n${text}\n${fence}`;
}

/**
 * The comment for `report`. `notes` are Markdown lines about how symbolication went, written by
 * this script (never from the issue).
 */
function renderComment({ report, traces, version, notes, maxLength = MAX_REPORT_LENGTH }) {
    const crashed = traces.filter(trace => trace.crashed);
    const others = traces.filter(trace => !trace.crashed);
    const render = trace =>
        [`${trace.title}:`, ...trace.frames.map(frameLine), ...(trace.note ? [`(${trace.note})`] : [])].join('\n');

    const main = [summaryLines(report, version).join('\n'), ...crashed.map(render)].join('\n\n');
    let otherText = others.map(render).join('\n\n');

    const build = other => {
        const parts = [COMMENT_MARKER, '### Symbolicated crash report', '', ...notes, '', codeBlock(main)];
        if (other) {
            parts.push('', `<details><summary>Other threads (${others.length})</summary>`, '', codeBlock(other), '', '</details>');
        }
        return parts.join('\n');
    };

    let comment = build(otherText);
    if (comment.length > maxLength) {
        // Drop other threads before anything else; the crashed one is what matters.
        const budget = maxLength - build('').length - 200;
        otherText = budget > 0 ? `${otherText.slice(0, budget)}\n... (cut short to fit in a comment)` : '';
        comment = build(otherText);
    }
    if (comment.length > maxLength) {
        comment = `${comment.slice(0, maxLength - 40)}\n... (cut short)`;
    }
    return comment;
}

/**
 * Symbolicates `report` against the dSYMs in `dsymsDirectory` (if any) and renders the comment.
 * `releaseNote` says where the dSYMs came from, or why there aren't any.
 */
function buildComment({ report, version, dsymsDirectory, releaseNote, dwarfdump, atos }) {
    const traces = backtraces(report);
    const notes = [releaseNote];
    if (dsymsDirectory) {
        const dsyms = dsymsByUUID(dsymsDirectory, dwarfdump);
        symbolicate(traces, dsyms, atos);

        // Our own binaries are the ones in the app bundle, outside its frameworks.
        const ours = new Map();
        for (const frame of traces.flatMap(trace => trace.frames)) {
            const imagePath = frame.image.path || '';
            if (/\.app\/Contents\/(MacOS|XPCServices)\//.test(imagePath) && !imagePath.includes('/Frameworks/')) {
                ours.set((frame.image.uuid || '').toLowerCase(), frame.imageName);
            }
        }
        const unmatched = [...ours].filter(([uuid]) => !dsyms.has(uuid)).map(([, name]) => name);
        if (unmatched.length) {
            notes.push(
                '',
                `:warning: No dSYM in that release matches ${unmatched.map(name => `\`${name.replace(/`/g, '')}\``).join(', ')}, ` +
                    "so this crash probably isn't from the release build (a local or development build, perhaps)."
            );
        }
        const symbolicated = traces.flatMap(trace => trace.frames).filter(frame => frame.symbolicated).length;
        notes.push('', `Symbolicated ${symbolicated} frame${symbolicated === 1 ? '' : 's'}.`);
    }
    return renderComment({ report, traces, version, notes });
}

// --- GitHub ------------------------------------------------------------------------------------

async function github(method, apiPath, body) {
    const response = await fetch(`${process.env.GITHUB_API_URL || 'https://api.github.com'}${apiPath}`, {
        method,
        headers: {
            Accept: 'application/vnd.github+json',
            Authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
            'X-GitHub-Api-Version': '2022-11-28',
        },
        body: body && JSON.stringify(body),
    });
    if (!response.ok) {
        const error = new Error(`${method} ${apiPath} failed: ${response.status} ${await response.text()}`);
        error.status = response.status;
        throw error;
    }
    return response.status === 204 ? null : response.json();
}

/** Downloads an issue attachment, without credentials (they're readable by anyone who can see the issue). */
async function downloadAttachment(url) {
    const response = await fetch(url, { redirect: 'follow' });
    if (!response.ok) {
        throw new Error(`downloading ${url} failed: ${response.status}`);
    }
    const length = Number(response.headers.get('content-length') || 0);
    if (length > MAX_ATTACHMENT_BYTES) {
        throw new Error(`${url} is too big (${length} bytes)`);
    }
    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.length > MAX_ATTACHMENT_BYTES) {
        throw new Error(`${url} is too big (${buffer.length} bytes)`);
    }
    return buffer.toString('utf8');
}

/** The crash report in an issue: the first attachment that is one, or else one in the body. */
async function findReport(issueBody, download = downloadAttachment) {
    for (const url of attachmentURLs(issueBody)) {
        try {
            const report = parseIPS(await download(url));
            if (report) {
                return report;
            }
        } catch (error) {
            console.log(`::warning::${error.message}`);
        }
    }
    return parseIPS(issueBody);
}

/** Downloads and unzips the release's dSYMs. Returns `{ directory, note }`. */
async function fetchDSYMs(repo, version) {
    let release;
    try {
        release = await github('GET', `/repos/${repo}/releases/tags/${encodeURIComponent(version)}`);
    } catch (error) {
        if (error.status !== 404) {
            throw error;
        }
        return { directory: null, note: `There's no release tagged \`${version}\`, so there are no dSYMs to symbolicate this crash with.` };
    }
    const asset = (release.assets || []).find(candidate => candidate.name === DSYMS_ASSET(version));
    if (!asset) {
        return {
            directory: null,
            note: `[Release ${version}](${release.html_url}) doesn't have \`${DSYMS_ASSET(version)}\` (releases before crash reporting don't), so this crash couldn't be symbolicated.`,
        };
    }

    const work = fs.mkdtempSync(path.join(os.tmpdir(), 'dsyms-'));
    const zip = path.join(work, asset.name);
    const response = await fetch(asset.url, {
        headers: { Accept: 'application/octet-stream', Authorization: `Bearer ${process.env.GITHUB_TOKEN}` },
        redirect: 'follow',
    });
    if (!response.ok) {
        throw new Error(`downloading ${asset.name} failed: ${response.status}`);
    }
    fs.writeFileSync(zip, Buffer.from(await response.arrayBuffer()));
    execFileSync('ditto', ['-x', '-k', zip, path.join(work, 'dSYMs')]);
    return { directory: path.join(work, 'dSYMs'), note: `Symbolicated with the dSYMs from [release ${version}](${release.html_url}).` };
}

async function findComment(repo, issueNumber) {
    for (let page = 1; ; page++) {
        const comments = await github('GET', `/repos/${repo}/issues/${issueNumber}/comments?per_page=100&page=${page}`);
        // Check the author too, so a pasted copy of the marker can't redirect the report.
        const existing = comments.find(
            comment => comment.user && comment.user.login === COMMENT_AUTHOR && (comment.body || '').startsWith(COMMENT_MARKER)
        );
        if (existing || comments.length < 100) {
            return existing;
        }
    }
}

async function upsertComment(repo, issueNumber, body) {
    const existing = await findComment(repo, issueNumber);
    if (existing && existing.body === body) {
        return 'unchanged';
    }
    if (existing) {
        await github('PATCH', `/repos/${repo}/issues/comments/${existing.id}`, { body });
        return 'updated';
    }
    await github('POST', `/repos/${repo}/issues/${issueNumber}/comments`, { body });
    return 'created';
}

const NO_REPORT_COMMENT = [
    COMMENT_MARKER,
    '### Symbolicated crash report',
    '',
    "I couldn't find a crash log in this issue. Please edit it to paste one into the **Crash log** field, " +
        'or attach one there as a `.txt` file, and I\'ll symbolicate it.',
    '',
    'Crash logs are in `~/Library/Logs/DiagnosticReports`, named like `Hammerspoon 2-2026-10-20-123456.ips`.',
].join('\n');

async function runForIssue(issueNumber) {
    const repo = process.env.GITHUB_REPOSITORY;
    const issue = await github('GET', `/repos/${repo}/issues/${issueNumber}`);
    const issueBody = issue.body || '';

    const report = await findReport(issueBody);
    if (!report) {
        // Only nag once; if the bot has already replied, leave that reply alone.
        if (!(await findComment(repo, issueNumber))) {
            await upsertComment(repo, issueNumber, NO_REPORT_COMMENT);
        }
        console.log(`No crash log found in #${issueNumber}`);
        return;
    }

    const version = crashedVersion(report, issueBody);
    const { directory, note } = version
        ? await fetchDSYMs(repo, version)
        : { directory: null, note: "The crash log doesn't say which version crashed, and neither does the issue, so it couldn't be symbolicated." };
    const comment = buildComment({ report, version, dsymsDirectory: directory, releaseNote: note });
    console.log(`Comment on #${issueNumber}: ${await upsertComment(repo, issueNumber, comment)}`);
}

function parseArgs(argv) {
    const args = {};
    for (let i = 0; i < argv.length; i++) {
        const match = argv[i].match(/^--(issue|report|dsyms)$/);
        if (!match || i + 1 >= argv.length) {
            return null;
        }
        args[match[1]] = argv[++i];
    }
    return args;
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args || (!args.issue && !args.report)) {
        console.error('Usage: node scripts/symbolicate-crash.js --issue <number>');
        console.error('       node scripts/symbolicate-crash.js --report <file> [--dsyms <dir>]');
        process.exit(2);
    }

    if (args.report) {
        const report = parseIPS(fs.readFileSync(args.report, 'utf8'));
        if (!report) {
            console.error(`${args.report} isn't a crash report`);
            process.exit(1);
        }
        const releaseNote = args.dsyms ? `Symbolicated with the dSYMs in \`${args.dsyms}\`.` : 'No dSYMs given.';
        console.log(buildComment({ report, version: crashedVersion(report, ''), dsymsDirectory: args.dsyms, releaseNote }));
        return;
    }

    if (!/^\d+$/.test(args.issue)) {
        console.error(`not an issue number: ${args.issue}`);
        process.exit(2);
    }
    await runForIssue(Number(args.issue));
}

if (require.main === module) {
    main().catch(error => {
        console.error(error);
        process.exit(1);
    });
}

module.exports = {
    attachmentURLs,
    parseIPS,
    formField,
    crashedVersion,
    dsymsByUUID,
    backtraces,
    symbolicate,
    renderComment,
    buildComment,
    findReport,
    codeBlock,
    COMMENT_MARKER,
    NO_REPORT_COMMENT,
};
