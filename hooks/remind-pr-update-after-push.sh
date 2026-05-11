#!/bin/bash
# After a `git push`, if the current branch already has an OPEN PR on the
# remote, nudge Claude to consider whether the PR title and description still
# describe the full branch diff (origin..HEAD), not just the latest push.

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: remind-pr-update-after-push hook requires jq (not found); skipping reminder" >&2
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Match `git push` anchored at the start of any command segment (line start
# or after `&&`, `||`, `;`, `|`, `&`), optionally preceded by env-var
# assignments. Same pattern used by remind-ci-after-push.sh.
PATTERN='(^|[;|&]|&&|\|\|)[[:space:]]*(([[:alnum:]_]+=[^[:space:]]+)[[:space:]]+)*git[[:space:]]+push([[:space:]]|$)'
if ! echo "$cmd" | grep -qE "$PATTERN"; then
  exit 0
fi

# Look up the PR associated with the current branch. `gh pr view` (no args)
# resolves the PR from the current branch's tracking ref. Exits non-zero
# when no PR exists — in that case the agent presumably just opened a new
# branch and will create the PR next, so nothing to remind about.
pr_info=$(gh pr view --json state,number 2>/dev/null) || exit 0
state=$(echo "$pr_info" | jq -r '.state // empty')
[[ "$state" == "OPEN" ]] || exit 0

number=$(echo "$pr_info" | jq -r '.number // empty')

cat <<EOF
{
  "systemMessage": "You just pushed an update to PR #${number}. Consider: is a PR title or description update warranted? The title and description should capture the change between the original commit this branch was forked from and the present HEAD — not just the latest push."
}
EOF

exit 0
