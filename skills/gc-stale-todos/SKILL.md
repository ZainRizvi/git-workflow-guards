---
name: gc-stale-todos
description: Read-only repo-health scan. Use when running a manual repo-health pass to surface stale tech-debt markers. Finds `TODO`/`FIXME`/`XXX`/`HACK` comments where `git blame` shows the introducing commit is more than 30 days old, then files one tracker issue per finding with the original commit's sha/author/date/subject. Never edits source. Tracker-agnostic.
---

# Skill: gc-stale-todos

You are running as a **garbage-collection agent** for this repo. Your single job in this session is to find stale `TODO` / `FIXME` / `XXX` / `HACK` comments and file one tracker issue per finding, with the original commit context (sha, author, date, subject). You are not fixing anything — you are surfacing findings so a human (or a future agent) can later schedule the work.

## Trigger

Run on a manual cadence (cron-eligible, weekly is sensible) against a clean checkout. Not human-invoked at action boundaries.

## Goal

Find inline-comment markers that have been sitting in the codebase for **more than 30 days** and open one tracker issue per finding with the original commit's context, so a future reader can decide whether the marker is still relevant.

## What counts as a stale marker

A line containing one of `TODO`, `FIXME`, `XXX`, or `HACK` (case-sensitive, as comment text — not as a string literal in test data or fixture content) where `git blame` shows the original commit is **more than 30 days old** relative to today.

A marker is "stale" when:
- It's been in the tree for more than 30 days **without** a follow-up commit modifying or removing it, AND
- It's still describing future work (not historical commentary like `// HACK history: removed in 2024`).

## Where to look

All source files in the repo. Use a comment-aware grep (covering `//`, `/* */`, `#`, `<!-- -->`, `;` comment styles) across the working tree.

## What to skip (guardrails)

Do **not** open issues for markers that fall into these buckets:

1. **Generated code or vendored deps.** Anything under `node_modules/`, `.git/`, `dist/`, `build/`, `.next/`, `target/`, `vendor/`, or files containing `// AUTO-GENERATED` / `// DO NOT EDIT` / `# AUTO-GENERATED` headers. Also skip declarations files (`*.d.ts`).
2. **Strings, not comments.** A line like `expect(text).toBe('TODO: write me')` is data, not a real TODO. Verify the marker is in a comment context (`//`, `/* */`, `<!-- -->`, `#`, `;`) before counting it.
3. **Markers in test fixtures.** Files under `**/__fixtures__/`, `**/fixtures/`, `**/*.fixture.*`. Test data may contain TODO-like strings as part of mock content.
4. **Historical / closed markers.** A comment like `// FIXME (closed 2023): we used to ...` or `// TODO history` is documentation of past intent, not pending work. Skip.
5. **External-dependency markers.** A copy-pasted vendor library or third-party file with the original TODOs intact.
6. **Recent markers (≤30 days old).** Use `git blame -L <line>,<line> --porcelain -- <file>` to read the line's `author-time`. If it's within the last 30 days, skip — the author is still actively iterating. Do not use `git log -1 -- <file>` for this; see workflow step 3 for why.
7. **Broad/categorical markers without a target.** A comment like `// TODO: refactor this someday` with no concrete action is low signal. Only file when the marker names a specific thing to do or fix. If you can't summarize the work in one short sentence, the marker is too vague — skip.
8. **Markers already linked to an issue or ticket.** If the comment includes a tracker reference (e.g. `#42`, `JIRA-123`, `GH-99`, `bd-xxx`), the work is already tracked. Skip.

When in doubt: **don't open the issue**. The point of this scan is to surface debt that has *quietly* slipped past the team's attention. Markers that are actively-tracked, deliberately-left, or trivially-vague are not the target.

## How to score each candidate

For each candidate marker, capture:

- **Age (days):** `today - commit_date`.
- **Marker type:** `TODO` | `FIXME` | `XXX` | `HACK`. (FIXME and HACK are higher priority signals than TODO.)
- **Specificity:** does the comment describe concrete work? (yes/no — if no, skip per guardrail 7)
- **Suggested action:** one of:
  - `do-the-work` — the marker is concrete and the work is small. The issue becomes the work item.
  - `gate-and-monitor` — the marker calls out a known limitation; the right next step is to add a metric or test that fires when the limitation actually bites.
  - `delete-as-stale` — the marker references a system/feature that no longer exists, or describes work that is no longer relevant.

Only file an issue when **age ≥ 30 days** AND the marker is specific (per guardrail 7) AND it isn't already linked to a tracker.

## Filing each issue

This skill is **tracker-agnostic**. The repo's project tracker may be GitHub Issues (`gh issue create`), Linear, Jira, beads (`bd create`), or a plain markdown report. Detect what the project uses (look for `.beads/`, `gh` auth status, a `LINEAR_API_KEY`, etc.) and emit each finding via that tracker.

The **payload shape** is the same regardless of tracker:

- **Title:** `Stale <TYPE>: <one-line summary of what the comment says>` (one short imperative sentence; this is the issue's headline)
- **Body:** the structured block below

Body template:

```markdown
**Location:** `path/to/file.ts:42`

**Marker:** `// TODO: <verbatim comment text>`

**Age:** 187 days  |  **Type:** TODO

**Origin:** commit `abc1234` by Author Name on 2025-10-23 — "Original commit subject"

**What the comment is asking for:** <2–3 sentences describing the work in your own words, having read the surrounding code>

**Suggested action:** do-the-work

**Why this is still relevant (or isn't):** <1 sentence — has the world moved past this marker, or is the work still pending? If no longer relevant, set suggested action to delete-as-stale and explain why.>

_Filed by gc-stale-todos skill._
```

If the tracker supports labels, add `gc` and `stale-todo`. If not, embed them as a `**Labels:** gc, stale-todo` line in the body.

If no tracker is wired up, write the findings to `gc-findings/stale-todos-<YYYY-MM-DD>.md` at the repo root and tell the user where the report landed.

## Workflow

1. **Hunt.** Grep the working tree for the four marker types (`TODO`, `FIXME`, `XXX`, `HACK`). Capture file + line for every hit.
2. **Filter to comments only.** Skip hits inside string literals, test data, fixtures, or generated/vendored directories (per guardrail list).
3. **Age each surviving hit.** Run `git blame -L <line>,<line> --porcelain -- <file>` for each marker. Read the `author-time` (Unix timestamp), the sha, the `author` line, and the `summary` (commit subject) from the porcelain output. Do **not** use `git log -1 -- <file>` for this — it returns the file's most recent commit, which is misleading: a file touched yesterday in an unrelated area would mark every old TODO in it as "recent." `git blame` is line-accurate; `git log` is file-accurate.
4. **Apply guardrails 1–8.** Drop anything that doesn't pass.
5. **Score and rank.** Aim for **3–10 findings total**. If you find more, prioritize by `(age × marker_severity)` where `FIXME`/`HACK` outrank `TODO`/`XXX`. Drop the rest.
6. **File issues.** One per finding via the project's tracker. Print the issue IDs (or report path) as you go.
7. **Stop.** Do not modify any source files. Do not delete any TODO markers — even the ones flagged as `delete-as-stale`. Your output is only the issues and a final summary printed to stdout.

## Final summary

After filing, print:

```
=== gc-stale-todos summary ===
Filed N issues:
  <id-or-path>  <title> (age: D days, type: TODO|FIXME|XXX|HACK)
  ...

Skipped M candidates (reasons):
  <one-line reason per skip, grouped — e.g., "5× recent (≤30 days)", "3× linked to existing issue", "2× too vague">
```

The skip list is itself useful signal — if every run skips the same category, that's a hint to update the guardrails in this skill.

## Hard rules

- Read files (and surrounding code) before claiming what a marker means. Never paraphrase from memory.
- Never modify source files. This skill is read-only on the codebase. Do **not** delete the TODO/FIXME markers, even ones judged stale — that's a separate human decision.
- Restrict yourself to read-only commands (`grep`, `ls`, `cat`, `find`, `git log`, `git blame`, `git show`, `git diff`) plus the tracker's create command. No `git commit`, no `git push`, no writes to the filesystem outside the tracker call (or the fallback markdown report).
- Never open PRs, never commit, never push.
- If a tracker call fails, print the error and continue with the next finding. Do not retry blindly.
