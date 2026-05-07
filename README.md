# git-workflow-guards

A Claude Code plugin that catches common `git` and `gh` footguns before they
land. Blocks the moves you regret, nudges the moves you forget, and ships a
handful of git skills (`/making-git-commits`, `/rebase`, `/merge-pr`,
`/fix-github-issue`) plus a multi-agent review skill (`/review-changes`)
that codify a clean PR workflow.

Drop it into any git repo. The hooks run only when relevant — outside a git
repo, on commands that don't match, or in environments that opt out, they
fall through silently.

## Install

`git-workflow-guards` is distributed as a Claude Code plugin. Add the
repo as a marketplace and enable the plugin:

```bash
claude /plugin marketplace add ZainRizvi/git-workflow-guards
claude /plugin install git-workflow-guards
```

Or, edit your `~/.claude/settings.json` directly:

```json
{
  "extraKnownMarketplaces": {
    "git-workflow-guards": {
      "source": { "source": "github", "repo": "ZainRizvi/git-workflow-guards" }
    }
  },
  "enabledPlugins": {
    "git-workflow-guards@git-workflow-guards": true
  }
}
```

To develop locally, point Claude Code at a checkout:

```bash
claude --plugin-dir ~/code/git-workflow-guards
```

## What ships

### Hooks

PreToolUse on `Bash`:

| Hook | What it does |
|---|---|
| `strip-redundant-git-C.sh` | Denies `git -C <dir>`. Use `cd`/`pushd` instead. |
| `simplify-git-push.sh` | Rewrites `git push -u origin <current>` → `git push`. |
| `warn-no-verify-push.sh` | Blocks `git push --no-verify` unless the command also includes `--bypass`. |
| `ban-gh-api-comments.sh` | Rewrites `gh api repos/.../{pulls,issues}/N/comments` to the friendlier `gh pr/issue view N --comments`. |
| `block-delete-branch-in-worktree.sh` | Strips `--delete-branch` from `gh pr merge` when CWD is a worktree (deleting would break the worktree checkout). |
| `warn-amend-pushed-commits.sh` | Blocks `git commit --amend` when HEAD is already on the remote (would force a push). |
| `block-blanket-git-add.sh` | Blocks `git add -A`, `git add .`, `git commit -a/-am`. List paths explicitly. |
| `block-commit-on-main.sh` | Blocks `git commit` while on `main`/`master`/`trunk`. Override with `CLAUDE_ALLOW_MAIN_WORK=1`. |
| `block-merge-on-red-ci.sh` | Blocks `gh pr merge` when required CI checks aren't green. Configure required checks via `GIT_WORKFLOW_REQUIRED_CHECKS` (default: empty → hook is a no-op). Override with `CLAUDE_ALLOW_RED_MERGE=1`. |
| `warn-on-pr-merge.sh` | Warns (does not block) when the agent invokes `gh pr merge`. Reminder that "merging is a human action" — agents hand off, humans land. Pairs with `block-merge-on-red-ci.sh`, which still hard-blocks the unsafe case. |

PreToolUse on `Edit|Write|MultiEdit|NotebookEdit`:

| Hook | What it does |
|---|---|
| `block-edits-on-main-or-root.sh` | Blocks edits while on `main`/`master`/`trunk` or while CWD is the root worktree. Allows edits whose target file path lives in a sibling worktree. Override with `CLAUDE_ALLOW_MAIN_WORK=1`. |

PostToolUse on `Bash`:

| Hook | What it does |
|---|---|
| `remind-ci-after-push.sh` | After `git push`, reminds the agent to poll CI with `gh run watch`. |
| `post-merge-watch-deploy.sh` | After `gh pr merge`, reminds the agent to watch the post-merge deploy run on the target branch. |

### Skills

| Skill | What it covers |
|---|---|
| `/making-git-commits` | Explicit file staging, `git diff --cached` before commit, PR-title-shaped messages. |
| `/rebase` | Rebase the current branch onto `origin/main`, anticipate conflicts. |
| `/merge-pr` | Squash-merge the PR for the current branch, then watch the merge-commit's CI run on the target branch. |
| `/fix-github-issue <ref>` | Fetch a GitHub issue, implement the fix, iterate via code review. |
| `/review-changes` | Multi-agent code review of recent changes — runs up to six specialised reviewer agents in parallel, aggregates findings, implements valid feedback, and **iterates until clean**. See [Multi-agent review](#multi-agent-review) below. |

### Multi-agent review

`/review-changes` orchestrates six specialised review agents (each can also be invoked directly):

| Agent | Lens |
|---|---|
| `code-reviewer` | General bug/quality/CLAUDE.md compliance |
| `comment-analyzer` | Comment accuracy and rot |
| `test-analyzer` | Behavioural test coverage gaps |
| `silent-failure-hunter` | Suppressed errors, silent fallbacks |
| `type-design-analyzer` | Invariant strength, encapsulation |
| `code-simplifier` | Polish pass — runs after the loop converges |

The skill auto-detects scope (branch diff vs. uncommitted vs. last commit), runs your test suite first, launches the relevant agents in parallel, evaluates findings by impact (High/Medium/Low/None), implements everything with positive impact, and **re-runs the loop** until every agent returns nothing of value. Sub-agents tend to surface only a partial list per pass, so the iterate-to-clean loop is the value-add.

Default invocation reviews the current branch's diff against `main`:

```
/review-changes
```

Restrict to specific aspects:

```
/review-changes tests errors
/review-changes simplify        # polish pass after a clean review
```

The six agent prompts are adapted from Anthropic's [`pr-review-toolkit`](https://github.com/anthropics/claude-code-plugins) plugin (with project-specific TypeScript/Sentry references generalised). The iterate-until-clean orchestration loop is added on top so a single `/review-changes` invocation drives the whole review-evaluate-implement-iterate cycle instead of stopping at "agents returned, here's a list."

## Configuration

Set these environment variables (in your shell profile, repo `.env`, or
Claude settings) to tune behavior:

| Variable | Default | Purpose |
|---|---|---|
| `GIT_WORKFLOW_REQUIRED_CHECKS` | _(empty — hook no-ops)_ | Space- or comma-separated CheckRun names that must be green before `gh pr merge` is allowed. Example: `"Lint Test"`. Only list checks that run on `pull_request` events — jobs gated on `push` will appear MISSING and always block. |
| `CLAUDE_ALLOW_MAIN_WORK` | unset | When `1`, suppresses `block-commit-on-main` and `block-edits-on-main-or-root`. Use sparingly (e.g., a trivial fix when CI is broken). `CLAUDE_ALLOW_MAIN_COMMIT=1` is accepted as a legacy alias for the commit hook only. |
| `CLAUDE_ALLOW_RED_MERGE` | unset | When `1` (typically as an inline assignment, e.g. `CLAUDE_ALLOW_RED_MERGE=1 gh pr merge 42`), suppresses `block-merge-on-red-ci` for one command. Use only when a failing check is genuinely unrelated infra. |
| `CLAUDE_CODE_REMOTE` | _(set automatically by Claude Code on the web)_ | When `true`, the worktree-aware hooks (`block-checkout-on-root`, `block-commit-on-main`, `block-edits-on-main-or-root`) skip — there are no worktrees in the web environment, so the guards would only produce false positives. |

## What's intentionally *not* in scope

- **Worktree workflow hooks** that assume [worktrunk](https://github.com/ZainRizvi/worktrunk)
  (e.g. `use-worktrunk-for-worktrees`, `block-checkout-on-root`). Use the
  worktrunk plugin alongside this one if you adopt that workflow.
- **Tool-specific rewrites** (Neon, Vercel, Railway). Those belong in their
  own integrations.
- **Project-tracker reminders** (Beads, Linear, Jira). Those are workflow-,
  not git-, concerns.

## Layout

```
.claude-plugin/plugin.json    # plugin manifest
hooks/
  hooks.json                  # event wiring
  *.sh                        # one script per guard
skills/
  making-git-commits/SKILL.md
  rebase/SKILL.md
  merge-pr/SKILL.md
  fix-github-issue/SKILL.md
```

Hook commands resolve via `${CLAUDE_PLUGIN_ROOT}`, so the scripts run from
wherever Claude unpacks the plugin without any per-machine path fixup.

## Requirements

- `bash`, `jq` — every hook reads JSON on stdin via jq.
- `git` — checked at runtime; hooks soft-fail when git isn't available.
- `gh` — only required for `block-merge-on-red-ci.sh` and the `/merge-pr`,
  `/fix-github-issue` skills.
- `python3` — used by `strip-redundant-git-C.sh` and
  `warn-amend-pushed-commits.sh` for quote-aware command parsing; falls
  back to a permissive sed-based heuristic if missing.

## License

MIT — see [LICENSE](LICENSE).
