---
name: ratchet-retro
description: Periodic retrospective scan across recent Claude session transcripts in this repo (and its worktrees) for recurring failure patterns. For each pattern surfaced, runs the /ratchet-harness procedure to add a guard. Use proactively on a schedule (weekly is a good cadence) or after any stretch of dense agent work, not in response to a single failure — that's what /ratchet-harness alone is for.
argument-hint: "[since: '7 days ago' | '24 hours ago' | <ISO date>]  [--dry-run]"
---

# Skill: ratchet-retro

A periodic retrospective. Scan recent Claude session transcripts for this repo (and its worktrees) for *recurring* failure patterns the project's automated checks didn't catch, then ratchet up the harness against each one. This is the proactive, batched version of `/ratchet-harness`: instead of reacting to one failure at a time, it surfaces classes of failure across many sessions and prevents the next instance.

This skill is the operationalisation of an exhaustive practice that's worth running on a cadence:

> *"Look through all Claude conversations / session history for this repo and all its worktrees, spanning the past week. Look for: issues the human had to steer the LLM on, and problems the LLM ran into that required a lot of debugging to discover the right way to do a thing. For each, run /ratchet-harness to improve future iterations."*

## When to use

- **On a schedule** — weekly is a sensible default. Long enough to accumulate signal, short enough that the harness is still a credible response to fresh patterns.
- **After a stretch of dense agent work** — a feature push that involved many sessions, an autonomous loop run, or a multi-day refactor.
- **When the same kind of correction keeps coming up** — if you've personally steered the agent past the same mistake three times this week, run this skill rather than ratchet-fixing the third instance ad-hoc.

**When NOT to use:**

- Responding to a single failure — that's `/ratchet-harness` alone.
- After a one-off session with no broader repo context (nothing to compare against).
- More frequently than every few days — you'll see noise instead of patterns.

## Search space

The skill scans:

1. **Claude session transcripts** for this project. They live under `~/.claude/projects/<project-slug>/*.jsonl`, where `<project-slug>` is the project's working-directory path with `/` replaced by `-`. Example: `/Users/zain/code/book-analyzer-v4` → `~/.claude/projects/-Users-zain-code-book-analyzer-v4/`.
2. **Sibling worktree transcripts**. Each worktree gets its own session directory under the same `~/.claude/projects/` root. Find them by listing `git worktree list --porcelain` and translating each path.
3. **Subagent transcripts** for those sessions, located under `~/.claude/projects/<slug>/<session-id>/subagents/agent-<id>.jsonl`. Subagent loops often contain the most concentrated correction signal.

Filter by mtime against the `since` argument (default: 7 days). Don't read transcripts older than the cutoff — they bloat the analysis without adding signal.

If `~/.claude/projects/<slug>/` doesn't exist (the project hasn't been used through Claude Code, or the user is on a fresh machine), surface that and stop. There's nothing to retro.

## Procedure

### 1. Resolve the search space

```bash
PROJECT_DIR="$(git rev-parse --show-toplevel)"
SLUG="$(echo "$PROJECT_DIR" | tr / -)"
TRANSCRIPT_ROOT="$HOME/.claude/projects/$SLUG"
SINCE="${SINCE:-7 days ago}"

# Main checkout transcripts:
find "$TRANSCRIPT_ROOT" -maxdepth 1 -name '*.jsonl' -newermt "$SINCE"

# Sibling worktree transcripts:
git worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print}' \
  | while read -r wt; do
      [[ "$wt" == "$PROJECT_DIR" ]] && continue
      wt_slug=$(echo "$wt" | tr / -)
      find "$HOME/.claude/projects/$wt_slug" -maxdepth 1 -name '*.jsonl' -newermt "$SINCE" 2>/dev/null
    done
```

Collect the file list. Note total line count and approximate session count up front; if the corpus is enormous (≫ 100 sessions), narrow the time window before you start reading — reading every line of every session is not the goal.

### 2. Extract correction signal

For each session transcript, extract two kinds of turn:

- **Steering turns** — user messages that correct, redirect, or override the agent's prior action. Phrases to grep for: `no don't`, `stop`, `that's wrong`, `you should have`, `actually`, `revert`, `back out`, `not that`, `instead`, plus capitalised exclamations of frustration. False positives are fine; a noisy initial filter is the right shape.
- **Stuck-loop turns** — sequences where the agent repeated a failing action 3+ times before resolving. Look for: same tool call shape with similar args, same error message, "let me try again" / "let me try a different approach" within a few turns of each other.

For each match, capture: timestamp, session id, the user message (or the agent's stuck loop), and the surrounding ~5 turns of context. Don't pull the whole session into your reasoning context — pull only what looks like signal.

### 3. Cluster into patterns

A *pattern* is a class of failure, not an instance. Cluster the captured signal by shape, not by literal text:

- "Agent ran X despite the brief saying not to" — count instances across sessions.
- "Agent dismissed CI failures as preexisting without verifying" — count.
- "Agent treated 'no matching files' as success" — count.
- "Agent edited on main without realising" — count.

For each cluster, record: short title, symptom, frequency (how many sessions / how many turns), and example timestamps.

Discard clusters with fewer than 2 instances unless the single instance was a high-impact failure (data loss, prod incident). The "recurring" part of "recurring pattern" is load-bearing — a one-off goes through plain `/ratchet-harness`, not through retro.

### 4. For each pattern, run the /ratchet-harness procedure

Hand each surfaced pattern off to `/ratchet-harness` (steps 3-7 of that skill — you've already reproduced and analysed via the transcript scan, so steps 1-2 of `/ratchet-harness` are satisfied). Decide per pattern:

- Lint rule? → add it.
- Structural test? → add it.
- Project-doc note? → add it (and consider a `.claude/ratchets.md` entry if not load-bearing for every turn).
- Skill update? → update the skill.
- Guardrail update? → tighten it.
- Genuine "do nothing" (single high-impact incident, already-mitigated, etc.)? → write the rationale into the retro report.

Each ratchet response goes in its own structural-only commit, per `/ratchet-harness` discipline.

### 5. Bundle the retro into one PR

Open a single PR titled e.g. "ratchet-retro: N patterns from <since> retro" with each pattern's response as a separate commit. The PR description should summarise: pattern title, frequency, response. The format of [the past-week-audit commit message used by this project's authors](#example) is a good template.

If `--dry-run` was passed, skip step 5 and instead write the retro report to stdout. The point of dry-run is to surface candidate patterns for human review before committing to ratchet responses.

### 6. Label the PR

Add the `harness-fix` label (or whatever the equivalent is for your project) so the cumulative effect is queryable alongside reactive ratchets:

```bash
gh label create harness-fix --description "PR added a ratchet in response to a failure" --force
gh pr edit <pr-number> --add-label harness-fix
```

## Example

A worked example of a retro the user previously ran on this style of repo (week of work, `--since '7 days ago'`):

| Pattern | Frequency | Response |
|---|---|---|
| Agent ran `gh pr merge` despite brief saying "do not merge" | 2 sessions | New `warn-on-pr-merge` PreToolUse hook + skill rule that brief overrides terse follow-ups |
| Agent treated `lefthook (skip) no matching push files` as a green signal and pushed from `main` | 30+ sessions | `lefthook.yml` `not-from-main` gate (no glob, always runs) + `scripts/check-push-not-from-main.sh` |
| Agent dismissed CI failures as "preexisting" without verifying on default branch | 35+ instances | `scripts/verify-preexisting.sh` (PASS-on-main / FAIL-on-main / NO-MATCH); `/push` and `/ratchet-harness` now require citing the script's stdout |
| Agent hand-waved "I'll get notified when CI finishes" without actually scheduling anything | 2-3 sessions | `/land` and `/push` updated: must use `gh pr checks --watch` or schedule a wakeup |
| Single-instance changes missed sibling files (one logo PNG replaced, design-folder copies missed) | 2 sessions | Generalised "Bug-Finding Discipline" → "Change-Finding Discipline" in CLAUDE.md — same class-then-grep treatment for any change |

That retro produced 5 commits across 4 ratchet responses (one pattern was a CLAUDE.md-note-only response). Each commit was structural-only. The PR carried the `harness-fix` label.

## Hard rules

- Only ratchet against *recurring* patterns. Single instances (especially where the agent self-corrected within the session) belong in `/ratchet-harness`, not here.
- Never act on a pattern without quoting concrete evidence — at least two timestamps + the user's correction text or the agent's stuck-loop excerpt — in the PR description. "I noticed the agent…" without quotes doesn't survive scrutiny.
- Each pattern's ratchet response gets its own structural-only commit. Don't bundle two ratchets in one commit even if they look similar.
- If `--dry-run` produces zero high-confidence patterns, that's a valid outcome. Report and stop. The harness has converged for this window.
- Read the transcripts; don't summarise from memory. Memory of "I think the agent kept doing X" is the wrong evidence basis — `~/.claude/projects/<slug>/*.jsonl` is the source of truth.

## See also

- `/ratchet-harness` — the per-incident version of this skill. `/ratchet-retro` calls into it for each pattern it surfaces.
- `.claude/ratchets.md` (if your project keeps one) — the chronological log of incidents the harness has already acted on. A retro should cross-check against it before declaring a pattern "new."
