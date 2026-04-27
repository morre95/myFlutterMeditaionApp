---
name: review
description: Reviews all uncommitted changes against project standards before committing. Use when the user asks to review changes, check code before committing, or run a pre-commit review.
---

# Review

Review all uncommitted changes in this project against the project rules.

## Process

1. **Gather changes**: Run `git diff --staged` for staged changes, or `git diff` if nothing is staged. Also check `git status` for new untracked files.

2. **Check each changed file against the project rules** (`.cursor/rules/*.mdc`):

   ### Code Quality
   - Is there dead code, unused imports, or commented-out code?
   - Are there bandaid fixes or workarounds instead of root-cause solutions?
   - Is anything over-engineered for what it needs to do?

   ### Architecture
   - Does this follow existing patterns in the codebase?
   - Is there duplicate logic that should use an existing shared component or utility?
   - Are dependencies pointing in the right direction (inward, not outward)?

   ### Consistency
   - Does the code match the style and structure of similar files in the project?
   - For Flutter UI: are spacing, colors, theme usage, and widget patterns consistent with the rest of the app?
   - For services: are error handling, provider abstractions, and validation patterns consistent?

   ### Reuse
   - Could any new component, function, or pattern already exist in the codebase? Search before approving.
   - If something similar exists, flag it — it should be reused or extracted into a shared utility.

   ### Security
   - Any hardcoded secrets, credentials, or API keys?
   - Is user input validated at the boundary?
   - Are OAuth tokens, provider credentials, file paths, and local permissions handled safely?
   - Does the change preserve the rule that source audio files are read-only?

   ### Performance
   - Any blocking file, provider, secure-storage, or audio work on the UI thread?
   - Any unbounded local/cloud library listing missing pagination or incremental loading?
   - Flutter UI: unnecessary rebuilds, missing debounce on search/provider inputs?

3. **Verdict**: Provide one of:
   - **Ready to commit** — no issues found
   - **Minor issues** — list them, but committing is acceptable after acknowledging
   - **Needs changes** — list specific issues that must be fixed before committing

For each issue, provide: the file, the line(s), what's wrong, and what the fix should be.
