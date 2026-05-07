#!/bin/bash
# Ban gh api for PR/issue comments, suggest gh pr/issue view instead.

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Quick exit: only care about "gh api" commands
[[ "$cmd" == *"gh api"* ]] || exit 0

# Check patterns and suggest alternatives
suggest=""
if [[ "$cmd" =~ gh[[:space:]]+api[[:space:]]+repos/[^/]+/[^/]+/pulls/([0-9]+)/comments ]]; then
  suggest="gh pr view ${BASH_REMATCH[1]} --comments"
elif [[ "$cmd" =~ gh[[:space:]]+api[[:space:]]+repos/[^/]+/[^/]+/pulls/([0-9]+)/reviews ]]; then
  suggest="gh pr view ${BASH_REMATCH[1]} --json reviews"
elif [[ "$cmd" =~ gh[[:space:]]+api[[:space:]]+repos/[^/]+/[^/]+/issues/([0-9]+)/comments ]]; then
  suggest="gh issue view ${BASH_REMATCH[1]} --comments"
elif [[ "$cmd" =~ gh[[:space:]]+api[[:space:]]+repos/[^/]+/[^/]+/deployments ]]; then
  suggest="gh run list"
fi

if [[ -n "$suggest" ]]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Use \`$suggest\` instead of gh api."
  }
}
EOF
fi

exit 0
