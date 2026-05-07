---
name: review-changes
description: Multi-agent code review of recent changes — launches up to six specialised reviewer sub-agents in parallel (general code review, comments, tests, error handling, type design, simplification), aggregates their findings, implements valid feedback, and iterates until no agent returns valid findings. Use after writing a non-trivial chunk of code, before committing, before opening a PR, or whenever you want a deeper review than a single-agent pass provides.
argument-hint: "[aspects: code|comments|tests|errors|types|simplify|all]  [parallel|sequential]  [scope: files or 'staged'|'branch']"
---

# Multi-agent code review with iterative implementation

Run a deep review of recent changes using up to six specialised sub-agents, aggregate their findings, implement everything with positive impact, and iterate until the agents return nothing of value.

This skill is the merge of two patterns:

- **Parallel specialist agents** — each agent owns one review dimension and reads the same diff with that lens. Specialists catch what a single generalist misses, and they run concurrently so wall-clock cost stays close to one agent's runtime.
- **Iterate-to-clean** — sub-agents tend to return a partial list per invocation, even when more issues exist. The skill keeps re-launching agents (with the *updated* diff each round) until they explicitly return empty.

## When to use

- After writing a non-trivial chunk of code and before committing.
- Before opening a PR (catch issues before reviewers do).
- Before pushing changes to a long-lived branch.
- When a single-agent review feels shallow and you want adversarial breadth.

## When NOT to use

- For trivial changes (typo fix, single-line tweak) — the parallel-agent overhead isn't worth it.
- When you've just run this skill and the diff hasn't materially changed.
- When the test suite is broken — fix tests first; the reviewers should only see working code.

## Phase 1 — Determine scope

If the user passed explicit files or a scope argument, use that. Otherwise auto-detect:

1. `git diff main...HEAD` — if non-empty, you're on a feature branch; review the branch diff.
2. Else `git diff` and `git diff --staged` — review uncommitted/staged work.
3. Else `git show HEAD` — review the most recent commit.

Capture the file list (and the diff text) for the agents.

## Phase 2 — Run tests first

Before any review, ensure the test suite passes. The agents must only review working code; reviewing on top of test failures wastes cycles and produces noise.

Detect the project's test command from CLAUDE.md / AGENTS.md / package.json / Makefile / pyproject.toml. Common forms:

```bash
pnpm test
npm test
pytest
go test ./...
cargo test
```

If tests fail, fix the failures first and re-run. Do not start the review with red tests.

If the project has no test suite, note it and continue — the reviewers can still inspect static quality.

## Phase 3 — Pick which agents to launch

Default is **all-applicable in parallel**. Filter by what the diff actually contains:

| Agent | Run when |
|---|---|
| `code-reviewer` | Always (general bug/quality/CLAUDE.md compliance) |
| `comment-analyzer` | Comment or doc-string lines added/changed |
| `test-analyzer` | Test files added or production code added without matching tests |
| `silent-failure-hunter` | Try/catch, error callbacks, fallback logic, optional-chaining patterns added |
| `type-design-analyzer` | New types/classes/interfaces/enums introduced |
| `code-simplifier` | Run *after* the loop converges (polish pass — see Phase 6) |

If the user passed `aspects=...`, restrict to those agents only.

## Phase 4 — Launch agents in parallel

Issue all selected agent invocations in **a single message with multiple Task tool calls** so they run concurrently. Each agent gets:

- The list of changed files
- The diff (or instructions to fetch it via `git diff`)
- A pointer to CLAUDE.md / AGENTS.md so they can pick up project conventions
- Any user-supplied focus areas

Do not run them sequentially unless the user explicitly asked for `sequential` or you have fewer than two applicable agents.

If the user asked for a single aspect, just launch that one agent.

## Phase 5 — Aggregate, evaluate, implement

Collect every finding from every agent. For each one, judge:

| Impact | Description |
|---|---|
| **High** | Bugs, security issues, data-loss risk, major performance regressions, silent failures |
| **Medium** | Code-quality issues that affect maintainability, missing important tests, comment rot that misleads future maintainers |
| **Low** | Minor style, small clarity wins, nitpicks |
| **None** | Doesn't apply, is incorrect, contradicts CLAUDE.md, or would make the code worse |

| Risk (for items you'll implement) | Description |
|---|---|
| **Low** | Safe refactors, obvious fixes, well-tested areas |
| **Medium** | Touches business logic, needs careful testing |
| **High** | Core infrastructure, security-sensitive, complex state |

**Implement every finding with positive impact (High, Medium, or Low).** Document what you changed and why.

When two agents flag the same issue, count it once. When two agents disagree (e.g. simplifier wants extraction, reviewer wants inlining), explain your choice in the summary rather than picking silently.

**Trust your judgment over the agents' suggestions** when they conflict with the project's CLAUDE.md, established patterns, or the explicit scope of the change. If an agent suggests refactoring code outside the diff, defer it to a future TODO unless it directly enables the current change.

## Phase 6 — Iterate until clean

Sub-agents are biased toward returning a *limited* set of findings per pass, even when more issues remain. The loop is the value of this skill:

1. Re-run tests after implementing feedback.
2. Re-launch the same agent set against the *updated* diff.
3. Evaluate the new findings with the same impact rubric.
4. Implement everything with positive impact.
5. Repeat.

**Stop when every agent returns no findings with positive impact.** Not when *you* think they should be done — agents can surface new issues each iteration as the diff evolves.

After the loop converges, run `code-simplifier` once for a polish pass — it operates best on stabilised code.

## Phase 7 — Report

Output a structured summary the user can scan in 10 seconds:

```markdown
## Review summary

### Scope
- Files: <list>
- Iterations: <N>

### Implemented
**High impact (X)**
- <agent>: <finding> → <change> [<file:line>] (Risk: Low/Med/High)
**Medium impact (X)**
- <agent>: <finding> → <change> [<file:line>] (Risk: Low/Med/High)
**Low impact (X)**
- <agent>: <finding> → <change> [<file:line>] (Risk: Low/Med/High)

### Rejected (None impact)
- <agent>: <finding> → <reason for rejection>

### Out of scope (deferred TODOs)
- <finding> → <why deferred> [proposed follow-up]

### Final state
- Tests: passing
- Iterations to clean: <N>
- Confidence: <one-line summary>
```

## Important guardrails

- **Don't expand scope.** The agents will sometimes find legitimate issues in code you didn't change. File those as TODOs; don't sweep them into this PR.
- **Don't accept agent suggestions that contradict CLAUDE.md.** The agents read CLAUDE.md but they can still misread it. If a suggestion would violate a stated rule, reject it with rationale.
- **Don't silence agents you don't like.** If an agent keeps flagging the same thing, the right move is either (a) implement it or (b) document why it's not applicable in the rejected list — not (c) drop the agent from future runs.
- **The exception:** if a PR description makes an explicit consistency claim ("response shape now matches GET/list"), verify that claim field-by-field. A pre-existing deviation becomes in-scope the moment the PR claims to fix it — "pre-existing" stops being a valid filter.
- **Don't loop forever.** If after three iterations no new positive-impact findings appear, the diff is clean. Report and stop.

## Quick reference

```bash
# Default — all applicable agents, parallel, auto-scope
/review-changes

# Specific aspects only
/review-changes tests errors

# Sequential (rare — slower, but easier to follow live)
/review-changes all sequential

# Explicit scope
/review-changes path/to/dir/

# Just simplification (after a clean review)
/review-changes simplify
```
