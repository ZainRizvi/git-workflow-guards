#!/bin/bash
# Block any use of "git -C". Claude should cd/pushd to the directory instead.

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# If no command, passthrough
[[ -z "$cmd" ]] && exit 0

# Check for git -C in any form (git -C dir, git -C=dir).
# We need to match an actual flag, not occurrences of "git -C" inside
# argument strings (commit messages, echoed text, etc.). Strip quoted
# string literals, $(...) substitutions, and heredoc bodies before matching.
strip_strings_and_heredocs() {
  local s="$1"
  s="${s%%&&*}"
  s="${s%%;*}"
  s="${s%%|*}"
  s="${s%%<<*}"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import re, sys
s = sys.argv[1]
prev = None
while prev != s:
    prev = s
    s = re.sub(r"\$\([^()]*\)", "", s)
    s = re.sub(r"'"'"'[^'"'"']*'"'"'", "", s)
    s = re.sub(r"\"[^\"]*\"", "", s)
print(s)
' "$s"
  else
    s=$(echo "$s" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
    echo "$s"
  fi
}

cleaned=$(strip_strings_and_heredocs "$cmd")

if [[ "$cleaned" =~ git[[:space:]]+-C ]]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Never use `git -C`. Instead, cd or pushd to the desired directory first, then run git commands there."
  }
}
EOF
  exit 0
fi

exit 0
