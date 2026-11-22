/**
 * The pull request comment posted by .github/workflows/changelog.yml, from
 * the output of `changelog.js check --json`.
 */

const MARKER = '<!-- changelog-trailers -->';

const HOW_TO = `To add something to the release notes, put one or more of these trailers in the **last paragraph** of a commit message, alongside any \`Co-Authored-By:\` lines and with no blank lines between them:

\`\`\`
Changelog-Added: hs.foo.bar(), which does a thing
Changelog-Changed: hs.foo.baz() now returns null instead of false
Changelog-Fixed: hs.foo.qux() no longer crashes on an empty string
\`\`\`

- **Added** is for new API that users can now use.
- **Changed** is for existing API whose behaviour has changed.
- **Fixed** is for bugs that have been fixed.

Each entry is one line of markdown (an indented following line continues it), and a commit can have as many as it needs. To change an existing commit's message, use \`git commit --amend\` or \`git rebase -i\`, then force-push.`;

// Problems and previews quote commit messages, which anyone opening a pull
// request controls, so the bot mustn't post them as-is.
const MAX_LINE_LENGTH = 500;
const MAX_LINES = 60;

/**
 * Make text from commit messages safe to post: break @mentions (a zero-width
 * space after the @ stops GitHub notifying anyone, including teams), and
 * clip long lines and long lists so the comment stays readable and under
 * GitHub's size limit.
 */
function quote(text) {
    const lines = text.replace(/\n$/, '').split('\n').map((line) => {
        const clipped = line.length > MAX_LINE_LENGTH ? `${line.slice(0, MAX_LINE_LENGTH)}…` : line;
        return clipped.replace(/@(?=[\w-])/g, '@\u200b');
    });
    if (lines.length > MAX_LINES) {
        const more = lines.length - MAX_LINES;
        lines.splice(MAX_LINES, more, `…and ${more} more line${more === 1 ? '' : 's'}`);
    }
    return lines.join('\n');
}

/**
 * What to do with the PR's changelog comment.
 *
 * Returns { body, create }: body is the comment's text, and create says
 * whether to post it if there isn't one already (otherwise it only updates
 * an existing one, so PRs with valid entries don't get a new comment).
 */
function changelogComment({ count, problems, preview }, author) {
    if (problems.length > 0) {
        const list = quote(problems.map((problem) => `- ${problem}`).join('\n'));
        return {
            create: true,
            body: `${MARKER}\n@${author}, some changelog trailers in this pull request won't be picked up:\n\n${list}\n\n${HOW_TO}`,
        };
    }
    if (count === 0) {
        return {
            create: true,
            body: `${MARKER}\n@${author}, none of the commits in this pull request have a changelog entry, so it won't appear in the release notes. That's fine if it doesn't change anything users can see.\n\n${HOW_TO}`,
        };
    }
    return {
        create: false,
        body: `${MARKER}\nThanks! This pull request will add these entries to the release notes:\n\n${quote(preview)}\n`,
    };
}

module.exports = { changelogComment, quote, MARKER };
