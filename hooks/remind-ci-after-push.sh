#!/bin/bash
# Remind Claude to wait for CI results after git push

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Check for git push (but not --help or similar)
if [[ "$cmd" =~ ^git\ push ]]; then
  cat <<'EOF'
{
  "systemMessage": "IMPORTANT: You just pushed changes. Poll CI with `gh run watch` until all checks complete. Do NOT assume your changes work until CI is green. Do NOT accept any failures as pre-existing conditions - if CI fails, fix it."
}
EOF
fi

exit 0
