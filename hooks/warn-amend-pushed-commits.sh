#!/bin/bash
# Block amending commits that have been pushed to the remote.
# Allow amending unpushed commits freely.

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Check for git commit --amend.
# We need to match the FLAG, not occurrences of "--amend" inside argument
# strings (e.g. a commit message body or an echoed/printed string).
# Strategy: strip everything that's a string literal (single- or
# double-quoted) and anything after a heredoc opener, then substring-match
# on what remains. Only the first command segment matters (split on &&/;/|).
strip_strings_and_heredocs() {
  local s="$1"
  s="${s%%&&*}"
  s="${s%%;*}"
  s="${s%%|*}"
  s="${s%%<<*}"
  # Use python for correct quote-aware stripping; fall back to a permissive
  # regex if python isn't available (very rare on dev machines).
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import re, sys
s = sys.argv[1]
# Remove single-quoted, double-quoted, and $(...) substitutions in order.
# Repeat until stable to handle nesting like "$(cat <<EOF...EOF)".
prev = None
while prev != s:
    prev = s
    s = re.sub(r"\$\([^()]*\)", "", s)
    s = re.sub(r"'"'"'[^'"'"']*'"'"'", "", s)
    s = re.sub(r"\"[^\"]*\"", "", s)
print(s)
' "$s"
  else
    # Permissive fallback: strip greedily between matching quote pairs.
    s=$(echo "$s" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
    echo "$s"
  fi
}

cleaned=$(strip_strings_and_heredocs "$cmd")
[[ "$cleaned" == *"git commit"* && "$cleaned" == *"--amend"* ]] || exit 0

# Check if HEAD has been pushed to the remote tracking branch
remote_branch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null) || exit 0
remote_head=$(git rev-parse "$remote_branch" 2>/dev/null) || exit 0
local_head=$(git rev-parse HEAD 2>/dev/null) || exit 0

# If HEAD matches or is an ancestor of remote, it's been pushed
if git merge-base --is-ancestor "$local_head" "$remote_head" 2>/dev/null; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: HEAD has already been pushed to the remote. Amending it would require a force-push. Create a new commit instead."
  }
}
EOF
fi

exit 0
