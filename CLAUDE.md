# Hard Constraints

## 1. Never act without explicit approval

Do NOT modify files, run builds, explore code, or take any action until the user explicitly asks for it. This applies to everything: code edits, memory writes, file reads for research, build commands. Present analysis or proposals first, then wait. "Go ahead", "do it", "yes" or similar explicit approval is required before any action.

## 2. Development process for code changes

Every code change must follow this process in order:

1. **Analyze** the problem
2. **Check for existing tests** covering the code to be modified
3. **Present findings** and proposed approach — then stop and wait for approval
4. **Make the changes**
5. **Build and run tests** to verify
6. **Only then** report the work as done

## 3. Running tests — ALL tests must pass before pushing

Never push code unless ALL tests pass. This means:

1. The full xcodebuild test suite (not a subset):
```
xcodebuild build-for-testing -scheme Development -project "Hammerspoon 2.xcodeproj" -configuration Debug -destination "platform=macOS,arch=arm64"
xcodebuild test-without-building -scheme Development -project "Hammerspoon 2.xcodeproj" -configuration Debug -destination "platform=macOS,arch=arm64" -only-testing:"Hammerspoon 2Tests"
```

2. Any other test scripts in the repo (e.g. `scripts/test-hs2.sh`).

Running a subset of tests for quick iteration during development is fine, but the full suite must pass before committing or pushing. Do not cherry-pick which tests to run — run them all.

## 4. No issues or pull requests without approval

Do NOT create GitHub issues, pull requests, or post comments without explicit user approval. These are public-facing actions visible to others and cannot be easily undone. Always present the proposed content and wait for confirmation before creating.

## 5. Verify findings before reporting

When assessing bugs or issues found during review, I must verify which branch they exist on before reporting them. A bug visible in a PR diff may be pre-existing on `main` or introduced by the feature branch — the response is different for each. Check the actual code on the relevant branch before filing issues or making claims about scope.

## 6. Search for all dependents before changing behavior

When making a behavioral change (exit codes, return values, API contracts, protocols), I must grep the entire repo for all code that depends on the old behavior — not just the files I already know about. This includes test scripts, shell scripts, documentation, and any other consumers. Missing dependents causes silent breakage.

## 7. Fix bugs, never fix tests to work around bugs

When a test fails, fix the code, not the test. Tests exist to catch bugs. Modifying a test to pass despite a bug is hiding the problem. This software must be professional-grade and highly reliable.

If ignoring it would be a process failure regardless of context, it belongs in CLAUDE.md. If it's information that helps make better decisions when relevant, it goes in memory.

When asked to remember something, I must fully understand the impact of the request and determine where it should be recorded so it is reliably retrieved and applied when applicable. User requests to remember something are not hints — they are strong directives to follow. If it is unclear where to store information or which rule takes precedence, I must ask for clarification before acting. CLAUDE.md cannot contain every constraint; I must use judgment to place information where it will be most effective.
