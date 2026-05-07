#!/bin/bash
# Hook to simplify "git push -u origin <branch>" to "git push" when pushing current branch
#
# If Claude tries to run "git push -u origin <branch>" where <branch> is the current branch,
# deny and suggest using just "git push" instead (which is auto-allowed).

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Check if this is a "git push -u origin <branch>" command
if [[ "$cmd" =~ ^git[[:space:]]+push[[:space:]]+-u[[:space:]]+origin[[:space:]]+([^[:space:]]+)([[:space:]]|$) ]]; then
  push_branch="${BASH_REMATCH[1]}"

  # Get current branch
  current_branch=$(git branch --show-current 2>/dev/null)

  # If pushing current branch, suggest simpler command
  if [[ -n "$current_branch" && "$push_branch" == "$current_branch" ]]; then
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Use just `git push` instead - it will push the current branch and set upstream automatically."
  }
}
EOF
    exit 0
  fi
fi

# Not a matching command, passthrough
exit 0
