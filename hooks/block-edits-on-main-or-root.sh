#!/bin/bash
# BLOCK (hard fail) when the agent is about to edit a file while either
# (a) the current branch is main/master/trunk, or (b) the CWD is the root
# worktree. All work goes through topic branches in dedicated worktrees.
#
# Suppresses the block when the edit's destination file_path lives inside
# a non-root worktree — the Edit/Write tool accepts absolute paths, so
# Claude can legitimately edit in a sibling worktree from a root-rooted
# session. Without this check the hook produces false alarms in exactly
# the recommended workflow ("create a worktree, then edit there").
#
# Emergency override: set CLAUDE_ALLOW_MAIN_WORK=1 to suppress the block
# for rare legitimate edits on main (e.g. .claude/ config, README typo).
# Use sparingly; this is a footgun.

input=$(cat)

# Skip on Claude Code for the web — there are no worktrees in that
# environment, so the root-checkout/main-branch guard is meaningless and
# only produces false positives.
[[ "$CLAUDE_CODE_REMOTE" == "true" ]] && exit 0

# Honour explicit override.
[[ "$CLAUDE_ALLOW_MAIN_WORK" == "1" ]] && exit 0

# Detect signals.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0
common_abs=$(cd "$common_dir" 2>/dev/null && pwd) || exit 0
git_abs=$(cd "$git_dir" 2>/dev/null && pwd) || exit 0

on_main=false
on_root=false
case "$branch" in
  main|master|trunk) on_main=true ;;
esac
[[ "$common_abs" == "$git_abs" ]] && on_root=true

# If neither, no block needed.
$on_main || $on_root || exit 0

# Suppress the block if the edit targets a file inside a non-root worktree.
# Claude's CWD might be the root checkout, but the Edit/Write tool accepts
# absolute paths — so it can legitimately target a file in a sibling worktree
# without the agent doing anything wrong. Without this check the hook fires
# false-alarms whenever Claude edits in another worktree from a session
# rooted at the repo root.
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
if [[ -n "$file_path" ]]; then
  # Canonicalize to a real path. We need realpath (resolve symlinks), not
  # just abspath: on macOS /tmp is a symlink to /private/tmp, and `git
  # worktree list` returns the resolved physical path. abspath would leave
  # /tmp/... unresolved and the prefix comparison below would falsely miss.
  # The file may not exist yet (Write creates new files); resolve the
  # deepest existing ancestor and append the remainder.
  canonicalize() {
    if command -v python3 >/dev/null 2>&1; then
      python3 -c '
import os, sys
p = os.path.abspath(sys.argv[1])
# Walk up to the deepest existing ancestor, realpath that, then re-append.
existing = p
tail_parts = []
while existing and not os.path.exists(existing):
    existing, tail = os.path.split(existing)
    tail_parts.insert(0, tail)
real = os.path.realpath(existing) if existing else "/"
if tail_parts:
    real = os.path.join(real, *tail_parts)
print(real)
' "$1"
    else
      echo "$1"
    fi
  }
  file_abs=$(canonicalize "$file_path")

  # The repo root checkout is the parent of git_common_dir.
  root_checkout=$(canonicalize "$(dirname "$common_abs")")

  # Iterate worktree paths via while/read so paths containing spaces work.
  # awk strips the leading "worktree " keyword and prints the rest as-is
  # (handles spaces in the path correctly).
  in_root_checkout=false
  in_other_worktree=false
  any_worktree_seen=false
  while IFS= read -r wt_path; do
    [[ -z "$wt_path" ]] && continue
    any_worktree_seen=true
    wt_canon=$(canonicalize "$wt_path")
    if [[ "$wt_canon" == "$root_checkout" ]]; then
      [[ "$file_abs" == "$wt_canon"/* || "$file_abs" == "$wt_canon" ]] && in_root_checkout=true
      continue
    fi
    if [[ "$file_abs" == "$wt_canon"/* || "$file_abs" == "$wt_canon" ]]; then
      in_other_worktree=true
    fi
  done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {sub(/^worktree /, ""); print}')

  # Edit targets a non-root worktree — legitimate, allow.
  $in_other_worktree && exit 0

  # Edit targets a path outside the repo entirely (not in root checkout,
  # not in any sibling worktree). The hook's job is to keep work off main
  # IN THE REPO; edits to ~/.claude/projects/... or /tmp/... aren't repo
  # work and shouldn't be blocked just because cwd happens to be the
  # root checkout.
  #
  # Fail-closed if `git worktree list` produced no entries (git error,
  # corrupt DB, missing binary): we can't tell whether the file is in the
  # repo, so default to blocking. Without this guard the hook would
  # silently allow all edits any time git is unhappy.
  if $any_worktree_seen && ! $in_root_checkout; then
    exit 0
  fi
fi

# Build the error message based on which conditions tripped.
where=""
if $on_main && $on_root; then
  where="the ROOT worktree on branch '$branch'"
elif $on_main; then
  where="branch '$branch'"
else
  where="the ROOT worktree"
fi

# Emit denial with permissionDecision: "deny" to block the operation.
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: You are about to edit a file while in $where. All work goes through PRs from topic branches in dedicated worktrees, not on main or in the root checkout.\n\nCreate a dedicated worktree for this topic:\n  wt switch --create <topic-name>\n\nAfter wt prints the new worktree path, you must switch to it before retrying the edit:\n  cd <new-worktree-path>\n\nTo migrate any in-progress edits from the root checkout, choose based on your situation:\n\n  Option A — git stash (simpler, safe in quiet repos):\n    git stash push -m 'migrate to <topic>' -- <files>\n    cd <new-worktree-path> && git stash pop\n\n  Option B — copy + clean (safer with concurrent sessions):\n    cp <files> <new-worktree-path>/<files>\n    git restore <files>\n    git clean -nd   # dry-run; drop -n to delete untracked files\n\nThen retry the Edit or Write operation from inside the new worktree.\n\nEmergency override (use sparingly; e.g. .claude/ config edits, README typo on main):\n  CLAUDE_ALLOW_MAIN_WORK=1 <tool-command>"
  }
}
EOF

exit 0
