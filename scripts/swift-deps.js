#!/usr/bin/env node

/**
 * Swift Package Dependency Report
 *
 * Dependabot can't update Swift packages that are referenced from an Xcode project (it only
 * understands a standalone Package.swift), so .github/workflows/swift-deps.yml does it instead.
 * This script is the part of that workflow that isn't xcodebuild:
 *
 *   update-summary <old Package.resolved> <new Package.resolved>
 *       Prints a Markdown summary of what changed between two resolutions, with links to each
 *       package's upstream diff. Used as the body of the update pull request.
 *
 *   fork-report [--json]
 *       Most of our packages are forks. For each of our forks in Package.resolved (those owned by
 *       this repository's owner, whether we depend on them directly or not), compares the branch
 *       (or revision) we use with its upstream's default branch, and with the root of the fork
 *       network when that's a different repository, and suggests re-syncing when upstream has
 *       moved on, or switching back to upstream when the fork has nothing of its own. Also
 *       lists newer versions of directly-referenced packages that the project's version
 *       requirement won't take, since re-resolving can't pick those up. Prints Markdown, or
 *       with --json, { actionable, body } for the workflow to put in a tracking issue.
 *
 * fork-report calls the GitHub API, using GITHUB_TOKEN when it's set.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const RESOLVED_PATH = path.join(ROOT, 'Hammerspoon 2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved');
const PBXPROJ_PATH = path.join(ROOT, 'Hammerspoon 2.xcodeproj/project.pbxproj');

const REPORT_MARKER = '<!-- swift-deps-fork-report -->';
const REPORT_TITLE = 'Swift package forks and versions need attention';
// Tag listings are paged 100 at a time; no package we use has anywhere near this many.
const MAX_TAG_PAGES = 10;

/** "https://github.com/owner/repo(.git)" -> "owner/repo", or null for anything not on GitHub. */
function githubRepo(location) {
    const match = /^https:\/\/github\.com\/([^/]+)\/([^/]+?)(?:\.git)?\/?$/i.exec(location || '');
    return match ? `${match[1]}/${match[2]}` : null;
}

/** The pins in a Package.resolved file (format version 2 or 3). */
function parseResolved(text) {
    const resolved = JSON.parse(text);
    return (resolved.pins || []).map(pin => ({
        identity: pin.identity,
        location: pin.location,
        repo: githubRepo(pin.location),
        branch: pin.state.branch || null,
        revision: pin.state.revision,
        version: pin.state.version || null,
    }));
}

/**
 * The version requirements of the project's remote package references, keyed by lowercased
 * "owner/repo". Each is the pbxproj's requirement dictionary: { kind, minimumVersion, ... }.
 */
function parseRequirements(pbxproj) {
    const requirements = new Map();
    const blocks = pbxproj.matchAll(/\/\* XCRemoteSwiftPackageReference "[^"]*" \*\/ = \{([\s\S]*?)\n\t\t\};/g);
    for (const [, block] of blocks) {
        const url = /repositoryURL = "([^"]+)";/.exec(block);
        const body = /requirement = \{([\s\S]*?)\};/.exec(block);
        const repo = url && githubRepo(url[1]);
        if (!repo || !body) {
            continue;
        }
        const requirement = {};
        for (const [, key, value] of body[1].matchAll(/(\w+) = "?([^";]+)"?;/g)) {
            requirement[key] = value;
        }
        requirements.set(repo.toLowerCase(), requirement);
    }
    return requirements;
}

/** [major, minor, patch] for a release tag like "1.2.3" or "v1.2", or null (pre-releases too). */
function parseVersion(tag) {
    const match = /^v?(\d+)\.(\d+)(?:\.(\d+))?$/.exec(tag || '');
    return match ? [Number(match[1]), Number(match[2]), Number(match[3] || 0)] : null;
}

function compareVersions(a, b) {
    for (let i = 0; i < 3; i++) {
        if (a[i] !== b[i]) {
            return a[i] - b[i];
        }
    }
    return 0;
}

/** The highest release among some tag names, as { tag, version }, or null if none are releases. */
function latestRelease(tags) {
    let latest = null;
    for (const tag of tags) {
        const version = parseVersion(tag);
        if (version && (!latest || compareVersions(version, latest.version) > 0)) {
            latest = { tag, version };
        }
    }
    return latest;
}

/**
 * Whether a version is allowed by an Xcode package requirement. Returns null for requirements
 * that aren't version ranges (branch, revision), where the question doesn't apply.
 */
function versionAllowed(requirement, version) {
    const min = parseVersion(requirement.minimumVersion);
    switch (requirement.kind) {
        case 'upToNextMajorVersion':
            return compareVersions(version, min) >= 0 && version[0] === min[0];
        case 'upToNextMinorVersion':
            return compareVersions(version, min) >= 0 && version[0] === min[0] && version[1] === min[1];
        case 'versionRange':
            return compareVersions(version, min) >= 0 &&
                compareVersions(version, parseVersion(requirement.maximumVersion)) < 0;
        case 'exactVersion':
            return compareVersions(version, parseVersion(requirement.version)) === 0;
        default:
            return null;
    }
}

function describeRequirement(requirement) {
    switch (requirement.kind) {
        case 'upToNextMajorVersion':
            return `up to next major from ${requirement.minimumVersion}`;
        case 'upToNextMinorVersion':
            return `up to next minor from ${requirement.minimumVersion}`;
        case 'versionRange':
            return `${requirement.minimumVersion} up to ${requirement.maximumVersion}`;
        case 'exactVersion':
            return `exactly ${requirement.version}`;
        default:
            return requirement.kind;
    }
}

function shortRevision(revision) {
    return revision ? revision.slice(0, 7) : '?';
}

/** How a pin reads in a summary: its version, or branch@revision. */
function describePin(pin) {
    if (pin.version) {
        return pin.version;
    }
    return pin.branch ? `${pin.branch}@${shortRevision(pin.revision)}` : shortRevision(pin.revision);
}

/** The packages whose pins differ between two resolutions, sorted by identity. */
function diffPins(oldPins, newPins) {
    const before = new Map(oldPins.map(pin => [pin.identity, pin]));
    const after = new Map(newPins.map(pin => [pin.identity, pin]));
    const identities = [...new Set([...before.keys(), ...after.keys()])].sort();
    const changes = [];
    for (const identity of identities) {
        const from = before.get(identity) || null;
        const to = after.get(identity) || null;
        if (from && to && from.revision === to.revision && from.location === to.location) {
            continue;
        }
        changes.push({ identity, from, to });
    }
    return changes;
}

function renderUpdateSummary(changes) {
    if (changes.length === 0) {
        return 'No Swift package updates.';
    }
    const rows = changes.map(({ identity, from, to }) => {
        const pin = to || from;
        const name = pin.repo ? `[${identity}](https://github.com/${pin.repo})` : identity;
        if (!from) {
            return `| ${name} | | ${describePin(to)} | New dependency |`;
        }
        if (!to) {
            return `| ${name} | ${describePin(from)} | | No longer a dependency |`;
        }
        const diff = to.repo && from.location === to.location
            ? `[Diff](https://github.com/${to.repo}/compare/${from.revision}...${to.revision})`
            : `Moved from ${from.location}`;
        return `| ${name} | ${describePin(from)} | ${describePin(to)} | ${diff} |`;
    });
    return [
        'Re-resolved the Xcode project\'s Swift packages to the newest versions their requirements allow.',
        '',
        '| Package | From | To | Changes |',
        '| --- | --- | --- | --- |',
        ...rows,
        '',
        'Packages that are forks, and newer versions the requirements won\'t take, are tracked in the ' +
            `"${REPORT_TITLE}" issue when there's something to do.`,
        '',
        'This pull request was opened by the Swift dependencies workflow (`.github/workflows/swift-deps.yml`), ' +
            'which starts the test suite itself, since pull requests opened by GitHub Actions don\'t.',
    ].join('\n');
}

/**
 * What to do about a fork, from how many commits it has that upstream doesn't (ahead) and how
 * many upstream has that it doesn't (behind). Returns { actionable, text }.
 */
function forkAdvice({ ahead, behind }) {
    if (ahead === 0 && behind === 0) {
        return { actionable: true, text: 'Identical to upstream; consider depending on upstream directly' };
    }
    if (ahead === 0) {
        return { actionable: true, text: 'No changes of its own; consider depending on upstream directly, or fast-forward the fork' };
    }
    if (behind > 0) {
        return { actionable: true, text: 'Re-sync: merge upstream into the fork' };
    }
    return { actionable: false, text: 'Up to date' };
}

/**
 * A GitHub REST client: api('/repos/...') resolves to the parsed JSON response.
 * Reads GITHUB_TOKEN when set; anonymous requests work too, with a much lower rate limit.
 */
function makeAPI(token = process.env.GITHUB_TOKEN) {
    return async function api(apiPath) {
        const response = await fetch(`${process.env.GITHUB_API_URL || 'https://api.github.com'}${apiPath}`, {
            headers: {
                Accept: 'application/vnd.github+json',
                ...(token ? { Authorization: `Bearer ${token}` } : {}),
                'X-GitHub-Api-Version': '2022-11-28',
            },
        });
        if (!response.ok) {
            throw new Error(`GET ${apiPath} failed: ${response.status} ${await response.text()}`);
        }
        return response.json();
    };
}

async function listTags(api, repo) {
    const tags = [];
    for (let page = 1; page <= MAX_TAG_PAGES; page++) {
        const batch = await api(`/repos/${repo}/tags?per_page=100&page=${page}`);
        tags.push(...batch.map(tag => tag.name));
        if (batch.length < 100) {
            break;
        }
    }
    return tags;
}

/**
 * Compares a fork's ref with an upstream repository's default branch. The compare is made in
 * the fork, with upstream's branch as the base, so ahead_by counts the fork's own commits and
 * behind_by counts upstream's new ones.
 */
async function compareWithUpstream(api, fork, ref, upstream) {
    const [owner] = upstream.full_name.split('/');
    const base = `${owner}:${upstream.default_branch}`;
    const comparison = await api(`/repos/${fork}/compare/${encodeURIComponent(base)}...${encodeURIComponent(ref)}`);
    const latest = latestRelease(await listTags(api, upstream.full_name));
    return {
        upstream: upstream.full_name,
        upstreamBranch: upstream.default_branch,
        ahead: comparison.ahead_by,
        behind: comparison.behind_by,
        latestRelease: latest && latest.tag,
    };
}

/**
 * Our forks among some pins (those owned by `owner`, so other people's forks that we merely
 * depend on aren't included), each compared with its parent and, if different, its root.
 */
async function collectForks(api, pins, owner) {
    const forks = [];
    for (const pin of pins) {
        if (!pin.repo || pin.repo.split('/')[0].toLowerCase() !== owner.toLowerCase()) {
            continue;
        }
        const info = await api(`/repos/${pin.repo}`);
        if (!info.fork || !info.parent) {
            continue;
        }
        const ref = pin.branch || pin.revision;
        const upstreams = [info.parent];
        if (info.source && info.source.full_name !== info.parent.full_name) {
            upstreams.push(info.source);
        }
        for (const upstream of upstreams) {
            forks.push({
                identity: pin.identity,
                repo: info.full_name,
                ref,
                ...await compareWithUpstream(api, info.full_name, ref, upstream),
            });
        }
    }
    return forks;
}

/** Version-pinned direct dependencies with a newer release than their requirement allows. */
async function collectOutOfRange(api, pins, requirements) {
    const outOfRange = [];
    for (const pin of pins) {
        const requirement = pin.repo && requirements.get(pin.repo.toLowerCase());
        const current = parseVersion(pin.version);
        if (!requirement || !current) {
            continue;
        }
        const latest = latestRelease(await listTags(api, pin.repo));
        if (latest && compareVersions(latest.version, current) > 0 && versionAllowed(requirement, latest.version) === false) {
            outOfRange.push({
                identity: pin.identity,
                repo: pin.repo,
                current: pin.version,
                latest: latest.tag,
                requirement: describeRequirement(requirement),
            });
        }
    }
    return outOfRange;
}

function renderForkReport(forks, outOfRange, { runURL } = {}) {
    const lines = [REPORT_MARKER];
    let actionable = outOfRange.length > 0;

    lines.push('## Forks', '');
    if (forks.length === 0) {
        lines.push('None of the Swift packages are our forks.');
    } else {
        lines.push(
            '| Package | Fork | Upstream | Fork-only commits | New upstream commits | Upstream\'s latest release | Suggestion |',
            '| --- | --- | --- | ---: | ---: | --- | --- |'
        );
        for (const fork of forks) {
            const advice = forkAdvice(fork);
            actionable = actionable || advice.actionable;
            const forkLink = `[${fork.repo}@${fork.ref.length === 40 ? shortRevision(fork.ref) : fork.ref}](https://github.com/${fork.repo}/tree/${fork.ref})`;
            const upstreamLink = `[${fork.upstream}@${fork.upstreamBranch}](https://github.com/${fork.upstream})`;
            const [upstreamOwner] = fork.upstream.split('/');
            // Upstream's commits that the fork doesn't have.
            const behind = fork.behind > 0
                ? `[${fork.behind}](https://github.com/${fork.repo}/compare/${fork.ref}...${upstreamOwner}:${fork.upstreamBranch})`
                : '0';
            const suggestion = advice.actionable ? `**${advice.text}**` : advice.text;
            lines.push(`| ${fork.identity} | ${forkLink} | ${upstreamLink} | ${fork.ahead} | ${behind} | ${fork.latestRelease || 'None'} | ${suggestion} |`);
        }
        lines.push(
            '',
            'A fork that is also a fork of something else is listed against both its parent and the root of its fork network.'
        );
    }

    lines.push('', '## Newer versions outside the requirement', '');
    if (outOfRange.length === 0) {
        lines.push('Every version-pinned package is on a release its requirement allows, and none have a newer one beyond it.');
    } else {
        lines.push(
            'Re-resolving can\'t pick these up. Change the package\'s requirement in Xcode to try them.',
            '',
            '| Package | Current | Latest | Requirement |',
            '| --- | --- | --- | --- |'
        );
        for (const entry of outOfRange) {
            lines.push(`| [${entry.identity}](https://github.com/${entry.repo}/releases) | ${entry.current} | ${entry.latest} | ${entry.requirement} |`);
        }
    }

    if (runURL) {
        lines.push('', `<sub>From [this run](${runURL}) of the Swift dependencies workflow.</sub>`);
    }
    return { actionable, body: lines.join('\n') };
}

/** The owner of this repository: from Actions' environment, or else the origin remote. */
function repositoryOwner() {
    if (process.env.GITHUB_REPOSITORY_OWNER) {
        return process.env.GITHUB_REPOSITORY_OWNER;
    }
    const origin = execFileSync('git', ['remote', 'get-url', 'origin'], { cwd: ROOT, encoding: 'utf8' }).trim();
    const match = /github\.com[:/]([^/]+)\//.exec(origin);
    if (!match) {
        throw new Error(`Can't tell who owns this repository from its origin remote, ${origin}; set GITHUB_REPOSITORY_OWNER`);
    }
    return match[1];
}

async function main() {
    const [command, ...args] = process.argv.slice(2);
    if (command === 'update-summary' && args.length === 2) {
        const [oldPins, newPins] = args.map(file => parseResolved(fs.readFileSync(file, 'utf8')));
        console.log(renderUpdateSummary(diffPins(oldPins, newPins)));
        return;
    }
    if (command === 'fork-report') {
        const api = makeAPI();
        const pins = parseResolved(fs.readFileSync(RESOLVED_PATH, 'utf8'));
        const requirements = parseRequirements(fs.readFileSync(PBXPROJ_PATH, 'utf8'));
        const runURL = process.env.GITHUB_RUN_ID &&
            `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`;
        const report = renderForkReport(await collectForks(api, pins, repositoryOwner()), await collectOutOfRange(api, pins, requirements), { runURL });
        console.log(args.includes('--json') ? JSON.stringify(report) : report.body);
        return;
    }
    console.error('Usage: node scripts/swift-deps.js update-summary <old Package.resolved> <new Package.resolved>');
    console.error('       node scripts/swift-deps.js fork-report [--json]');
    process.exit(2);
}

if (require.main === module) {
    main().catch(error => {
        console.error(error.message);
        process.exit(1);
    });
}

module.exports = {
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
    REPORT_TITLE,
};
