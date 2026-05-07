# Repo Setup Checklist

Things to add to every new repo. The `/setup-repo` skill applies all of these idempotently.

## Claude Code config

### `.claude/settings.json`

Project-level Claude settings. The recommended baseline auto-installs the `git-workflow-guards` plugin on first session, sets the required-CI-checks for `block-merge-on-red-ci`, and wires in a Stop-time ratchet agent that watches for redirects:

```json
{
  "extraKnownMarketplaces": {
    "git-workflow-guards": {
      "source": { "source": "github", "repo": "ZainRizvi/git-workflow-guards" }
    }
  },
  "enabledPlugins": {
    "git-workflow-guards@git-workflow-guards": true
  },
  "env": {
    "GIT_WORKFLOW_REQUIRED_CHECKS": "Lint"
  },
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "agent",
            "model": "inherit",
            "prompt": "You are a ratchet agent. Look only at the most recent user message and Claude's reply immediately before it. Did the user correct or redirect Claude's behaviour?\n\nIf no: do nothing.\n\nIf yes: implement one ratchet to prevent the mistake recurring. Pick the mechanism that fires closest to the mistake with the least LLM reasoning required:\n1. Lint rule — static, fires before code ships\n2. Git hook — blocks at commit/push\n3. Claude PreToolUse hook — intercepts the exact tool call\n4. Claude PostToolUse hook — fires right after the action\n5. Skill update — reusable slash-command guidance\n6. Memory entry — last resort\n\nDecide scope first: all repos (→ ~/.claude/) or just this one (→ .claude/ or repo memory/).\n\nImplement it with your tools.",
            "timeout": 60,
            "statusMessage": "Checking for ratchets..."
          }
        ]
      }
    ]
  }
}
```

Edit `GIT_WORKFLOW_REQUIRED_CHECKS` to list the CheckRun names that must be green for the merge-blocking hook to allow `gh pr merge` (default: `Lint`; project-specific). Leave empty to disable the merge-blocking hook entirely.

### `.claude/ratchets.md`

Append-only log of incidents the harness has learned from. The `/ratchet-harness` skill consults this file before deciding if an incident is novel. Bootstrap with the standard header:

```markdown
# Ratchets log

A chronological log of incidents that informed the project's automated
checks. New entries go at the top. The `/ratchet-harness` skill reads
this file in step 2 to spot recurring classes of failure.

## YYYY-MM-DD — short title

**Incident**: one sentence describing what failed and how.
**Class**: the *shape* of the failure (not the specific instance).
**Response**: which step(s) of /ratchet-harness applied, and what
specific rule/test/note was added (cite file path or commit SHA).
**Status**: `rule-added` / `note-added` / `not-yet-promoted` / `do-nothing`.
```

## Git hooks

- lefthook configured for the repo's language/toolchain (`/setup-lefthook`).

## CLAUDE.md

- Root `CLAUDE.md` with TDD, Tidy First, Commit Discipline, Code Organisation, Code Design (`/setup-claude-md`).
