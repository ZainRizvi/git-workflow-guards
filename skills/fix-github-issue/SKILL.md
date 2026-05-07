---
name: fix-github-issue
description: Implement a fix for a GitHub issue with iterative code review. Use when given a GitHub issue URL or number to fix. Fetches the issue, implements the fix, runs tests, then uses /review-agent for iterative review until no valid feedback remains.
argument-hint: "<issue-url-or-number>"
---

# Fix GitHub Issue with Iterative Review

Implement a fix for a GitHub issue, ensuring quality through test verification and iterative code review using the `/review-agent` skill.

## Arguments

- `<issue-url-or-number>`: GitHub issue URL (e.g., `https://github.com/owner/repo/issues/123`) or issue number (e.g., `123` or `#123`)

## Phase 1: Fetch and Understand the Issue

1. **Parse the issue reference**:
   - If a full URL: extract owner, repo, and issue number
   - If just a number: use the current repo context

2. **Fetch issue details** using `gh`:
   ```bash
   gh issue view <number> --json title,body,labels,comments
   ```

3. **Analyze the issue**:
   - What is the problem being reported?
   - What is the expected behavior?
   - Are there reproduction steps?
   - Are there any hints about the root cause?

4. **Create a todo list** to track the implementation

## Phase 2: Implement the Fix

1. **Explore the codebase** to understand:
   - Where the bug likely exists
   - Related code and dependencies
   - Existing patterns to follow

2. **Implement the fix**:
   - Follow project conventions (check CLAUDE.md)
   - Keep changes minimal and focused on the issue
   - Add/update tests if appropriate

3. **Verify the fix** addresses the issue:
   - Does it solve the reported problem?
   - Does it handle edge cases mentioned?

## Phase 3: Iterative Review with /review-agent

Invoke the `/review-agent` skill to perform iterative code review:

```
/review-agent
```

The `/review-agent` skill handles:
1. Running tests before review (and between iterations)
2. Launching the review sub-agent
3. Evaluating and implementing valid feedback
4. Iterating until no more valid feedback remains

See `/review-agent` for full details on the review process, including how it handles sub-agent bias.

## Phase 4: Final Summary

After the review loop completes with no remaining valid feedback, provide:

```markdown
## Issue Fix Summary

### Issue
- **Title**: [Issue title]
- **Number**: #[number]
- **Problem**: [Brief description of what was broken]

### Solution
[Description of the fix implemented]

### Files Changed
- `path/to/file.ext`: [What was changed]

### Tests
- [x] All tests passing
- [New tests added, if any]

### Review Iterations
- Iteration 1: X findings implemented
- Iteration 2: X findings implemented
- ...
- Final: No valid feedback remaining

### Ready for PR
[Yes/No - and any notes about remaining concerns]
```

## Common Mistakes

- Implementing a fix without understanding the full issue context
- Implementing reviewer feedback that contradicts project conventions
- Making changes beyond the scope of the issue
