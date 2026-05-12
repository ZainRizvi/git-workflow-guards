---
name: merge-pr
description: Squash merge the current branch's PR via gh
allowed-tools: Bash(gh pr merge:*), Bash(gh pr checks:*), Bash(gh run watch:*), Bash(gh run list:*), Bash(gh run view:*)
user-invokable: true
---

# Merge PR

## When to invoke

Only when the user has **explicitly asked for a merge** in this turn or earlier in the conversation. Merging is a human action — `gh pr merge --squash` lands code on `main` with destructive blast radius (force-update of refs, side-effects of any `on: push` workflow, public history rewrite if it goes wrong).

Do **not** invoke as a "natural next step" after PR creation, CI going green, or `/review` returning clean. Those produce a PR ready for human review; review and merge are the human's call.

If the original brief said "hand off to human review", "do not merge", or "human-only action", a terse follow-up like `merge?` / `ship it` / `merge if ci green` is **not** authorisation. Re-read the original brief before invoking. If in doubt, post the PR URL and ask explicitly.

## Procedure

1. Wait for the PR's CI checks to pass:

```bash
gh pr checks --watch --fail-fast
```

If checks fail, investigate with `gh run view <run-id> --log-failed`, fix the issues, push, and re-run this step until CI is green. Do NOT proceed with the merge until all checks pass.

2. Squash merge the PR:

```bash
gh pr merge --squash
```

3. Find the CI run triggered by the merge commit on the target branch:

```bash
gh run list --branch main --limit 1 --json databaseId,status,conclusion,headSha
```

4. Watch that run until it completes:

```bash
gh run watch <run-id> --exit-status
```

5. If checks fail, investigate what went wrong:

```bash
gh run view <run-id> --log-failed
```

Analyze the failed logs, identify the root cause, and report it with actionable next steps.
