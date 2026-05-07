---
name: setup-lefthook
description: Configure lefthook git hooks for any repository. Analyzes project structure, detects language/tools, and generates optimized pre-commit hooks.
disable-model-invocation: true
---

# Setup Lefthook

Configure lefthook git hooks for any repository with intelligent detection of project structure and available tools.

## Workflow

### Phase 1: Repository Analysis

Detect language ecosystem and available tools:

**Language Detection (check in order):**

| Language | Primary Indicators | Secondary Indicators |
|----------|-------------------|---------------------|
| Node.js | `package.json` | `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lockb` |
| Python (uv) | `pyproject.toml` + `uv.lock` | `.python-version` |
| Python (other) | `requirements.txt`, `Pipfile`, `poetry.lock` | `setup.py` |
| Rust | `Cargo.toml` | `Cargo.lock` |
| Go | `go.mod` | `go.sum` |

**Package Manager Detection (Node.js):**

| Lockfile | Package Manager | Run Command |
|----------|-----------------|-------------|
| `bun.lockb` | bun | `bun run` |
| `pnpm-lock.yaml` | pnpm | `pnpm run` |
| `yarn.lock` | yarn | `yarn` |
| `package-lock.json` | npm | `npm run` |

**Available Scripts/Tools Detection:**

For Node.js, check `package.json` scripts for:
- `typecheck`, `tsc`, `check:types`
- `lint`, `eslint`
- `test`, `vitest`, `jest`
- `format:check`, `prettier --check`

For Python (uv), check `pyproject.toml` for:
- `[tool.mypy]` or `[tool.pyright]` → typecheck
- `[tool.ruff]` → lint
- `[tool.pytest]` or pytest in dependencies → test

For Rust, always available:
- `cargo check`, `cargo clippy`, `cargo test`, `cargo fmt --check`

For Go, check for:
- `golangci-lint` in path or config
- Standard: `go vet`, `go test`

**Monorepo Detection:**

- Node.js: Check `workspaces` in root `package.json`, or `pnpm-workspace.yaml`
- Rust: Check `[workspace]` in `Cargo.toml`
- Go: Multiple `go.mod` files

**CI Analysis:**

Check `.github/workflows/*.yml` for hints about which checks the project runs.

### Phase 2: Existing Config Analysis

If `lefthook.yml` or `lefthook.yaml` exists:

1. Parse the existing configuration
2. Identify **cruft** to remove:
   - Commands referencing non-existent scripts/tools
   - Commands for deleted workspaces/directories
   - Redundant options with no effect:
     - `stage_fixed: false` on non-fixing commands
     - `skip: [merge, rebase]` on pre-commit (already doesn't run)
     - `parallel: false` when there's only one command
3. Identify **gaps** to fill:
   - New workspaces added since config creation
   - New scripts that should be hooked
4. Preserve intentional customizations

### Phase 3: Configuration Generation

Generate minimal `lefthook.yml`:

```yaml
pre-commit:
  parallel: true
  commands:
    # One command per check, per workspace
```

**Principles:**

- Use `pre-commit` hook (runs on `git commit`)
- Set `parallel: true` at hook level
- Use `glob` patterns to only run when relevant files are staged
- Use `root` to set working directory for workspace commands
- Include only options that have an effect

**Glob Patterns:**

For each workspace, determine which files trigger its hooks:

```yaml
# Workspace's own files
glob: "packages/foo/**/*.{ts,tsx}"

# If workspace A imports from workspace B, A's hooks trigger on B too
glob: "{packages/foo,packages/shared}/**/*.{ts,tsx}"
```

Analyze imports to detect cross-workspace dependencies.

**Extension patterns by language:**
- Node.js: `*.{ts,tsx,js,jsx,mjs,cjs}`
- Python: `*.py`
- Rust: `*.rs`
- Go: `*.go`

### Phase 4: Installation

**Node.js:**
```bash
# Install using detected package manager
npm install --save-dev lefthook
# or: pnpm add -D lefthook / yarn add -D lefthook / bun add -d lefthook

# Add prepare script to root package.json
# "prepare": "lefthook install"

# Run initial install
lefthook install
```

**Python (uv):**
```bash
uv add --dev lefthook
# or install globally: brew install lefthook
lefthook install
```

**Rust/Go:**
```bash
# Install via cargo/go/brew
cargo install lefthook  # or: go install github.com/evilmartians/lefthook@latest
lefthook install
```

### Phase 5: Validation

```bash
lefthook run pre-commit --force
```

Report any failures and suggest fixes.

## Example Configurations

### Node.js Monorepo

```yaml
pre-commit:
  parallel: true
  commands:
    core-typecheck:
      root: packages/core/
      run: npm run typecheck
      glob: "packages/core/**/*.{ts,tsx}"
    core-test:
      root: packages/core/
      run: npm test
      glob: "packages/core/**/*.{ts,tsx}"
    web-lint:
      root: packages/web/
      run: npm run lint
      glob: "{packages/core,packages/web}/**/*.{ts,tsx}"  # web imports from core
    web-typecheck:
      root: packages/web/
      run: npm run typecheck
      glob: "{packages/core,packages/web}/**/*.{ts,tsx}"
```

### Python (uv)

```yaml
pre-commit:
  parallel: true
  commands:
    typecheck:
      run: uv run mypy src/
      glob: "src/**/*.py"
    lint:
      run: uv run ruff check src/
      glob: "src/**/*.py"
    test:
      run: uv run pytest
      glob: "{src,tests}/**/*.py"
```

### Rust Workspace

```yaml
pre-commit:
  parallel: true
  commands:
    check:
      run: cargo check --all
      glob: "**/*.rs"
    clippy:
      run: cargo clippy --all -- -D warnings
      glob: "**/*.rs"
    test:
      run: cargo test --all
      glob: "**/*.rs"
```

### Go

```yaml
pre-commit:
  parallel: true
  commands:
    vet:
      run: go vet ./...
      glob: "**/*.go"
    lint:
      run: golangci-lint run
      glob: "**/*.go"
    test:
      run: go test ./...
      glob: "**/*.go"
```

### Single Node.js Package

```yaml
pre-commit:
  parallel: true
  commands:
    typecheck:
      run: npm run typecheck
      glob: "**/*.{ts,tsx}"
    lint:
      run: npm run lint
      glob: "**/*.{ts,tsx}"
    test:
      run: npm test
      glob: "**/*.{ts,tsx}"
```

## Common Mistakes to Avoid

| Mistake | Why Bad | Correct Approach |
|---------|---------|------------------|
| `stage_fixed: false` on lint-only commands | No effect, clutters config | Omit the option |
| `skip: [merge, rebase]` on pre-commit | pre-commit doesn't run during these anyway | Omit the option |
| `parallel: false` with one command | No effect | Omit or use `parallel: true` at hook level |
| Hardcoded paths without checking existence | Breaks on different setups | Detect what exists first |
| Not using `root` for workspace commands | Commands fail to find files | Set `root` to workspace directory |
| Overly broad globs | Hooks run unnecessarily | Scope to relevant directories |
| Missing cross-workspace dependencies in glob | Changes to shared code don't trigger dependent hooks | Analyze imports and include dependencies |

## Execution Steps

When invoked, follow this sequence:

1. **Detect ecosystem** - Which language(s) does this repo use?
2. **Detect package manager** - npm/yarn/pnpm/bun/uv/cargo/go?
3. **Find workspaces** - Is this a monorepo? What packages exist?
4. **Detect available scripts** - What can we hook into?
5. **Check existing config** - Is there already a lefthook.yml?
6. **Analyze dependencies** - Which workspaces import from which?
7. **Generate/update config** - Create minimal, correct lefthook.yml
8. **Install lefthook** - Add as dev dependency, set up prepare script
9. **Validate** - Run hooks to verify they work
