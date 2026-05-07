#!/bin/bash
# PostToolUse hook for Bash. Reminds Claude to watch the post-merge
# deploy workflow run on main after `gh pr merge`. Without this nudge,
# the merge succeeds and the agent moves on without verifying the
# production-promotion run finishes (which can fail on env-var drift,
# migration races, deploy outages, etc.).
#
# Soft-gate: prints to stderr and exits 0 (PostToolUse can't block
# anyway — the tool already ran).

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Match `gh pr merge` only when it appears at the start of a command
# (line start or after a shell separator), optionally preceded by env
# assignments. Pattern mirrors check-review-findings.sh so behavior is
# consistent across the two hooks that watch this command.
PATTERN='(^|[;|&]|&&|\|\|)[[:space:]]*(([[:alnum:]_]+=[^[:space:]]+)[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'
if ! echo "$COMMAND" | grep -qE "$PATTERN"; then
  exit 0
fi

if command -v gh >/dev/null 2>&1; then
  cat >&2 <<'MSG'
REMINDER: `gh pr merge` triggers the "Promote main to production"
workflow on main. The merge succeeding does not mean the deploy
succeeded. Before reporting the work as done, watch the run:

  1. Find the run for your merge commit:
     gh run list --branch main --limit 3
  2. Stream it (foreground):
     gh run watch <run-id>
     OR set up a background Monitor that polls
     `gh run view <run-id> --json status,conclusion` every 30s and
     emits when status=completed.
  3. If it fails, surface the failure to the user immediately —
     do not bury it.

Common deploy-time failures: env-var drift on Railway/Vercel,
migration race against pre-deploy traffic, third-party service outage.
MSG
else
  # `gh` isn't on PATH — likely Claude Code web or a stripped CI image.
  # The agent can't watch via gh, but should still flag the in-flight
  # deploy to the user instead of silently moving on. Resolve the
  # repo's actions URL from `origin` so the agent has a real link to
  # surface (vs. a `<owner>/<repo>` placeholder it would paste verbatim).
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
  # Strip SSH (`git@github.com:owner/repo.git`), HTTPS
  # (`https://github.com/owner/repo.git`), and port-qualified SSH
  # (`ssh://git@github.com:22/owner/repo.git`) forms; keep just
  # `owner/repo`. The optional `[0-9]*/` chunk after the host eats a
  # port if present.
  REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/]([0-9]+/)?||; s|\.git$||')
  if [ -n "$REPO_PATH" ]; then
    ACTIONS_URL="https://github.com/$REPO_PATH/actions"
  else
    ACTIONS_URL="(your repo's GitHub Actions page)"
  fi
  cat >&2 <<MSG
REMINDER: \`gh pr merge\` triggers the "Promote main to production"
workflow on main. The merge succeeding does not mean the deploy
succeeded.

\`gh\` is not on PATH in this environment, so the agent cannot watch
the run directly. Instead, surface the in-flight deploy to the user
explicitly — e.g. "merged; the production-promotion run is in flight
at $ACTIONS_URL, please confirm it lands green" — rather than
reporting the work as done.
MSG
fi

exit 0
