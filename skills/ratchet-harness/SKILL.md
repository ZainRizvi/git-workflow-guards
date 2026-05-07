---
name: ratchet-harness
description: REQUIRED whenever CI fails, a code-review pass flags a Medium+ finding, a test that passed locally fails on push, you discover a class of mistake the project's checks didn't catch, or a recurring scan skips the same false-positive twice. Use BEFORE writing the fix to decide if a lint rule, structural test, project-doc note, ratchet entry, or skill update could have caught it — and if so, add that rule first, in a separate commit.
---

# Skill: ratchet-harness

You just hit a failure that the project's automated checks (lint, types, tests, hooks, CI) should have caught earlier. This skill is the contract: before you fix the underlying bug, you ask whether a guard could have caught it — and if yes, you add that guard first.

The principle is one-way: **every failure becomes a new rule. Mistakes don't repeat. Rules are added, never silently removed.** That ratcheting is what keeps an autonomous (or near-autonomous) workflow from regressing into the same class of failure month after month.

## Trigger

Read this skill **before** writing the fix when any of these happen:

- CI failed for a reason you didn't catch locally.
- A code review flagged a Medium+ impact finding that lint/tests should have caught.
- A test that passed locally failed on push.
- You discovered a class of mistake while reading code (your own or someone else's) that no automated check would catch.
- The same false-positive shape has been hand-waved past in two consecutive runs of any read-only scan/audit.

If you skip this skill, you fix the bug; the next agent (or the next you) hits the same shape of failure in three weeks. The ratchet fails to advance — that is the failure mode this skill exists to prevent.

## Goal

Decide which response applies and execute it **before** fixing the original failure:

1. **Add a lint or structural test** — if a deterministic rule could have caught the failure at write-time.
2. **Add a project-doc note** (CLAUDE.md, AGENTS.md, README, or a per-directory equivalent) — if the failure is real but not lint-checkable, capture the exact incident in prose.
3. **Add an entry to `.claude/ratchets.md`** — if the failure doesn't fit any of the above but is worth remembering as a class. This file is a chronological log of incidents the harness should learn from; see [The ratchets log](#the-ratchets-log) below.
4. **Update a skill** — if the failure points to a procedural gap.
5. **Tighten a guardrail** — if a recurring scan keeps skipping the same false-positive class.
6. **Do nothing harness-side** — if the failure was a genuine one-off (network flake, pre-existing on the default branch). This is valid but must be justified, not assumed by default.

## Procedure

### 1. Reproduce the failure

Don't fix from a stack trace alone. Reproduce locally:

- For test failures: run the failing test in isolation. Confirm it fails on your branch.
- For CI failures that didn't reproduce locally: identify *what about CI's environment differs* from yours (env vars, DB state, file order, glob-filtered lint scope, container image, etc.).
- For review findings: re-read the flagged code and confirm the finding is correct.

If you can't reproduce, the "fix" is a guess. Surface the inability before continuing.

### 2. Check `.claude/ratchets.md` for prior incidents of the same class

Before deciding which response applies, grep `.claude/ratchets.md` (if the file exists) for the failure shape. Two outcomes:

- **Match found, with a rule already in place**: the rule didn't fire on this incident. Find out why (file scope, stale allow-list, glob mismatch). Tighten the existing rule rather than adding a parallel one.
- **Match found, no rule yet**: the harness was already on notice for this class and didn't act. Promote the ratchet entry to a real rule (steps 3-6 below) and append a note to the existing entry that it's been promoted.
- **No match**: this is a fresh incident. Continue to step 3.

### 3. Could a lint rule have caught it?

Look at the failure. Is the bad code shape **mechanically describable**?

This skill is language-agnostic. The examples below use ESLint to make the *shape of the question* concrete; substitute your project's linter (ESLint, ruff, golangci-lint, clippy, rubocop, …) and look for an equivalent rule:

- "We awaited a non-Thenable" → ESLint's `@typescript-eslint/await-thenable`.
- "We threw a string instead of an Error" → ESLint's `@typescript-eslint/only-throw-error`.
- "A new domain imports from another domain it shouldn't" → ESLint's `eslint-plugin-import` `no-restricted-paths`.
- "We forgot a docstring" → Python's `pydocstyle` / `ruff`; not lintable in languages without enforced docstring conventions.

If the rule **already exists** but didn't fire, find out why (file scope mismatch, a stale `// eslint-disable`, glob excluding the file, autofix erasing it). Fix the rule's coverage before fixing the bug.

If the rule **doesn't exist** but the shape is lintable, **add the rule first**, in a separate structural-only commit before the bug fix. The error message must be a remediation prompt — say "X is not allowed; use Y instead — see <file>" rather than just "Bad code."

### 4. Could a structural test have caught it?

If the failure is about *graph-shape* properties — "domain A now imports domain B," "this file got too big," "this function lost its colocated test," "two files now contain the same magic string" — that's a job for a structural test that walks the code graph (e.g. via `madge`, `dependency-cruiser`, AST-based custom tests), not a per-file linter. Linters see one file at a time; structural tests walk the graph.

If a structural test exists for this property, why didn't it fire? (Probably a stale allow-list.)

If one doesn't exist but should, write it. Same rule: separate structural-only commit before the bug fix.

### 5. Is it a project-doc note or a ratchets-log entry?

Some failure modes aren't lintable but are concrete:

- "When migration X runs against a forked DB branch, the schema tool silently no-ops the column rename." (Tooling quirk.)
- "Webhook delivery order is not guaranteed by this provider." (External system property.)
- "Don't trust the LLM's `temperature: 0` for determinism." (Model property.)

**Where it belongs depends on visibility need:**

- **Universally relevant to this project** (every contributor needs to know): goes in CLAUDE.md / AGENTS.md / a per-directory equivalent. Format: one or two sentences naming the exact thing that bit you and what to do instead. Concrete incident, concrete next-action.
- **Specific incident worth remembering but not load-bearing for every turn**: goes in `.claude/ratchets.md` (see [The ratchets log](#the-ratchets-log)). The file is a chronological log; CLAUDE.md is read every turn and stays small.

Add the note in a separate structural-only commit before the bug fix.

### 6. Is it a skill update?

Some failures point to gaps in your project's skill files. Examples — substitute the equivalent skill in your project:

- "I marked a PR ready for review with red CI because no skill said not to." → the PR-prep skill needs a hard rule. (In this plugin: `/merge-pr` covers post-merge watching; you may need a project-specific PR-prep skill on top.)
- "I committed structural and behavioural changes together because no skill said to split them." → the commit-prep skill needs a hard rule. (In this plugin: `/making-git-commits` is the closest equivalent.)
- "I started work on a stale branch because no skill said to rebase first." → the task-start skill needs a step. (In this plugin: `/rebase` covers the rebase mechanic; the project-specific task-start skill, if any, owns the *when*.)

If your project ships its own skills for these workflows, update them. If you only have the ones this plugin ships, the update goes into the plugin skill — open a PR upstream rather than forking locally.

Update in a separate structural-only commit before the bug fix.

### 7. Is it a guardrail update?

If a recurring read-only scan or audit (a periodic linter pass, an architecture-conformance check, a security audit) is skipping the same false-positive category twice in a row, tighten its guardrail rather than continuing to skip. The skip is the signal; tightening is the response. Same shape as a skill update.

### 8. Is the answer genuinely "do nothing harness-side"?

Valid reasons:

- **Network flake**: verify by re-running. If the failure isn't reproducible after 3 reruns and the cause is a known external-service blip, document briefly and move on.
- **Pre-existing on the default branch**: the failing behaviour exists on `origin/<default-branch>` independent of your changes. Verify, don't assume — the verification is the non-negotiable part:
  1. Identify the default branch (e.g. `git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`).
  2. Run the failing test against that branch, not your branch. The cleanest way: create a throwaway worktree on the default branch (`git worktree add /tmp/preexisting-check origin/<default>`), run the test there, then `git worktree remove`. Avoid `git stash; git checkout origin/<default> -- <files>` in your active worktree — it leaves the working tree in a hybrid state and is easy to corrupt.
  3. Cite the test runner's output (exit code, summary line) in the PR description. "It's pre-existing" without quoted output doesn't count.
  4. Pre-existing failures must also have a tracked issue.
- **Work-in-progress code being deleted in this PR**.

In all three cases, write the reasoning into the PR description or task tracker. "Do nothing" requires a paper trail. The verify-then-cite step is what keeps "preexisting" from becoming a catch-all dismissal — sessions across many projects have used it that way without verification, often enough that the gate is non-negotiable.

### 9. Now fix the original bug

After the harness change is in (steps 3-7) or you've documented the no-op (step 8), fix the original failure in a separate behavioural commit. Structural changes always come first.

### 10. Label the PR

Once the PR is open, add a `harness-fix` label so the cumulative effect is queryable:

```bash
LABEL="harness-fix"  # change once at the top if you want a different name
gh label create "$LABEL" --description "PR added a lint, structural test, ratchet entry, or doc note in response to a failure" --force
gh pr edit <pr-number> --add-label "$LABEL"
```

The `--force` on `gh label create` makes it idempotent (so this same block works on every harness-fix PR after the first). The `gh pr edit` call is what actually attaches the label to *this* PR — the create-only call would just leave the label sitting in the repo unused. Both are needed.

## The ratchets log

`.claude/ratchets.md` is an append-only log of incidents the harness has learned from. Bootstrap it the first time this skill fires on a repo:

```markdown
# Ratchets log

A chronological log of incidents that informed the project's automated
checks. New entries go at the top. The `/ratchet-harness` skill reads
this file in step 2 to spot recurring classes of failure.

## YYYY-MM-DD — short title

**Incident**: one sentence describing what failed and how.
**Class**: the *shape* of the failure (not the specific instance).
**Response**: which step(s) of /ratchet-harness applied, and what
specific rule/test/note was added (cite file path or commit SHA).
**Status**: `rule-added` / `note-added` / `not-yet-promoted` / `do-nothing`.
```

**What to write down**:
- The shape of the failure (so future-you can grep for "the same class")
- What you did about it (file path of the rule, line of CLAUDE.md you appended to, commit SHA)
- Status, so step 2's "match found, no rule yet" / "match found, with a rule" branches are decidable

**What NOT to write down**:
- The original bug fix (that's in git history; don't duplicate it)
- Generic best practices (those go in CLAUDE.md / AGENTS.md, where everyone reads them every turn)

The file is a memory aid for *the skill*, not a contributor doc. Keep entries terse — three or four lines per incident is the right scale.

## Hard rules

- Never fix a bug before deciding if a harness rule could have caught it. The order is: reproduce → check ratchets log → harness response → bug fix. Skipping the middle steps is the failure this skill exists to prevent.
- Never call a failure "preexisting" without verifying on the default branch and citing the test runner's output. Pre-existing failures are bugs that need their own tracking issues, not excuses to ignore CI.
- Never write a vague "best practice" doc note. Concrete incident, concrete next-action, ≤2 sentences.
- Always commit harness changes as structural-only, not bundled with the behavioural bug fix.
- Always label the PR. The label is the metric.

## What to keep in your project's CLAUDE.md / AGENTS.md

This skill is the procedure. The project-specific bits — the names of your linter rules, the path to your verification scripts, which skill files exist in your repo, your tracker conventions — belong in your project's docs, not here. When you adapt this skill for a new repo, leave the procedure as-is and let the agent discover the local equivalents from the project's own docs and from `.claude/ratchets.md`.
