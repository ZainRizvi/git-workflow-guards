#!/bin/bash
# Block `git commit` (any variant, including --amend) when the current
# branch is main/master/trunk. All work happens on topic branches in
# dedicated worktrees; main is updated by merging PRs, never by direct
# commits.
#
# Emergency override: set CLAUDE_ALLOW_MAIN_WORK=1 (preferred) or the
# legacy CLAUDE_ALLOW_MAIN_COMMIT=1 (kept for backwards compat) in the
# command's environment for the rare legitimate direct-commit case
# (e.g. CI is broken and the fix is trivial). Use sparingly; this is a
# footgun. The same alias silences the warn-edits-on-main-or-root hook.
#
# Per-repo scoping: at user-level installs, the hook can be limited to
# specific repos via $XDG_CONFIG_HOME/git-workflow-guards/main-guard-repos.
# See lib/main-guard-allowlist.sh and README "Main-branch guard scope".

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

[[ -z "$cmd" ]] && exit 0

# Skip on Claude Code for the web — there are no worktrees in that
# environment, so the main-branch guard is meaningless and only produces
# false positives.
[[ "$CLAUDE_CODE_REMOTE" == "true" ]] && exit 0

# Honour explicit override (new name preferred, old name still accepted).
[[ "$CLAUDE_ALLOW_MAIN_WORK" == "1" ]] && exit 0
[[ "$CLAUDE_ALLOW_MAIN_COMMIT" == "1" ]] && exit 0

# Only inspect the FIRST segment of a compound command.
first_segment="${cmd%%&&*}"
first_segment="${first_segment%%;*}"
first_segment="${first_segment%%|*}"

# Match git invocations even when interleaved with global flags
# (`git -c key=val commit`, `git --git-dir=... commit`).
git_prefix='^[[:space:]]*git([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+))*[[:space:]]+'

[[ "$first_segment" =~ ${git_prefix}commit([[:space:]]|$) ]] || exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0

case "$branch" in
  main|master|trunk) ;;
  *) exit 0 ;;
esac

# Per-repo scoping: skip if user-level install and this repo isn't allowlisted.
# Prefer CLAUDE_PLUGIN_ROOT (set by Claude Code) so we work when the hook is
# invoked via a symlink, which would break a bare `$(dirname "$0")` lookup.
# Fall back to resolving BASH_SOURCE through symlinks one hop at a time,
# anchoring each relative target to the previous link's directory.
_gwg_lib_dir="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/hooks}"
if [[ -z "$_gwg_lib_dir" ]]; then
  _gwg_src="${BASH_SOURCE[0]}"
  while [[ -L "$_gwg_src" ]]; do
    _gwg_tgt=$(readlink "$_gwg_src")
    [[ "$_gwg_tgt" != /* ]] && _gwg_tgt="$(dirname "$_gwg_src")/$_gwg_tgt"
    _gwg_src="$_gwg_tgt"
  done
  _gwg_lib_dir=$(cd "$(dirname "$_gwg_src")" 2>/dev/null && pwd)
fi
# Fail-open ONLY if the helper file is missing. If it exists but fails to
# parse, let bash surface the error to stderr (Claude Code captures it) so
# the regression is visible instead of silently turning the guard off.
_gwg_lib="$_gwg_lib_dir/lib/main-guard-allowlist.sh"
if [[ ! -r "$_gwg_lib" ]]; then
  exit 0
fi
# shellcheck source=lib/main-guard-allowlist.sh
# shellcheck disable=SC1091
. "$_gwg_lib"
# If sourcing failed mid-parse, the function isn't defined. Bash already
# printed the parse error to stderr; warn loudly here and fail-open so the
# guard isn't silently disabled forever.
if ! declare -F main_guard_repo_in_scope >/dev/null; then
  echo "git-workflow-guards: failed to load $_gwg_lib (see above); main-branch guard disabled" >&2
  exit 0
fi
main_guard_repo_in_scope || exit 0

# Use jq for JSON encoding so the deny payload stays well-formed regardless
# of what `$branch` resolves to (defense in depth — currently it's filtered
# to main/master/trunk, but cheap insurance against future widening).
reason="BLOCKED: You are about to commit directly to '$branch'. All work goes through PRs from topic branches in dedicated worktrees.

Create a worktree for this work:
  wt switch --create <topic-name>

Note: PreToolUse hooks cannot change Claude's CWD. After wt prints the new worktree path, you must \`cd\` into it before retrying the commit.

To migrate your uncommitted edits, pick based on repo activity. Run \`git worktree list\` to gauge — many active worktrees / parallel agents = pick copy; quiet repo = stash is fine:

  Option A — git stash (simpler, safe in quiet repos):
    git stash push -m 'migrate to <topic>' -- <files>
    cd <new-worktree-path> && git stash pop

  Option B — copy + clean (safer when other sessions might also be stashing):
    cp <files> <new-worktree-path>/<files>
    git restore <files-you-copied>
    git clean -nd   # dry-run; drop -n to delete untracked files

Finally, stage and commit from inside the new worktree.

Emergency override (use sparingly; e.g. CI is broken and the fix is trivial):
  CLAUDE_ALLOW_MAIN_WORK=1 git commit -m '...'"

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'

exit 0
