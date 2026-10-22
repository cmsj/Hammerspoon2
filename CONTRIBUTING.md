# Contributing to Hammerspoon 2

Please read the [AI policy](AI_POLICY.md) and [code of conduct](CODE_OF_CONDUCT.md) first.

## Changelog entries

Release notes are built from trailers in commit messages. If your change is
something users will notice, add one or more of these to the **last
paragraph** of a commit message (with no blank lines between them and any
`Co-Authored-By:` or `Signed-off-by:` lines):

```
Changelog-Added: hs.foo.bar(), which does a thing
Changelog-Changed: hs.foo.baz() now returns null instead of false
Changelog-Fixed: hs.foo.qux() no longer crashes on an empty string
```

- **Added** is for new API that users can now use.
- **Changed** is for existing API whose behaviour has changed.
- **Fixed** is for bugs that have been fixed.

Each entry is one line of markdown, and a commit can have as many as it
needs. Changes users won't see (refactoring, tests, CI) don't need one. A bot
will comment on your pull request if it can't find any entries, or if some
are malformed. To check your commits locally:

```bash
node scripts/release/changelog.js check --from origin/main
```
