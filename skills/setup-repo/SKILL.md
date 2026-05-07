---
name: setup-repo
description: Set up a repo with the standard Claude Code configuration (CLAUDE.md, lefthook, ratchet-the-harness ratchet, .claude/settings.json with this plugin's hooks/skills enabled). Idempotent — safe to run on repos that are partially set up; only adds what's missing.
---

# Setup Repo

Apply the standard Claude Code repo configuration. Safe to run multiple times — checks what's already present and only adds the delta.

## Steps

### 1. Read the checklist

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup-repo/checklist.md` for the canonical list of things every repo should have.

### 2. Check and apply each item idempotently

For each item in the checklist:

1. **Check if it already exists and matches** — read the current state of the file or config.
2. **If missing: add it** — create the file or insert the config.
3. **If present but outdated: update it** — merge in any new fields, don't clobber customisations.
4. **If already correct: skip** — do nothing.

### 3. Invoke the other setup skills

After applying checklist items, invoke these skills in order — each is also idempotent:

- `/setup-claude-md` — ensures CLAUDE.md has TDD, Tidy First, Commit Discipline, Code Organisation, Code Design sections.
- `/setup-lefthook` — configures lefthook git hooks for the repo's language/toolchain.

### 4. Report

Tell the user what was added, what was updated, and what was already correct.

## Idempotency Rules

- **`.claude/settings.json`**: If the file exists, **merge** rather than replace. Add the marketplace + plugin entry only if not already present. Add hook entries only if no equivalent is already configured. Preserve all existing settings.
- **`.claude/ratchets.md`**: Create with the standard header only if missing. Never overwrite an existing log.
- **CLAUDE.md**: Defer entirely to `/setup-claude-md` — it handles its own idempotency.
- **lefthook**: Defer entirely to `/setup-lefthook` — it handles its own idempotency.
