#!/bin/bash
# Block blanket staging operations: `git add -A`, `git add .`, `git add --all`,
# `git commit -a`, `git commit -am ...`. These sweep in stray files (other
# sessions' work, generated artefacts, .DS_Store, accidental edits) and have
# been the proximate cause of polluted commits more than once.
#
# Allowed: `git add <path>` (specific files or directories by name), even if
# the path is a directory like `drizzle/` or `features/audit/`.

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

[[ -z "$cmd" ]] && exit 0

# Strip everything after a shell separator so compound commands like
# `git status && git add -A` are evaluated only on the relevant segment.
# We intentionally only inspect the FIRST git invocation in the command
# string; if a later segment violates, that's a known limitation (Claude
# rarely chains git operations this way, and the strict regex below
# limits collateral damage).
first_segment="${cmd%%&&*}"
first_segment="${first_segment%%;*}"
first_segment="${first_segment%%|*}"

# Match git invocations even when interleaved with `-c key=val` flags
# or `-C path` (e.g. `git -c user.email=x add -A`). Group the optional
# flag-prefix so it doesn't leak into argument parsing.
git_prefix='^[[:space:]]*git([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+))*[[:space:]]+'

violation=""

# git add -A / --all / .
if [[ "$first_segment" =~ ${git_prefix}add([[:space:]]|$) ]]; then
  args="${first_segment#${BASH_REMATCH[0]}}"
  # Use read -ra to preserve quoted arguments rather than word-splitting
  # on every space (which would break paths like "my file.txt").
  read -ra toks <<< "$args"
  for tok in "${toks[@]}"; do
    case "$tok" in
      -A|--all) violation="git add $tok"; break ;;
      .)        violation="git add ."; break ;;
    esac
    # Combined short flags containing A: -Av, -uA, etc. Exclude long flags.
    if [[ "$tok" =~ ^-[A-Za-z]*A[A-Za-z]*$ ]]; then
      violation="git add $tok"; break
    fi
  done
fi

# git commit -a / -am / -aXY / --all
if [[ -z "$violation" && "$first_segment" =~ ${git_prefix}commit([[:space:]]|$) ]]; then
  args="${first_segment#${BASH_REMATCH[0]}}"
  read -ra toks <<< "$args"
  skip_next=0
  for tok in "${toks[@]}"; do
    if [[ $skip_next -eq 1 ]]; then
      skip_next=0
      continue
    fi
    case "$tok" in
      --all) violation="git commit --all"; break ;;
      -a)    violation="git commit -a"; break ;;
      # Value-consuming flags. Skip the next token so a value that happens
      # to contain 'a' (e.g. `-F changelog.md`, `--message 'add a thing'`)
      # doesn't trip the short-flag-cluster regex below. --message is the
      # canonical form Claude uses, so the long forms matter in practice.
      -F|--file|-C|--reuse-message|-c|--reedit-message|-m|--message|-t|--template) skip_next=1; continue ;;
    esac
    # Short-flag clusters containing 'a': -am, -am"msg", -aS, etc.
    # Exclude --amend (long flag, starts with --).
    if [[ "$tok" =~ ^-[A-Za-z]+$ && "$tok" =~ a ]] && [[ "$tok" != --* ]]; then
      violation="git commit $tok"; break
    fi
  done
fi

[[ -z "$violation" ]] && exit 0

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: '$violation' stages everything dirty in the working tree, which sweeps in stray files (other sessions' edits, generated artefacts, .DS_Store, untracked scratch). List files explicitly instead.\n\nFigure out what to add:\n  git status --short\n  git diff --stat        # unstaged changes\n  git diff --stat --cached  # already staged\n\nThen stage by name:\n  git add path/to/file1 path/to/file2\n  git add path/to/dir/   # whole directory by name is fine\n\nFor commit, drop the -a flag and use a separate \`git add\` step before \`git commit\`."
  }
}
EOF

exit 0
