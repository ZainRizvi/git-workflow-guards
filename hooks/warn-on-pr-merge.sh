#!/bin/bash
# Warn (not block) when the agent invokes `gh pr merge`. The /land skill
# is explicit that "merging is human" — agents hand off, humans land.
# But past-week sessions had 2 cases where the agent merged a PR despite
# task briefs containing "Do not merge". The block-merge-on-red-ci.sh
# hook already blocks the *unsafe* merge case; this hook adds a warning
# for the *unauthorised* merge case (CI green, but agent wasn't asked to
# merge).
#
# We don't outright block: the user has explicitly asked for warn-not-
# block here, because there are legitimate cases (user said "merge it"
# in this turn, agent has explicit authorisation). Print a sharp
# reminder and let the call proceed; the resulting transcript line is
# the audit trail the agent should re-read before continuing.

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: warn-on-pr-merge hook requires jq (not found); skipping reminder" >&2
  exit 0
fi

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# Match `gh pr merge` anywhere in the command (could be after && or in a
# subshell). Re-uses the segment-splitting approach from
# block-merge-on-red-ci.sh. The regex allows a leading run of
# env-var assignments AND/OR known wrapper commands (`time`, `sudo`,
# `nice`, `ionice`, `stdbuf`) so e.g. `time gh pr merge 42` still
# triggers the warning.
splittable=$(echo "$cmd" | sed -E 's/(&&|\|\||[;|&])/\n/g')
gh_merge_re='^[[:space:]]*(([[:alnum:]_]+=[^[:space:]]+|time|sudo|nice|ionice|stdbuf)[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'

found=0
while IFS= read -r segment; do
  if [[ "$segment" =~ $gh_merge_re ]]; then
    found=1
    break
  fi
done <<< "$splittable"

[[ $found -eq 0 ]] && exit 0

# additionalContext is shown to the agent before its next turn; it does
# not block the tool call.
cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "REMINDER: *merging is a human action, not an agent action*. Before running `gh pr merge`, confirm the user has asked for the merge in this conversation (not a prior session, not the task brief). If the brief said 'do not merge' or 'hand off to human review', stop and surface the PR URL instead. Re-read the original task before continuing."
  }
}
EOF

exit 0
