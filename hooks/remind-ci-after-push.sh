#!/bin/bash
# Remind Claude to wait for CI results after git push

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Match `git push` anchored at the start of any command segment (line start
# or after `&&`, `||`, `;`, `|`, `&`), optionally preceded by env-var
# assignments (`GIT_COMMITTER_NAME=x git push`). Catches compound forms like
# `pnpm build && git push` and `git commit -m '...' && git push` that the
# original anchored-only `^git push` regex missed entirely.
PATTERN='(^|[;|&]|&&|\|\|)[[:space:]]*(([[:alnum:]_]+=[^[:space:]]+)[[:space:]]+)*git[[:space:]]+push([[:space:]]|$)'
if echo "$cmd" | grep -qE "$PATTERN"; then
  cat <<'EOF'
{
  "systemMessage": "IMPORTANT: You just pushed changes. Poll CI with `gh run watch` until all checks complete. Do NOT assume your changes work until CI is green. Do NOT accept any failures as pre-existing conditions - if CI fails, fix it."
}
EOF
fi

exit 0
