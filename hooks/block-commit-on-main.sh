#!/bin/bash
# Block `git commit` (any variant, including --amend) when the current
# branch is main/master/trunk. All work happens on topic branches in
# dedicated worktrees; main is updated by merging PRs, never by direct
# commits.
#
# Emergency override: set CLAUDE_ALLOW_MAIN_WORK=1 (preferred) or the
# legacy CLAUDE_ALLOW_MAIN_COMMIT=1 (kept for backwards compat) in the
# command's environment for the rare legitimate direct-commit case
# (e.g. CI is broken and the fix is trivial). Use sparingly; this is a
# footgun. The same alias silences the warn-edits-on-main-or-root hook.

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

[[ -z "$cmd" ]] && exit 0

# Skip on Claude Code for the web — there are no worktrees in that
# environment, so the main-branch guard is meaningless and only produces
# false positives.
[[ "$CLAUDE_CODE_REMOTE" == "true" ]] && exit 0

# Honour explicit override (new name preferred, old name still accepted).
[[ "$CLAUDE_ALLOW_MAIN_WORK" == "1" ]] && exit 0
[[ "$CLAUDE_ALLOW_MAIN_COMMIT" == "1" ]] && exit 0

# Only inspect the FIRST segment of a compound command.
first_segment="${cmd%%&&*}"
first_segment="${first_segment%%;*}"
first_segment="${first_segment%%|*}"

# Match git invocations even when interleaved with global flags
# (`git -c key=val commit`, `git --git-dir=... commit`).
git_prefix='^[[:space:]]*git([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+))*[[:space:]]+'

[[ "$first_segment" =~ ${git_prefix}commit([[:space:]]|$) ]] || exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0

case "$branch" in
  main|master|trunk) ;;
  *) exit 0 ;;
esac

# Use jq for JSON encoding so the deny payload stays well-formed regardless
# of what `$branch` resolves to (defense in depth — currently it's filtered
# to main/master/trunk, but cheap insurance against future widening).
reason="BLOCKED: You are about to commit directly to '$branch'. All work goes through PRs from topic branches in dedicated worktrees.

Create a worktree for this work:
  wt switch --create <topic-name>

Note: PreToolUse hooks cannot change Claude's CWD. After wt prints the new worktree path, you must \`cd\` into it before retrying the commit.

To migrate your uncommitted edits, pick based on repo activity. Run \`git worktree list\` to gauge — many active worktrees / parallel agents = pick copy; quiet repo = stash is fine:

  Option A — git stash (simpler, safe in quiet repos):
    git stash push -m 'migrate to <topic>' -- <files>
    cd <new-worktree-path> && git stash pop

  Option B — copy + clean (safer when other sessions might also be stashing):
    cp <files> <new-worktree-path>/<files>
    git restore <files-you-copied>
    git clean -nd   # dry-run; drop -n to delete untracked files

Finally, stage and commit from inside the new worktree.

Emergency override (use sparingly; e.g. CI is broken and the fix is trivial):
  CLAUDE_ALLOW_MAIN_WORK=1 git commit -m '...'"

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'

exit 0
