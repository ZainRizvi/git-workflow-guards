#!/bin/bash
# Block git push --no-verify unless --bypass flag is included

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Check for git push with --no-verify
if [[ "$cmd" =~ ^git\ push && "$cmd" =~ --no-verify ]]; then
  # Allow if --bypass flag is present
  [[ "$cmd" =~ --bypass ]] && exit 0

  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: git push --no-verify is not allowed. NEVER use --no-verify to skip local failures. No failure is 'out of scope' or 'pre-existing' - fix all local issues before pushing. If you must bypass (e.g., testing something impossible to verify locally, or human explicitly instructed), add --bypass flag to the command."
  }
}
EOF
  exit 0
fi

exit 0
