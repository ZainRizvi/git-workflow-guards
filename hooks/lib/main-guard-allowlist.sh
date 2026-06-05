#!/bin/bash
# Optional per-repo allowlist for the main-branch guards
# (block-commit-on-main, block-edits-on-main-or-root).
#
# Scope:
#   * Project-level install (plugin lives inside the current repo) → the repo
#     opted in by installing the plugin; guard ALWAYS applies, allowlist ignored.
#     Detected via $CLAUDE_PLUGIN_ROOT being inside the repo's root checkout.
#   * User-level install (plugin lives under $HOME/.claude/ or anywhere outside
#     the repo) → consult the allowlist.
#
# Allowlist file: $XDG_CONFIG_HOME/git-workflow-guards/main-guard-repos
# (falls back to $HOME/.config/git-workflow-guards/main-guard-repos).
# One entry per line. Blank lines and `#`-comments ignored.
# File missing or empty → apply everywhere (backwards-compatible).
# File present with entries → apply only to listed repos.
#
# Entry forms:
#   * Bare name (no `/`): matched against the repo basename. A trailing `.git`
#     is stripped before matching, so `myproj` matches both `myproj` and
#     `myproj.git`.
#   * Path containing `/`: matched against the canonical repo root path
#     (resolved with `pwd -P`). Must be absolute or `~/`-prefixed; relative
#     entries are skipped because their resolution would depend on the
#     hook's invocation CWD and could match the wrong repo.
#
# Match policy: if any entry matches, the repo is in scope.
#
# Usage: source this and call `main_guard_repo_in_scope || exit 0` AFTER the
# hook has decided it would otherwise block.

main_guard_repo_in_scope() {
  local common_dir repo_root repo_name
  common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 0

  # `git rev-parse --git-common-dir` returns a physical (realpath-resolved)
  # path on macOS, so we must canonicalize repo_root the same way (`pwd -P`)
  # for the project-level prefix comparison below to work when either
  # CLAUDE_PLUGIN_ROOT or the repo lives under a symlink like /tmp or /var.
  repo_root=$(cd "$(dirname "$common_dir")" 2>/dev/null && pwd -P) || return 0
  repo_name=$(basename "$repo_root")
  [[ -z "$repo_name" ]] && return 0  # couldn't determine → fail-open (apply)

  # Strip a trailing `.git` from the basename so users don't need to know
  # whether their checkout is bare to write the allowlist entry. Skip the
  # strip if it would empty `repo_name` (a bare repo at `~/x/.git` would
  # otherwise become unmatchable by name).
  [[ "$repo_name" != ".git" ]] && repo_name="${repo_name%.git}"

  # Project-level install: plugin is checked into this repo. The act of
  # committing the plugin into the repo is itself the opt-in signal.
  # If `cd` into CLAUDE_PLUGIN_ROOT fails we leave plugin_abs empty rather
  # than falling back to the literal (un-canonicalized) string, so the
  # prefix check below cannot accidentally match.
  if [[ -n "$CLAUDE_PLUGIN_ROOT" ]]; then
    local plugin_abs
    plugin_abs=$(cd "$CLAUDE_PLUGIN_ROOT" 2>/dev/null && pwd -P) || plugin_abs=""
    if [[ -n "$plugin_abs" && ( "$plugin_abs" == "$repo_root"/* || "$plugin_abs" == "$repo_root" ) ]]; then
      return 0
    fi
  fi

  # User-level install: consult the allowlist.
  local allowlist="${XDG_CONFIG_HOME:-$HOME/.config}/git-workflow-guards/main-guard-repos"
  [[ -s "$allowlist" ]] || return 0  # no allowlist → in scope (apply everywhere)

  # Read entries: drop blanks/comments, strip surrounding whitespace, then
  # match either by full path (entry contains `/`) or by basename.
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    # Warn on any leading-`~` form we don't support (`~`, `~user`, `~user/...`)
    # — silently dropping them leaves the user wondering why their entry never
    # matches. Only `~/...` is meaningful and gets expanded below.
    # shellcheck disable=SC2088 # quoted ~ is a literal, intentional
    if [[ "${entry:0:1}" == "~" && "${entry:0:2}" != "~/" ]]; then
      echo "git-workflow-guards: allowlist entry '$entry' uses ~user form which is not supported; skipping" >&2
      continue
    fi
    if [[ "$entry" == */* ]]; then
      # Expand a leading `~/` to $HOME/. Bash performs tilde expansion on an
      # unquoted `~` inside the `#` parameter-expansion pattern, so the prefix
      # must be escaped (`\~/`) to be treated as literal. Guard on $HOME being
      # non-empty so we don't produce a surprise root-relative path.
      # shellcheck disable=SC2088 # quoted ~ is a literal, intentional
      if [[ "${entry:0:2}" == "~/" && -n "$HOME" ]]; then
        entry="$HOME/${entry#\~/}"
      fi
      # Skip anything still non-absolute — its meaning would depend on the
      # hook's CWD and could silently match the wrong repo.
      [[ "$entry" != /* ]] && continue
      # Canonicalize the same way as repo_root. If the entry path doesn't
      # exist `cd` fails and entry_canon stays at the literal string — that
      # virtually never equals the canonicalized $repo_root, which is the
      # right outcome (skip the entry). Don't "simplify" away the fallback.
      local entry_canon
      entry_canon=$(cd "$entry" 2>/dev/null && pwd -P) || entry_canon="$entry"
      [[ "$entry_canon" == "$repo_root" ]] && return 0
    else
      [[ "$entry" == "$repo_name" ]] && return 0
    fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$allowlist" \
             | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

  return 1
}
