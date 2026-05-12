---
name: gc-run
description: Run all repo-health garbage-collection scans in parallel. Dispatches each `gc-*` subvariant in its own sub-agent so the scans run isolated and without polluting each other's context, then reports a per-scan summary count. Use when running a manual repo-health pass; subvariants currently include `gc-stale-todos` and `gc-duplicated-blocks`.
---

# Skill: gc-run

You are the orchestrator for this repo's garbage-collection scans. Your single job is to dispatch each `gc-*` subvariant as its own sub-agent, in parallel, and then report a one-line summary per subvariant. You do not perform the scans yourself — the sub-agents do.

## Trigger

Run on a manual cadence (cron-eligible, weekly is sensible). Not human-invoked at action boundaries.

## Subvariants

Currently shipped:

- **`gc-stale-todos`** — finds `TODO`/`FIXME`/`XXX`/`HACK` comments where `git blame` shows the introducing commit is more than 30 days old.
- **`gc-duplicated-blocks`** — finds blocks of more than 30 lines duplicated across the repo with at least 80% similarity.

If a future subvariant is added to this plugin (named `gc-<something>/SKILL.md`), the orchestrator picks it up automatically.

## Procedure

### 1. Verify the working tree is clean

```bash
git status --porcelain
```

If there are uncommitted changes, stop and tell the user. The scans should run against a clean checkout — uncommitted edits would skew `git blame` ages and leave noise in the duplicated-blocks survey.

### 2. Dispatch each subvariant as a parallel sub-agent

Spawn one sub-agent per subvariant in a single tool-call batch so they run in parallel. Each sub-agent runs the matching skill end-to-end and is responsible for its own filing, summary, and stop conditions.

Brief each sub-agent with:

- The skill name to invoke (e.g. "Run the `gc-stale-todos` skill end-to-end against this repo").
- The repo's project tracker if you can detect it (presence of `.beads/`, `gh` auth, etc.) — otherwise let the sub-agent detect.
- A reminder that the skill is read-only on the codebase and that the sub-agent must not commit, push, or open PRs.

Do **not** brief the sub-agent with extra heuristics or "be careful about X" — the skill files already encode their own discipline. Wrapping them in extra prose dilutes the contract.

### 3. Collect and report

When all sub-agents finish, print one line per subvariant in this shape:

```
=== gc-run summary ===
gc-stale-todos:        filed N issues, skipped M candidates
gc-duplicated-blocks:  filed N issues, skipped M candidates
```

If a sub-agent fell back to a markdown report (no tracker wired up), substitute the report path for the issue count: `gc-stale-todos: wrote gc-findings/stale-todos-<date>.md`.

If a sub-agent failed (errored out, hit a permission prompt, exhausted its budget), print:

```
gc-<name>: FAILED — <one-line reason>
```

…and continue to report the others. One scan failing does not block the rest.

## Output discipline

The orchestrator's job is dispatch and summary, not re-display. The findings are already in the tracker (or a fallback report file); duplicating them in the orchestrator's output wastes context and tempts the user to act on the orchestrator's transcribed copy instead of the canonical tracker entry.

If the user wants to drill into a specific finding, they go to the tracker.

## Hard rules

- Never run the scans yourself. The orchestrator's only job is dispatch + summary. If you find yourself grepping the codebase, stop — that's the sub-agent's job.
- Never modify source files in this session. The orchestrator is as read-only on the codebase as the sub-agents it dispatches.
- Never commit, push, or open PRs.
- If `git status --porcelain` shows uncommitted changes, stop and tell the user before dispatching.
