---
name: codex-review
description: Code review via OpenAI Codex — review uncommitted changes, branches, or commits
---

# /codex-review — Code Review via Codex

Get a code review from OpenAI's Codex CLI. Reviews uncommitted changes by default, or specify a branch or commit.

## How to invoke

Run the wrapper script via Bash. **IMPORTANT:** Codex regularly takes 3-6 minutes for non-trivial tasks. You MUST set the Bash tool's `timeout` parameter to `420000` (7 minutes) to prevent Claude Code from killing the process before Codex finishes.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.sh" \
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
4. **Run codex-run.sh** with `--mode review` via the Bash tool.
5. **Read the output file** using the Read tool.
6. **Present the review** to the user. Frame it as "Codex's code review:" with clear sections.
7. **Add your own perspective** if you see issues Codex missed, or agree with specific points.

## Review targets

| Target | Flag | Example |
|--------|------|---------|
| Uncommitted changes | `--review-target uncommitted` | `/codex-review` |
| Branch diff | `--review-target branch:NAME` | `/codex-review branch:feature/auth` |
| Specific commit | `--review-target commit:SHA` | `/codex-review commit:abc1234` |

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` | `""` | Additional instructions for the review |
| `--cwd` | current dir | Path to the git repository |
| `--mode` | — | Must be `review` for this skill |
| `--review-target` | `uncommitted` | What to review |
| `--timeout` | from config (360s) | Max seconds to wait |
| `--model` | from config | Override the Codex model |

## Example invocations

- `/codex-review` — review all uncommitted changes
- `/codex-review branch:main` — review diff from main to HEAD
- `/codex-review commit:a1b2c3d` — review a specific commit
- `/codex-review "focus on security and SQL injection"` — review with extra instructions

## Rules

- **Always verify we're in a git repo** before running. If not, tell the user.
- **If no changes exist**, tell the user there's nothing to review instead of sending an empty diff.
- **Present both perspectives** — show Codex's review, then add your own observations.
- **Don't auto-apply suggestions** — present findings and let the user decide what to fix.
