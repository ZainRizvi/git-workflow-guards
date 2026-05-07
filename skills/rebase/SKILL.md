---
name: rebase
description: Rebase the current branch onto the latest origin/main
allowed-tools: Bash(git fetch:*), Bash(git log:*), Bash(git diff:*), Bash(git rebase:*), Bash(git show:*), Bash(git merge-base:*), Bash(git rev-parse:*), Bash(git status:*), Bash(git branch:*)
user-invokable: true
---

# Rebase onto latest origin/main

Rebase the current branch onto the latest `origin/main`, taking care to anticipate and handle conflicts.

## Steps

1. **Fetch latest main and find the merge base:**

```bash
git fetch origin main
git merge-base HEAD origin/main
```

Store the merge base commit hash for use in subsequent commands.

2. **Identify incoming commits:**

```bash
git log --oneline <merge-base>..origin/main
```

3. **Analyze incoming commits for conflict risk:**

For each incoming commit, understand its purpose and the files it touches. Compare against the changes on the current branch:

```bash
git diff --name-only <merge-base>..HEAD
git diff --name-only <merge-base>..origin/main
```

If any incoming commits touch the same files or areas as the current branch, inspect them closely to understand the nature of both sets of changes and plan how to resolve conflicts before starting the rebase.

3. **Rebase:**

```bash
git rebase origin/main
```

If conflicts arise, resolve them using the understanding built in step 2, then `git rebase --continue`. Repeat until the rebase completes.
