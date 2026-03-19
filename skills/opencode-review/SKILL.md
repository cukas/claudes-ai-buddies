---
name: opencode-review
description: Code review via OpenCode — review uncommitted changes, branches, or commits
---

# /opencode-review — Code Review via OpenCode

Get a code review from OpenCode CLI. Reviews uncommitted changes by default, or specify a branch or commit.

## How to invoke

Run the wrapper script via Bash:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/opencode-run.sh" \
  --prompt "Additional review instructions (optional)" \
  --cwd "/path/to/repo" \
  --mode review \
  --review-target "uncommitted"
```

Then read the output file and present the review to the user.

## Step-by-step workflow

1. **Determine what to review:**
   - No arguments → review uncommitted changes (`--review-target uncommitted`)
   - User specifies a branch → `--review-target branch:branch-name`
   - User specifies a commit → `--review-target commit:SHA`
2. **Determine working directory.** Must be inside a git repository.
3. **Build the prompt.** The wrapper automatically fetches the diff and builds a review prompt. If the user provides extra instructions (e.g., "focus on security"), pass them as `--prompt`.
4. **Run opencode-run.sh** with `--mode review` via the Bash tool.
5. **Read the output file** using the Read tool.
6. **Present the review** to the user. Frame it as "OpenCode's code review:" with clear sections.
7. **Add your own perspective** if you see issues OpenCode missed, or agree with specific points.

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` | (optional) | Extra review instructions |
| `--cwd` | current dir | Working directory (must be a git repo) |
| `--mode` | `review` | Always `review` for this skill |
| `--review-target` | `uncommitted` | What to review |
| `--timeout` | from config (360s) | Max seconds to wait |
| `--model` | from config | Override the model (format: `provider/model`) |

## Review targets

| Target | Flag | Example |
|--------|------|---------|
| Uncommitted changes | `--review-target uncommitted` | `/opencode-review` |
| Branch diff | `--review-target branch:NAME` | `/opencode-review branch:feature/auth` |
| Specific commit | `--review-target commit:SHA` | `/opencode-review commit:abc1234` |

## Example invocations

- `/opencode-review` — review all uncommitted changes
- `/opencode-review branch:main` — review diff from main to HEAD
- `/opencode-review commit:a1b2c3d` — review a specific commit
- `/opencode-review "focus on security and SQL injection"` — review with extra instructions

## Rules

- **Always verify we're in a git repo** before running. If not, tell the user.
- **If no changes exist**, tell the user there's nothing to review instead of sending an empty diff.
- **Present both perspectives** — show OpenCode's review, then add your own observations.
- **Don't auto-apply suggestions** — present findings and let the user decide what to fix.
