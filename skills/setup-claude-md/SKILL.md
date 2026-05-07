---
name: setup-claude-md
description: ALWAYS load this skill when creating or modifying any CLAUDE.md file. Ensures proper structure, content, and core development principles.
---

# Setup CLAUDE.md

Update a repository's CLAUDE.md files with proper structure, relevant content, and core development principles.

## What Belongs in CLAUDE.md

Each CLAUDE.md should contain only information relevant to every session that touches that folder:

**Include:**
- Build, test, and lint commands with exact syntax
- Key directories and their purposes
- Project gotchas and warnings
- Things Claude has gotten wrong before (feedback loop, scoped to relevant directory)

**Exclude:**
- One-off instructions
- Extensive documentation
- Information only relevant to specific tasks

## Structure Guidelines

**Opening:** One-line project description (e.g., "Next.js e-commerce app with Stripe integration")

**Commands:** Scannable format with exact syntax

**Placement:** Commands are sometimes better placed in subfolders if that's where the work is being done

## Root CLAUDE.md Required Sections

The root-level CLAUDE.md must define these core development principles:

### TDD Cycle

Follow Red → Green → Refactor:
1. Write the simplest failing test first
2. Implement minimum code to make it pass
3. Refactor only after tests pass
4. Run all tests (except long-running) after each change

For defects: Write an API-level failing test first, then the smallest test that reproduces the problem, then fix.

### Tidy First (Structural vs Behavioral Changes)

All changes fall into two types:
1. **Structural**: Rearranging code without changing behavior (renaming, extracting methods, moving code)
2. **Behavioral**: Adding or modifying functionality

Rules:
- Never mix structural and behavioral changes in the same commit
- Refactoring and implementation are always distinct steps with distinct commits
- When both are needed, make structural changes first
- Validate structural changes don't alter behavior by running tests before and after

### Commit Discipline

Only commit when:
1. All tests are passing
2. All compiler/linter warnings are resolved
3. The change represents a single logical unit of work

Commit messages must clearly state whether the commit contains structural or behavioral changes.

### Code Organization

**Domain-based structure:** Organize code by domain, with all code for a single domain colocated in a single folder. This maximizes context availability for LLMs working in that area.

**Colocated tests:** Tests live alongside the code they test, not in a separate `tests/` directory tree.

### Code Design

**Dependency injection:** Use dependency injection patterns for better testability. Dependencies should be passed in, not instantiated internally.

## Execution Steps

1. **Find all CLAUDE.md files** in the repository
2. **Check root CLAUDE.md** for required sections (TDD, Tidy First, Commit Discipline)
3. **Add missing sections** to root CLAUDE.md
4. **Review subfolder CLAUDE.md files** for relevance and proper scoping
5. **Remove cruft** - one-off instructions, excessive documentation
6. **Add missing essentials** - build/test commands, key directories, known gotchas

## Example Root CLAUDE.md Structure

```markdown
# Project Name

One-line description of what this project does.

## Commands

- `npm test` - Run tests
- `npm run build` - Build for production
- `npm run lint` - Run linter

## Key Directories

- `src/` - Application source code
- `tests/` - Test files
- `scripts/` - Build and utility scripts

## Development Principles

### TDD Cycle

Red → Green → Refactor. Write the simplest failing test, implement minimum code to pass, refactor only after tests pass. Run all tests after each change.

For defects: API-level failing test first, then smallest reproducing test, then fix.

### Tidy First

Separate structural changes (refactoring) from behavioral changes (features/fixes). Never mix in the same commit. Structural changes come first when both are needed.

### Commit Discipline

Only commit when all tests pass and warnings are resolved. Each commit is one logical unit. Label commits as structural or behavioral.

### Code Organization

- Organize by domain: all code for a single domain in one folder (maximizes LLM context)
- Colocate tests with the code they test

### Code Design

- Use dependency injection for testability

## Gotchas

- [Project-specific warnings and things Claude has gotten wrong]
```
