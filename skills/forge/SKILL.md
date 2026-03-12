---
name: forge
description: Evolutionary multi-AI code forge — three AIs build, test, and cross-pollinate
---

# /forge — Evolutionary Multi-AI Code Forge

Three AI engines independently implement the same task, compete on automated fitness tests, then cross-pollinate improvements into one refined solution.

## How to invoke

**Direct forge** — user specifies a focused task:
```
/forge "Add NaN guard to scoring" --fitness "npx jest"
```

Optional flags:
- `--timeout SECS` — override the safety cap (default: 600s from config key `forge_timeout`)
- `--async` — run peer engines in background, continue conversation

## Using forge inside existing planning workflows

`/forge` works as a **tool within any plan** — `/build-guard`, `/plan-guarded`, plan mode, or any task list. It is NOT a separate planning system.

### The `[forge]` tag

When building a plan (in any workflow), Claude can tag tasks:
- `[forge]` — algorithmic, tricky, multiple valid approaches → three-way competition
- No tag or `[direct]` — straightforward → Claude handles normally

Example plan (from `/build-guard`, plan mode, or anywhere):
```
1. Add RetryConfig type to shared types
2. [forge] Implement exponential backoff with jitter algorithm
3. Wire retry config into python-manager.ts
4. [forge] Add circuit breaker pattern for repeated failures
5. Add retry status to UI connection indicator
```

### During execution

When Claude reaches a `[forge]` task, it runs the full forge workflow below (setup → diverge → fitness → scoreboard → converge), then continues with the next task in the plan.

**Between forge tasks**, commit the working state so each forge starts from a clean base.

### What to tag `[forge]`

- Algorithms, scoring logic, data transformations
- Race condition fixes, concurrency patterns
- Performance-critical code paths
- Anything with multiple valid approaches where three perspectives help

### What NOT to tag `[forge]`

- Types, imports, config, UI layout, wiring
- Boilerplate, glue code — one obvious answer
- Anything without a runnable fitness test

---

## Step-by-step workflow (single forge)

### Phase 0: Setup

1. **Parse args.** Extract the task, `--fitness` command, optional `--timeout`, and `--async` flag.
2. **Detect engines.** Source lib.sh and check binaries:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
CODEX_BIN=$(ai_buddies_find_codex 2>/dev/null) || CODEX_BIN=""
GEMINI_BIN=$(ai_buddies_find_gemini 2>/dev/null) || GEMINI_BIN=""
FORGE_TIMEOUT=$(ai_buddies_forge_timeout)  # config key, default 600
```

3. **Create forge directory and claude worktree:**

```bash
FORGE_ID="$(date +%s)-${RANDOM}"
FORGE_DIR="/tmp/ai-buddies-${CLAUDE_SESSION_ID:-default}/forge-${FORGE_ID}"
mkdir -p "$FORGE_DIR"

ENGINES=(claude)
git worktree add --detach "$FORGE_DIR/wt-claude" HEAD
[[ -n "$CODEX_BIN" ]]  && ENGINES+=(codex)
[[ -n "$GEMINI_BIN" ]] && ENGINES+=(gemini)
```

4. **Tell the user** how many engines are competing, the task, and what fitness will run.

### Phase 0.5: Speculative Test Generation (if no `--fitness`)

When `--fitness` is omitted, run the spectest pre-phase before proceeding:

```bash
SPECTEST_RESULT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-spectest.sh" \
  --task "$TASK" --cwd "$(pwd)" --timeout "$FORGE_TIMEOUT")
```

Read the proposals JSON. Each engine proposes test files and a run command. Claude reviews all proposals, picks or synthesizes the best fitness test, then presents it to the user for approval. Once approved, set `--fitness` to the chosen run command and proceed with the normal forge.

If running non-interactively (e.g., inside `--async` or automated pipeline), Claude picks the proposal with the broadest test coverage and proceeds automatically without user approval.

### Phase 1: Diverge (Claude implements)

**Claude implements first** in `$FORGE_DIR/wt-claude/` using Edit/Write tools with absolute paths.

### Phase 1.5: Dispatch peers via forge-run.sh

After Claude's implementation is complete, launch peer engines:

**Synchronous (default):**
```bash
MANIFEST_PATH=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-run.sh" \
  --forge-dir "$FORGE_DIR" \
  --task "$TASK" \
  --fitness "$FITNESS_CMD" \
  --timeout "$FORGE_TIMEOUT")
```

**Async (when `--async` flag is set):**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-run.sh" \
  --forge-dir "$FORGE_DIR" \
  --task "$TASK" \
  --fitness "$FITNESS_CMD" \
  --timeout "$FORGE_TIMEOUT"
```
Run the above via Bash tool with `run_in_background: true`. Tell user "Forge running in background, I'll show results when done." On completion notification, read `$FORGE_DIR/manifest.json` and proceed to Phase 2.

Check status while waiting (optional):
```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
ai_buddies_forge_status "$FORGE_DIR"  # "pending" | "done: winner=codex, engines=3"
```

### Phase 2: Read Results

Read `$FORGE_DIR/manifest.json`. It contains:

```json
{
  "forge_id": "...",
  "forge_dir": "...",
  "engines": ["claude","codex","gemini"],
  "task": "...",
  "results": {
    "<engine>": {
      "pass": true,
      "score": 85,
      "diff_lines": 27,
      "files_changed": 1,
      "duration_sec": 12,
      "lint_warnings": 0,
      "style_score": 95
    }
  },
  "patches": { "<engine>": "path/to/patch.diff" },
  "winner": "codex",
  "close_call": false
}
```

### Phase 3: Scoreboard

Present to user — columns for available engines only:

```markdown
## Forge Scoreboard: [task summary]

| | Engine 1 | Engine 2 | Engine 3 |
|---|---|---|---|
| Fitness | PASS/FAIL/TIMEOUT | ... | ... |
| Score | 85/100 | ... | ... |
| Duration | Xs | ... | ... |
| Files changed | N | ... | ... |
| Diff size | N lines | ... | ... |
| Lint warnings | N | ... | ... |
| Style score | N/100 | ... | ... |

**Winner:** [engine] — score X/100.
```

If `close_call` is true, note: "Close call (within 5 points) — consider reviewing both approaches."

Winner: highest composite score (pass required). If none passed, report failures and ask user.

### Phase 4: Cross-pollinate (optional)

Ask user: "Run a refinement round?" If yes, share all diffs + scores with each engine:

```
Three implementations with fitness results:
{each engine's diff and score}

Improve the winner by taking the best from all three. Make it pass: {fitness command}.
```

Claude refines its worktree. Send peers in parallel via a second `forge-run.sh` call. Run fitness again.

### Phase 5: Converge

**Ask user before applying.** Show winning diff. Options:
- **Apply:** Claude reads winning diff and applies via Edit tool (safer than `git apply`).
- **Cherry-pick:** Claude applies selected changes only.
- **Discard:** Clean up.

### Cleanup

**Always run**, regardless of outcome:

```bash
for engine in "${ENGINES[@]}"; do
  git worktree remove "$FORGE_DIR/wt-$engine" --force 2>/dev/null || true
done
rm -rf "$FORGE_DIR"
```

## Graceful degradation

- **3 engines:** Full three-way forge.
- **2 engines:** Two-way forge. 2-column scoreboard.
- **1 engine (solo):** Claude implements + fitness loop. No cross-pollination.
- **Timeout/error:** Mark in scoreboard, continue with remaining engines.

## Rules

- **Require `--fitness`** (or run spectest pre-phase to generate one).
- **Never touch user's working tree** until Phase 5 with explicit approval.
- **Always clean up** worktrees, even on error.
- **Time budget:** Default from `ai_buddies_forge_timeout()` config (600s). Engines self-exit when done. 120s for fitness. Two rounds max.
- **Check engine output** for `TIMEOUT:`/`ERROR:` markers before proceeding.
- **Stage before diffing:** `git add -A` then `git diff --cached` to capture new files.
- **Prompts from lib.sh:** Use `ai_buddies_build_forge_prompt()` — never inline prompt text.
