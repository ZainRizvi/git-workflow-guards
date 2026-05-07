#!/bin/bash
# Block `gh pr merge <N>` (any flag combination) when PR <N> has any failing
# or in-flight required CI check. Catches the "merging while CI is red"
# class of failure that has bitten this repo before.
#
# Required-check policy: every check in REQUIRED_CHECKS must report `pass`
# (or `skipping`/`neutral`) on the PR's most recent run. Anything else —
# `fail`, `pending`, `in_progress`, `cancelled`, missing entirely — blocks.
#
# Soft-fails open if:
#   - jq or gh aren't installed (advisory: warns to stderr)
#   - we can't extract a PR number from the command (e.g. `gh pr merge` with
#     no positional, which gh resolves from current branch — covered separately
#     below)
#   - `gh pr checks` errors (network blip, auth issue) — surface a warning,
#     allow. The reasoning: a hook that blocks on its own infrastructure
#     failures is worse than no hook.
#
# Emergency override:
#   CLAUDE_ALLOW_RED_MERGE=1 gh pr merge <N> ...
# Use only when the failing check is unrelated infra (e.g. preview deploy
# failing on missing secrets) AND a human has explicitly authorized.

# Required checks. Configurable via the GIT_WORKFLOW_REQUIRED_CHECKS env var
# (space- or comma-separated list of CheckRun names). Defaults to empty —
# no required checks, hook is a no-op until you tell it what to gate on.
#
# Each named check must report a SUCCESS/SKIPPED/NEUTRAL conclusion on the
# PR's most recent run. Anything else (failing, in-flight, missing) blocks
# the merge. Only check the names that actually run on `pull_request`; jobs
# gated on `push` events never appear in a PR's statusCheckRollup and would
# always classify as MISSING.
#
# Examples:
#   GIT_WORKFLOW_REQUIRED_CHECKS="Lint"
#   GIT_WORKFLOW_REQUIRED_CHECKS="Lint Test build"
#   GIT_WORKFLOW_REQUIRED_CHECKS="Lint,Test"
_required_raw="${GIT_WORKFLOW_REQUIRED_CHECKS:-}"
# Normalize commas to spaces, then word-split.
read -ra REQUIRED_CHECKS <<< "${_required_raw//,/ }"

# If the user hasn't configured any required checks, this hook does nothing.
if [[ ${#REQUIRED_CHECKS[@]} -eq 0 ]]; then
  exit 0
fi

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: block-merge-on-red-ci hook requires jq (not found); allowing merge unchecked" >&2
  exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# Honour explicit override (intentional, audited bypass). The override is
# expressed as an inline env assignment in the command string itself
# (`CLAUDE_ALLOW_RED_MERGE=1 gh pr merge ...`), so we scan the command
# rather than the hook's process environment — inline assignments are
# scoped to the subshell that runs `gh`, not propagated up to the hook.
if [[ "$cmd" =~ (^|[[:space:]])CLAUDE_ALLOW_RED_MERGE=1([[:space:]]|$) ]]; then
  exit 0
fi

# Split the command on shell separators so a merge buried in a fallback
# (`false || gh pr merge 5`) is still caught. The other block-* hooks in
# this repo only inspect the first segment, but the cost of a missed
# merge-while-red is high enough to justify the broader scan here.
# Replace each separator with a newline, then iterate.
splittable=$(echo "$cmd" | sed -E 's/(&&|\|\||[;|&])/\n/g')

# Match `gh pr merge` anchored at the start of a segment, allowing leading
# env-var assignments (matches the regex style from check-review-findings.sh).
gh_merge_re='^[[:space:]]*(([[:alnum:]_]+=[^[:space:]]+)[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'

merge_segment=""
while IFS= read -r segment; do
  if [[ "$segment" =~ $gh_merge_re ]]; then
    merge_segment="$segment"
    break
  fi
done <<< "$splittable"

[[ -z "$merge_segment" ]] && exit 0
first_segment="$merge_segment"

if ! command -v gh >/dev/null 2>&1; then
  echo "WARNING: block-merge-on-red-ci hook requires gh; allowing merge unchecked" >&2
  exit 0
fi

# Extract the PR number. `gh pr merge` accepts either a positional <number>
# (or URL/branch) or no positional at all (resolves from current branch).
# Strategy: take the first non-flag, non-flag-value token after `merge`.
# If none, fall through to "branch resolves to PR" via `gh pr view`.
read -ra tokens <<< "$first_segment"
pr_arg=""
seen_merge=0
skip_next=0
for tok in "${tokens[@]}"; do
  if [[ $skip_next -eq 1 ]]; then
    skip_next=0
    continue
  fi
  if [[ $seen_merge -eq 0 ]]; then
    [[ "$tok" == "merge" ]] && seen_merge=1
    continue
  fi
  case "$tok" in
    # Boolean / no-value flags. `--match-head-commit=<sha>` is the inline-value
    # form which terminates here (the value is glued to the flag); the bare
    # `--match-head-commit` form falls into the value-consuming branch below.
    --auto|--squash|--merge|--rebase|--admin|--delete-branch|--auto-merge|--match-head-commit=*)
      ;;
    -d|-s|-r|-m)
      ;;
    # Value-consuming flags. Bare form expects the value as the next token.
    # Inline `=`-form variants are not listed here since the value is part
    # of the same token and would be unreachable; `-*)` catches them.
    --body|--body-file|--subject|--match-head-commit)
      skip_next=1
      ;;
    -*)
      ;;
    *)
      pr_arg="$tok"
      break
      ;;
  esac
done

# Resolve PR number. Accepts:
#   - bare number: 18
#   - full URL: https://github.com/<o>/<r>/pull/18
#   - branch name: gh resolves it
#   - empty: gh pr checks (no arg) uses current branch
pr_number=""
if [[ -z "$pr_arg" ]]; then
  pr_number=$(gh pr view --json number -q .number 2>/dev/null) || pr_number=""
elif [[ "$pr_arg" =~ ^[0-9]+$ ]]; then
  pr_number="$pr_arg"
elif [[ "$pr_arg" =~ /pull/([0-9]+) ]]; then
  pr_number="${BASH_REMATCH[1]}"
else
  # Branch name — let gh resolve.
  pr_number=$(gh pr view "$pr_arg" --json number -q .number 2>/dev/null) || pr_number=""
fi

if [[ -z "$pr_number" ]]; then
  echo "WARNING: block-merge-on-red-ci hook could not resolve PR number from '$first_segment'; allowing merge unchecked" >&2
  exit 0
fi

# Pull the check rollup. We want each required check's most recent conclusion.
checks_json=$(gh pr view "$pr_number" --json statusCheckRollup -q '.statusCheckRollup' 2>/dev/null)
if [[ -z "$checks_json" || "$checks_json" == "null" ]]; then
  echo "WARNING: block-merge-on-red-ci could not fetch checks for PR #$pr_number; allowing merge unchecked" >&2
  exit 0
fi

# Build a name->status map from CheckRun entries. StatusContext entries
# (Vercel etc.) aren't in REQUIRED_CHECKS, so they don't block.
failing=()
missing=()
for required in "${REQUIRED_CHECKS[@]}"; do
  status=$(echo "$checks_json" | jq -r --arg name "$required" '
    [.[] | select(.__typename == "CheckRun" and .name == $name)]
    | sort_by(.completedAt) | last
    | if . == null then "MISSING"
      elif .status != "COMPLETED" then "IN_PROGRESS"
      else (.conclusion // "UNKNOWN")
      end
  ')
  case "$status" in
    SUCCESS|SKIPPED|NEUTRAL)
      ;;
    MISSING)
      missing+=("$required")
      ;;
    UNKNOWN)
      # COMPLETED but null conclusion — typically a transient propagation
      # race. Block (better safe than sorry) but label diagnostically.
      failing+=("$required: completed with no conclusion (transient — retry shortly)")
      ;;
    *)
      failing+=("$required: $status")
      ;;
  esac
done

if [[ ${#failing[@]} -eq 0 && ${#missing[@]} -eq 0 ]]; then
  exit 0
fi

# Build the deny payload.
reason="BLOCKED: gh pr merge on PR #$pr_number rejected because required CI checks are not green.\n\n"
if [[ ${#failing[@]} -gt 0 ]]; then
  reason+="Failing or in-flight required checks:\n"
  for entry in "${failing[@]}"; do
    reason+="  - $entry\n"
  done
fi
if [[ ${#missing[@]} -gt 0 ]]; then
  reason+="Missing required checks (not yet reported):\n"
  for entry in "${missing[@]}"; do
    reason+="  - $entry\n"
  done
fi
reason+="\nFix CI first, wait for it to go green, then retry. Do not merge speculatively.\n\n"
reason+="If the failing check is genuinely unrelated infra (e.g. Vercel preview env not configured) AND a human has explicitly authorized the bypass, override with:\n"
reason+="  CLAUDE_ALLOW_RED_MERGE=1 gh pr merge $pr_number ...\n\n"
reason+="Required checks tracked: ${REQUIRED_CHECKS[*]}"

# jq handles JSON encoding of the multi-line reason for us.
jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'

exit 0
