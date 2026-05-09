---
name: refactor
description: Apply universal, language-agnostic refactoring principles to a scope of code — map callers, run tests, then make one named, behavior-preserving transformation per commit, iterating until the smells in scope are addressed. Use when the user asks to refactor, clean up, simplify structure, deduplicate, extract, inline, rename, delete dead code, prune stale comments, or "improve" a file/module without changing behavior. Distilled from the top 30 refactoring skills on skillsmp.com.
argument-hint: "[scope: file/dir path | 'staged' | 'branch']  [smells: long-fn|duplication|dead-code|conditionals|naming|comments|layering|all]"
---

# Disciplined refactoring with universal principles

Make a codebase cleaner without changing what it does. This skill turns a set of universal refactoring principles into a repeatable workflow: pick a smell, make the smallest behavior-preserving transformation, verify with tests, commit, repeat. It is **not** a rewriter or a feature-builder — those need a separate skill and a separate commit.

## When to use

- The user says "refactor", "clean up", "simplify", "deduplicate", "extract", "inline", "rename", "delete dead code", "prune comments", or "improve the structure of" a file/module.
- After implementing a feature, when the user wants a structure pass before opening the PR.
- When a file/function is hard to read and the user wants to make it easier to read without changing behavior.

## When NOT to use

- The user wants behavior changes (a feature, a bug fix, a performance change). Do that separately. Refactoring with behavior changes mixed in is unreviewable.
- Tests are red. Fix tests first; don't refactor on a red bar.
- The code in scope is about to be deleted or rewritten.
- The user is in a production firefight. Refactoring is for calm; firefights need minimal targeted change.

## The Prime Directive

Three rules sit above every transformation. If you can't satisfy all three, stop — you're not refactoring, you're doing something else.

1. **Behavior is preserved.** Inputs, outputs, side effects, public APIs, error semantics — identical before and after.
2. **Tests (and types/lint) are green at the start, and again at the end of every step.** Red bar means stop, revert, diagnose.
3. **Smallest reversible step, then commit.** One named transformation per commit. If something breaks, you revert seconds of work, not days.

## Phase 1 — Determine scope

If the user passed an explicit path or `staged`/`branch`, use it. Otherwise auto-detect:

1. Resolve the repo's default branch:
   ```bash
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
   if [ -z "$DEFAULT_BRANCH" ]; then
     for cand in main master trunk; do
       if git rev-parse --verify "origin/$cand" >/dev/null 2>&1; then
         DEFAULT_BRANCH="$cand"; break
       fi
     done
   fi
   ```
2. `git diff "$DEFAULT_BRANCH"...HEAD --name-only` — if non-empty, scope is the changed files on the branch.
3. Else `git diff --name-only` and `git diff --staged --name-only` — scope is the modified working tree.
4. Else ask the user for an explicit path. Do **not** refactor an entire repository on autopilot.

Cap a single invocation at one cohesive scope: typically one module, one feature area, or the changed files of one branch. If the requested scope is bigger, do it in passes — and tell the user that's what you're doing.

## Phase 2 — Confirm the safety net

Refactoring without a safety net is rewriting. Before you touch anything:

- Detect and run the project's test command (CLAUDE.md / AGENTS.md / package.json / Makefile / pyproject.toml / Cargo.toml). Common forms: `pnpm test`, `npm test`, `pytest`, `go test ./...`, `cargo test`.
- Run the project's lint and type-check too if they exist (`pnpm lint`, `tsc --noEmit`, `mypy`, `ruff`, `clippy`).
- All must pass. If they don't, stop and surface it. Either the user fixes them, or you fix them as a separate commit *before* refactoring begins.
- Confirm coverage of the specific paths in scope. If coverage is thin, write characterization tests first (in their own commit), or stop and ask the user.

For UI/integration-shaped code, prefer end-to-end tests as the regression net; unit tests alone don't catch composition bugs.

## Phase 3 — Map callers and impact

Before any transformation, understand the blast radius of the symbols in scope.

- Grep / AST-search for every call site, import, and reference of the public symbols in scope.
- Tag each caller as in-module, in-tests, or external.
- Note dynamic references that static search misses: string lookups, reflection, dispatch tables, generated code, configuration files, JSDoc/docstring references.
- For symbols with external consumers, mark them as **public API** — those follow the deprecation flow in Principle 17, not the simple-rename flow.

A "compiles and tests pass" signal is **not** proof you found everything. Strings, configs, and on-disk formats slip past type checks.

## Phase 4 — Identify smells, plan transformations, order by risk

Walk the scope and list the smells you actually find. Use the principles below as a checklist, not a script. **Only act on smells you can name and observe** — don't refactor speculatively.

Order the planned transformations by risk and value:

1. **Quick wins first**: dead-code deletion, comment pruning, obvious renames, inlining of single-call passthroughs.
2. **Structural next**: Extract Method, splitting large units, flattening conditionals, deduplication, parameter objects.
3. **Architectural last**: layering, moving behavior, typed boundaries — these are the riskiest and benefit from a clean working set.

For non-trivial scopes (more than ~3 transformations), produce the plan as a checklist and confirm with the user before proceeding. For trivial scopes, just go.

## Phase 5 — The transformation loop

For each planned transformation, run this loop. **One transformation per pass. One pass per commit.**

1. Re-confirm tests/types/lint are green.
2. Apply the single named transformation (see principles below). Smallest possible diff.
3. Run tests/types/lint again.
4. **If green**: commit with a message naming the transformation and the symbol — e.g. `refactor: extract validateOrder() from processOrder`. Move to the next transformation.
5. **If red**: revert the change. Do **not** debug forward into the new state. Either retry with a smaller step, or skip this transformation and note why.

Don't bundle. Don't squash mid-loop. Don't mix in a bug fix you spotted along the way — note it as a TODO for after the refactor.

## Universal principles to apply

These are the transformations to look for. Each is language- and framework-agnostic.

### 1. Map callers and impact before changing anything
Done in Phase 3. Surprises later are paid for here.

### 2. Require a test/type safety net
Done in Phase 2. Re-confirm green at every loop step.

### 3. One transformation per commit
The loop in Phase 5. Atomic, named, revertable.

### 4. Extract Method
**Trigger**: function exceeds ~15-30 lines; cognitive complexity above the project threshold; comment-headed sections; repeated block.
**Action**: extract a coherent block into a function whose name says *what* (not *how*); pass only what it uses; return only what callers need; the original now reads like an outline.
**Watch out**: extracting a one-liner used once adds indirection without insight — the name must remove the need to read the body.

### 5. Split large units into focused subunits
**Trigger**: file/class/component exceeds the project's stable threshold (~300 lines is common); mixes unrelated concerns; violates Single Responsibility.
**Action**: identify seams (distinct sections, entities, lifecycle phases); extract each seam into its own dedicated unit; pass small explicit inputs; keep the parent as orchestrator.
**Watch out**: splitting along the wrong axis produces subunits that need 15 props.

### 6. Eliminate duplication — when it earns its keep
**Trigger**: same logic in 4+ places; bug fixes require parallel edits in N places; same conditional shape across adjacent functions; **two functions doing the same thing under different names**; near-duplicates differing only by a parameterizable bit.
**Action**: extract shared logic; for redundant functions, pick the canonical one (best name, best location, most callers), redirect every caller to it, then delete the loser via Principle 8. Apply the **Rule of Three**: tolerate once, note twice, refactor on the third.
**Watch out**: confirm semantic equivalence before consolidating — two functions can look identical and have different null/timezone/error behavior. Premature DRY costs more than the duplication.

### 7. Inline what doesn't earn its name
**Trigger**: helper has 1 caller and a trivial body; identity passthrough; single-passthrough barrel/re-export; wrapper that adds no value.
**Action**: inline at the call site, unless the helper documents non-obvious intent or belongs to a family of similar helpers (visual symmetry has value).
**Watch out**: respect deliberate naming, public API stability, and helpers that exist precisely to be mocked.

### 8. Delete dead code
**Trigger**: function/class/type/file/export/parameter/branch/feature flag/import has zero remaining consumers — including after a rename or inline elsewhere.
**Action**: confirm zero usage (including dynamic references, configs, generated code) and delete — including its tests. Don't comment out. Don't leave `// TODO: remove`. If it's needed later, it's recoverable from git. Land the deletion as its own commit.
**Watch out**: public API surface goes through Principle 17's deprecation flow instead. Tests that pass *because* the code is gone aren't passing — verify they still cover what they claim to cover.

### 9. Flatten conditional logic
**Trigger**: nesting depth >3; conditional chains >3 cases; mixed boolean-and-data switches; conditions whose meaning isn't obvious at a glance.
**Action**: guard clauses / early returns for edge cases; named predicates instead of multi-clause boolean expressions; lookup/dispatch tables for value-to-result switches; polymorphism when the type drives behavior in multiple places.
**Watch out**: a single switch in one place is fine — don't reach for polymorphism for its own sake.

### 10. Tame parameter lists and primitive obsession
**Trigger**: function takes 4+ parameters; the same group of primitives travels together through multiple functions; raw strings/ints carry domain meaning the type system can't enforce.
**Action**: parameter object when 2+ params always travel together; small domain types (`Money`, `EmailAddress`, `OrderId`) for primitives carrying invariants; remove unused or recoverable parameters.
**Watch out**: wrapping every primitive yields ceremony with no payoff.

### 11. Name to reveal intent; let names replace comments
**Trigger**: variables named `x`, `temp`, `data`; functions named after their implementation rather than their purpose; comments restating the code below.
**Action**: rename to say what it means in the domain; promote comment text into a function name (extract block, use comment as name); reserve real comments for *why*.
**Watch out**: renaming without checking string references, docs, and tests.

### 12. Delete unnecessary comments and comment rot
**Trigger**: comments restating what the next line does (`// increment counter`); comments narrating history ("now uses X instead of Y", "previously called `oldName`", "refactored from class-based", "removed the cache"); `// TODO: remove`; commented-out code blocks; "Used by X" / "added for the Y flow" pointers that rot when callers change; redundant block headers that section code the IDE already structures.
**Action**: delete what-comments — fix naming instead (Principle 11). Delete history comments — git log is the source of truth for "what changed"; if the rationale is load-bearing, rewrite the comment in the present tense as *why* the current design exists, not what it replaced. Delete commented-out code (recover from git if needed). Convert old `TODO`/`FIXME` markers to tracked issues. Keep comments that explain *why*: hidden constraints, subtle invariants, workarounds, surprising behavior.
**Watch out**: don't delete a comment that looks redundant but encodes a non-obvious constraint (timezone assumption, off-by-one rationale, regulatory citation) — read carefully before deleting. Stale docs are *worse* than no docs because they misdirect with authority.

### 13. Move behavior to where its data lives
**Trigger**: Feature Envy (a method reaches into another class's fields more than its own); recurring `a.getB().getC().doX()` chains; Shotgun Surgery (one logical change forces edits in many classes); god classes mixing entities.
**Action**: move methods/fields to the class whose state they truly use; introduce a method on the intermediate object instead of reaching through it (Law of Demeter); split god classes; inline anaemic ones.
**Watch out**: don't make speculative moves — wait for the second consumer to demand the new home.

### 14. Separate orchestration from implementation
**Trigger**: UI component issues raw API calls; service writes SQL inline; controller does validation, persistence, and rendering in one body.
**Action**: push side effects into dedicated services/adapters; keep UI thin (state binding, dispatch, render); inject dependencies explicitly.
**Watch out**: anaemic layers added just to have layers.

### 15. Route raw access through a single typed boundary
**Trigger**: multiple call sites do `obj.get('key') as Type` or `data['field']`, each duplicating shape assumptions.
**Action**: one parser/reader at the boundary that validates and returns a typed (often discriminated-union) value; all internal callers consume the typed result.
**Watch out**: helpers that re-cast to keep "flexibility" reintroduce the problem one layer deeper.

### 16. Don't mix refactoring with feature work or bug fixes
Wear one hat at a time. If you spot a bug mid-extract, note it and finish the refactor first — or revert the refactor, fix the bug, commit, then resume the refactor.

### 17. Preserve public APIs; deprecate before deleting
**Trigger**: renaming/replacing/removing a public function, class, option, hook, CSS class, or file path that other code (including external consumers) depends on.
**Action**: add the new surface alongside the old; migrate internal callers to the new surface; mark the old deprecated; only remove after the deprecation window. Watch out for default values, on-disk formats, and CSS class names — they leak through DOM and storage even when type checks pass.

### 18. Sweep for stragglers after non-trivial refactors
After inlining, renaming, extracting, or moving: grep for the old symbol/path/comment language; update or delete JSDoc/docstrings/READMEs referencing the old behavior; flatten now-trivial directories. Pair with Principle 8 to delete what's now unused, and Principle 12 to prune any rot-comments the move introduced. Land the sweep as its own commit.

### 19. Don't over-engineer
The cost of a wrong abstraction exceeds the cost of duplication. Extract only when the abstraction pays for itself: 5+ lines, 4+ uses, non-obvious logic, or different files where local context isn't shared. When two approaches both work, pick the one a new reader can understand without leaving the file.

### 20. Respect existing conventions
Mirror the project's directory structure, naming, export style, and import patterns. The surrounding code is the strongest specification you have. Don't introduce a "better" structure in one corner that diverges from the rest.

## Phase 6 — Sweep and report

After the loop converges:

1. **Straggler sweep** (Principle 18): grep for old symbols, stale comments, orphan docs, now-trivial directories. Commit separately.
2. **Final green check**: tests, types, lint all pass.
3. **Report** to the user with a structured summary:

```markdown
## Refactor summary

### Scope
- Files touched: <list>
- Commits: <N>

### Transformations applied
- <commit-msg> [<file:line>]
- ...

### Smells noted but not addressed
- <smell> at <file:line> — <why deferred> (out of scope / risky / public API / needs user input)

### Final state
- Tests: passing
- Lint/types: passing
- Behavior: unchanged (verified via <test-suite-name>)
```

## Important guardrails

- **Don't expand scope.** If you find smells outside the requested scope, list them as deferred TODOs in the report — don't sweep them in.
- **Don't bundle.** One transformation per commit. Reviewers can verify only one change at a time.
- **Don't refactor speculatively.** No "while we're here" cleanups for code that's about to be deleted or rewritten.
- **Don't over-engineer.** The Rule of Three exists for a reason.
- **Don't add new comments while pruning old ones.** When in doubt, no comment is better than a wrong one — names and types should carry the load (Principle 11).
- **Stop and ask** when business logic is unclear, public APIs are at stake, semantic equivalence between candidates is uncertain, or coverage is thin. The cheapest mistake is the one you didn't make.
- **Cap the loop.** If you've made 10 commits in this invocation, pause, summarize, and check in with the user before continuing.

## Quick reference

```bash
# Default — refactor the current branch's changed files
/refactor

# Specific path
/refactor src/orders/

# Just the staged hunk
/refactor staged

# Focus on specific smells
/refactor src/orders/ duplication dead-code comments

# After implementing a feature, before opening a PR
/refactor branch
```

## Provenance

The principles in this skill are distilled from the top 30 "refactor" Agent Skills on [skillsmp.com](https://skillsmp.com/search?q=refactor) (ranked by GitHub stars at extraction time), filtered to those that recur across multiple skills and apply regardless of language, framework, or domain. The full extraction (with source references and per-principle "seen in" counts) lives at `~/code/skill-refactor/PRINCIPLES.md`.
