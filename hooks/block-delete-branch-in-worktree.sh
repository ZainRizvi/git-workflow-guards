#!/bin/bash
# Strip --delete-branch from "gh pr merge" when running in a git worktree.
# Deleting the branch would break the worktree checkout.

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Only care about gh pr merge with --delete-branch
[[ "$cmd" == *"gh pr merge"* && "$cmd" == *"--delete-branch"* ]] || exit 0

# Check if we're in a worktree (git-common-dir != git-dir)
common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
git_dir=$(git rev-parse --git-dir 2>/dev/null)
[[ -n "$common_dir" && "$common_dir" != "$git_dir" ]] || exit 0

# Strip --delete-branch and clean up whitespace
new_cmd=$(echo "$cmd" | sed 's/--delete-branch//g' | sed 's/  */ /g; s/^ *//; s/ *$//')

# Use jq for JSON encoding so a command containing quotes, backslashes, or
# newlines (e.g. a commit message body inline-quoted into the gh command)
# can't malform the rewrite payload.
jq -n --arg cmd "$new_cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { command: $cmd },
    additionalContext: "Removed --delete-branch because you are in a worktree. Deleting the branch would break this worktree. Let the worktree manager handle branch cleanup."
  }
}'

exit 0
