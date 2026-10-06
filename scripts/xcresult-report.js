#!/usr/bin/env node

/**
 * Test Results Report
 *
 * Summarises an .xcresult bundle for CI, replacing the slidoapp/xcresulttool action (which
 * relies on `xcresulttool get --legacy`, whose output changed shape in Xcode 27). Reads the
 * bundle with `xcresulttool get test-results summary` (Xcode 16+) and:
 *
 *  1. Writes a Markdown report to the job summary ($GITHUB_STEP_SUMMARY), or stdout outside CI.
 *  2. Emits an `::error` workflow annotation for each failing test.
 *  3. On pull requests, when GITHUB_TOKEN is set, posts the report as a PR comment. The comment
 *     is created when tests fail and then updated in place on later runs (including once they
 *     pass), so a PR carries at most one of them and green PRs get no comment at all. Runs for a
 *     commit that's no longer the PR's head leave the comment alone, and the comment is trimmed
 *     to fit GitHub's size limit (the job summary always has every failure).
 *
 * Reporting problems are logged as warnings and never fail the job; the test step does that.
 *
 * Usage: node scripts/xcresult-report.js <path/to/TestResults.xcresult>
 */

const fs = require('fs');
const { execFileSync } = require('child_process');

const COMMENT_MARKER = '<!-- xcresult-report -->';
// Comments posted with the workflow's GITHUB_TOKEN are authored by this bot account.
const COMMENT_AUTHOR = 'github-actions[bot]';
// GitHub rejects comments over 65536 characters; leave room for the marker and footer.
const MAX_COMMENT_REPORT_LENGTH = 60000;
const MAX_COMMENT_FAILURE_TEXT_LENGTH = 4000;

function readSummary(bundlePath) {
    if (!fs.existsSync(bundlePath)) {
        return null;
    }
    const output = execFileSync(
        'xcrun',
        ['xcresulttool', 'get', 'test-results', 'summary', '--path', bundlePath, '--compact'],
        { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }
    );
    return JSON.parse(output);
}

function formatDuration(seconds) {
    if (!Number.isFinite(seconds)) {
        return 'unknown';
    }
    const minutes = Math.floor(seconds / 60);
    const remainder = (seconds % 60).toFixed(minutes ? 0 : 1);
    return minutes ? `${minutes}m ${remainder}s` : `${remainder}s`;
}

// Failure text is arbitrary, so fence it with more backticks than it contains.
function codeBlock(text) {
    const longestRun = Math.max(0, ...(text.match(/`+/g) || []).map(run => run.length));
    const fence = '`'.repeat(Math.max(3, longestRun + 1));
    return `${fence}\n${text}\n${fence}`;
}

// result can also be e.g. "Skipped" when nothing failed, so don't just compare it to "Passed".
function hasFailures(summary) {
    return !summary || summary.result === 'Failed' || summary.failedTests > 0;
}

/**
 * Renders the Markdown report. With `maxLength`, failure messages are shortened and failures
 * that don't fit are left out, with a pointer to `detailsURL` for the rest.
 */
function renderReport(summary, { maxLength = Infinity, detailsURL } = {}) {
    if (!summary) {
        return [
            '## :x: Test Results',
            '',
            'No test results were produced, so the build or test run probably failed before any ' +
                'tests ran. Check the job log.',
        ].join('\n');
    }

    const lines = [
        `## ${hasFailures(summary) ? ':x:' : ':white_check_mark:'} Test Results: ${summary.result}`,
        '',
        '| Total | Passed | Failed | Skipped | Expected Failures | Duration |',
        '| ---: | ---: | ---: | ---: | ---: | ---: |',
        `| ${summary.totalTestCount} | ${summary.passedTests} | ${summary.failedTests} | ` +
            `${summary.skippedTests} | ${summary.expectedFailures} | ` +
            `${formatDuration(summary.finishTime - summary.startTime)} |`,
    ];

    const devices = (summary.devicesAndConfigurations || [])
        .map(({ device }) => device && `${device.modelName}, ${device.platform} ${device.osVersion} (${device.osBuildNumber})`)
        .filter(Boolean);
    if (devices.length) {
        lines.push('', `Ran on: ${[...new Set(devices)].join('; ')}`);
    }

    const failures = summary.testFailures || [];
    if (failures.length) {
        lines.push('', '### Failures');
        // Reserve room for the "more failures" line, should it be needed.
        let length = lines.join('\n').length + 200;
        for (const [index, failure] of failures.entries()) {
            let text = failure.failureText || '(no failure message)';
            if (Number.isFinite(maxLength) && text.length > MAX_COMMENT_FAILURE_TEXT_LENGTH) {
                text = `${text.slice(0, MAX_COMMENT_FAILURE_TEXT_LENGTH)}\n… (truncated)`;
            }
            const entry = [
                '',
                `**${failure.targetName} › ${failure.testIdentifierString || failure.testName}**`,
                '',
                codeBlock(text),
            ].join('\n');
            if (length + entry.length > maxLength) {
                const remaining = failures.length - index;
                const where = detailsURL ? `[the job summary](${detailsURL})` : 'the job summary';
                lines.push('', `…and ${remaining} more failure${remaining === 1 ? '' : 's'}; see ${where}.`);
                break;
            }
            lines.push(entry);
            length += entry.length + 1;
        }
    }

    return lines.join('\n');
}

// Workflow commands need %, CR and LF escaped in the message, and also : and , in properties.
function escapeData(text) {
    return text.replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
}

function escapeProperty(text) {
    return escapeData(text).replace(/:/g, '%3A').replace(/,/g, '%2C');
}

function annotateFailures(summary) {
    for (const failure of (summary && summary.testFailures) || []) {
        const title = `${failure.targetName}/${failure.testIdentifierString || failure.testName}`;
        console.log(`::error title=${escapeProperty(title)}::${escapeData(failure.failureText || 'Test failed')}`);
    }
}

async function github(method, path, body) {
    const response = await fetch(`${process.env.GITHUB_API_URL || 'https://api.github.com'}${path}`, {
        method,
        headers: {
            Accept: 'application/vnd.github+json',
            Authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
            'X-GitHub-Api-Version': '2022-11-28',
        },
        body: body && JSON.stringify(body),
    });
    if (!response.ok) {
        throw new Error(`${method} ${path} failed: ${response.status} ${await response.text()}`);
    }
    return response.json();
}

async function findReportComment(repo, prNumber) {
    for (let page = 1; ; page++) {
        const comments = await github('GET', `/repos/${repo}/issues/${prNumber}/comments?per_page=100&page=${page}`);
        // Check the author too, so a pasted copy of the marker can't redirect the report.
        const existing = comments.find(
            comment =>
                comment.user && comment.user.login === COMMENT_AUTHOR &&
                comment.body && comment.body.startsWith(COMMENT_MARKER)
        );
        if (existing || comments.length < 100) {
            return existing;
        }
    }
}

async function upsertPRComment({ summary, repo, prNumber, headSha, runURL }) {
    const report = renderReport(summary, { maxLength: MAX_COMMENT_REPORT_LENGTH, detailsURL: runURL });
    const body = `${COMMENT_MARKER}\n${report}\n\n<sub>From [this run](${runURL}) of ${headSha}.</sub>`;

    const existing = await findReportComment(repo, prNumber);
    if (!existing && !hasFailures(summary)) {
        return 'skipped';
    }

    // A run for an older commit can finish after a newer one; don't let it overwrite that report.
    const pr = await github('GET', `/repos/${repo}/pulls/${prNumber}`);
    if (pr.head.sha !== headSha) {
        console.log(`Not updating the PR comment: ${headSha} is no longer the head of #${prNumber}.`);
        return 'outdated';
    }

    if (existing) {
        await github('PATCH', `/repos/${repo}/issues/comments/${existing.id}`, { body });
        return 'updated';
    }
    await github('POST', `/repos/${repo}/issues/${prNumber}/comments`, { body });
    return 'created';
}

async function main() {
    const bundlePath = process.argv[2];
    if (!bundlePath) {
        console.error('Usage: node scripts/xcresult-report.js <path/to/TestResults.xcresult>');
        process.exit(2);
    }

    let summary;
    try {
        summary = readSummary(bundlePath);
    } catch (error) {
        console.log(`::warning::Couldn't read test results from ${escapeData(bundlePath)}: ${escapeData(error.message)}`);
        summary = null;
    }

    const report = renderReport(summary);
    if (process.env.GITHUB_STEP_SUMMARY) {
        fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${report}\n`);
    } else {
        console.log(report);
    }
    annotateFailures(summary);

    const repo = process.env.GITHUB_REPOSITORY;
    const event = process.env.GITHUB_EVENT_PATH && JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    const pullRequest = event && event.pull_request;
    if (!process.env.GITHUB_TOKEN || !repo || !pullRequest) {
        return;
    }
    try {
        await upsertPRComment({
            summary,
            repo,
            prNumber: pullRequest.number,
            headSha: pullRequest.head.sha,
            runURL: `${process.env.GITHUB_SERVER_URL}/${repo}/actions/runs/${process.env.GITHUB_RUN_ID}`,
        });
    } catch (error) {
        console.log(`::warning::Couldn't post the test report to the pull request: ${escapeData(error.message)}`);
    }
}

if (require.main === module) {
    main();
}

module.exports = { renderReport, hasFailures, annotateFailures, upsertPRComment, COMMENT_MARKER, COMMENT_AUTHOR };
